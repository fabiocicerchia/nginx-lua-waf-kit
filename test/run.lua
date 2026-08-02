-- Assert-based tests for the WAF kit's pure logic.
--
--   lua test/run.lua          (any Lua 5.1+)
--   resty test/run.lua        (inside the nginx-lua image)
--
-- No framework: the point is that these run anywhere the modules can be loaded,
-- including a container with nothing but the interpreter.

package.path = "./lua/?.lua;./test/?.lua;" .. package.path

local mock = require("mock_ngx")

local passed, failed = 0, 0
local current = ""

local function test(name, fn)
  current = name
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("FAIL  ", name, "\n      ", tostring(err), "\n")
  end
end

local function check(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end

local function eq(got, want, msg)
  if got ~= want then
    error(string.format("%s: got %s, want %s", msg or current, tostring(got), tostring(want)), 2)
  end
end

local function near(got, want, tol, msg)
  if math.abs(got - want) > (tol or 1e-6) then
    error(string.format("%s: got %s, want ~%s", msg or current, tostring(got), tostring(want)), 2)
  end
end

-- ---------------------------------------------------------------- ratelimit --

_G.ngx = mock.new()
local ratelimit = require("ratelimit")

local function rl_opts(over)
  local o = { algo = "token-bucket", capacity = 5, rate = 1, window = 1 }
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

test("token bucket starts full and refills at the configured rate", function()
  local o = rl_opts()
  local state = {}
  for i = 1, 5 do
    local allowed
    allowed, state = ratelimit.step(state, 0, o)
    check(allowed, "request " .. i .. " should be admitted from a full bucket")
  end
  local allowed, _, retry = ratelimit.step(state, 0, o)
  check(not allowed, "the sixth request must be rejected")
  near(retry, 1, 0.01, "retry_after should be one token's worth of refill")

  local refilled = ratelimit.step(state, 2, o)
  check(refilled, "two seconds later the bucket has refilled")
end)

test("token bucket never refills past capacity", function()
  local o = rl_opts()
  local _, state = ratelimit.step({}, 0, o)
  local allowed
  for i = 1, 5 do
    allowed, state = ratelimit.step(state, 1000, o)
    check(allowed, "request " .. i .. " after a long idle should pass")
  end
  allowed = ratelimit.step(state, 1000, o)
  check(not allowed, "capacity must still cap the burst after an idle period")
end)

test("leaky bucket admits at the drain rate, not in bursts", function()
  local o = rl_opts({ algo = "leaky-bucket", capacity = 2, rate = 1 })
  local allowed, state = ratelimit.step({}, 0, o)
  check(allowed, "first request fits the empty bucket")
  allowed, state = ratelimit.step(state, 0, o)
  check(allowed, "second request fills it")
  allowed = ratelimit.step(state, 0, o)
  check(not allowed, "third overflows")

  local drained = ratelimit.step(state, 1.5, o)
  check(drained, "after draining, there is room again")
end)

test("fixed window resets on the boundary, which is its known flaw", function()
  local o = rl_opts({ algo = "fixed-window", capacity = 2, window = 10 })
  local state = {}
  local allowed
  allowed, state = ratelimit.step(state, 9.0, o); check(allowed)
  allowed, state = ratelimit.step(state, 9.5, o); check(allowed)
  allowed, state = ratelimit.step(state, 9.9, o); check(not allowed, "over the limit inside the window")
  allowed = ratelimit.step(state, 10.1, o)
  check(allowed, "the next window starts empty — 2x capacity across the boundary")
end)

test("sliding log is exact and expires entries by time", function()
  local o = rl_opts({ algo = "sliding-log", capacity = 2, window = 10 })
  local state = {}
  local allowed
  allowed, state = ratelimit.step(state, 0, o); check(allowed)
  allowed, state = ratelimit.step(state, 1, o); check(allowed)
  allowed, state = ratelimit.step(state, 2, o); check(not allowed, "limit reached")
  allowed, state = ratelimit.step(state, 10.5, o)
  check(allowed, "the entry at t=0 has aged out")
  eq(#state.log, 2, "the log must not grow past capacity")
end)

test("sliding counter smooths the boundary the fixed window jumps", function()
  local o = rl_opts({ algo = "sliding-counter", capacity = 2, window = 10 })
  local state = {}
  local allowed
  allowed, state = ratelimit.step(state, 9.0, o); check(allowed)
  allowed, state = ratelimit.step(state, 9.5, o); check(allowed)
  allowed, state = ratelimit.step(state, 9.9, o); check(not allowed, "over the limit inside the window")

  -- Just past the boundary the previous window is still 99% in view, so the
  -- weighted estimate leaves room for one request, not a whole fresh capacity.
  allowed, state = ratelimit.step(state, 10.1, o)
  check(allowed, "one request fits under the weighted estimate")
  allowed = ratelimit.step(state, 10.2, o)
  check(not allowed, "and the next does not — this is the boundary burst the fixed window allows")
end)

test("long algorithm spellings alias to the visualiser's names", function()
  local allowed = ratelimit.step({}, 0, rl_opts({ algo = "sliding-window-log", capacity = 1 }))
  check(allowed, "sliding-window-log should resolve to sliding-log")
end)

test("an unknown algorithm fails loudly rather than admitting everything", function()
  local ok = pcall(ratelimit.step, {}, 0, rl_opts({ algo = "nonsense" }))
  check(not ok, "an unknown algorithm must raise")
end)

test("state survives a round trip through the shared dict encoding", function()
  local _, state = ratelimit.step({}, 3, rl_opts())
  local back = ratelimit.decode(ratelimit.encode(state))
  near(back.tokens, state.tokens, 1e-9)
  near(back.at, state.at, 1e-9)

  local _, log_state = ratelimit.step({}, 1, rl_opts({ algo = "sliding-log", capacity = 3 }))
  local log_back = ratelimit.decode(ratelimit.encode(log_state))
  eq(#log_back.log, 1)
  near(log_back.log[1], 1, 1e-9)
end)

test("check() shares state across calls through the dict and fails open without one", function()
  local ngx = mock.new()
  _G.ngx = ngx
  ngx.var.remote_addr = "10.0.0.1"

  local o = rl_opts({ capacity = 2, key = "k" })
  check(ratelimit.check(o), "first")
  check(ratelimit.check(o), "second")
  check(not ratelimit.check(o), "third must see the state the first two wrote")

  local allowed, _, remaining = ratelimit.check(rl_opts({ dict = "does-not-exist" }))
  check(allowed, "a missing dict must fail open, not 503 every request")
  eq(remaining, -1)
  check(#ngx.logs > 0, "and it must say so in the error log")
end)

-- ------------------------------------------------------------------- mirror --

local mirror = require("mirror")

test("reads-only refuses to mirror anything that would write", function()
  local o = mirror.DEFAULTS
  local allowed, reason = mirror.should_mirror(o, "POST", 0, false)
  check(not allowed, "POST must not be mirrored by default")
  check(reason:find("reads%-only"), "the reason must name the rule: " .. reason)
  check(mirror.should_mirror(o, "GET", 0, false), "GET at roll 0 is inside a 1% sample")
end)

test("the kill switch beats every other rule", function()
  local o = { reads_only = false, sample_rate = 1 }
  check(not mirror.should_mirror(o, "GET", 0, true), "kill switch must win")
  check(mirror.should_mirror(o, "GET", 0, false))
end)

test("sampling bounds the load amplification", function()
  local o = { reads_only = true, sample_rate = 0.01 }
  check(mirror.should_mirror(o, "GET", 0.005, false), "under the rate is sampled")
  check(not mirror.should_mirror(o, "GET", 0.5, false), "over the rate is not")
  check(not mirror.should_mirror({ sample_rate = 0 }, "GET", 0, false), "zero disables mirroring")
end)

test("PII is scrubbed before a capture can leave the edge", function()
  local scrub = { authorization = true, cookie = true }
  local headers = mirror.scrub_headers_table({ Authorization = "Bearer abc", Accept = "*/*" }, scrub)
  eq(headers.Authorization, mirror.REDACTED)
  eq(headers.Accept, "*/*")

  local uri = mirror.scrub_query("/a?token=secret&page=2", { token = true })
  eq(uri, "/a?token=" .. mirror.REDACTED .. "&page=2")

  local body = mirror.scrub_body('{"email":"a@b.c","id":7}', { "email" })
  eq(body, '{"email":"' .. mirror.REDACTED .. '","id":7}')
end)

test("the kill switch is cached but not forever", function()
  local ngx = mock.new()
  _G.ngx = ngx
  mirror.reset_kill_cache()
  ngx.shared.kill = ngx.shared.waf_ratelimit

  local o = { kill_dict = "kill", kill_file = "", kill_ttl = 1 }
  eq(mirror.killed(o, 0), false)
  ngx.shared.kill:set("kill", "1")
  eq(mirror.killed(o, 0.5), false, "still inside the cache window")
  eq(mirror.killed(o, 1.5), true, "past the cache window it must see the flag")
end)

test("decide() sets the gate variable and the correlation id on both paths", function()
  local ngx = mock.new({ var = { request_id = "abc123" }, method = "GET" })
  _G.ngx = ngx
  mirror.reset_kill_cache()

  local allowed = mirror.decide({ sample_rate = 1, kill_file = "" })
  check(allowed)
  eq(ngx.var.dc_mirror, "1")
  eq(ngx.req.set_headers["X-Dark-Canary-Id"], "abc123")
  eq(ngx.ctx.dc_correl_id, "abc123")

  local ngx2 = mock.new({ var = { request_id = "def" }, method = "DELETE" })
  _G.ngx = ngx2
  mirror.reset_kill_cache()
  check(not mirror.decide({ sample_rate = 1, kill_file = "" }), "a DELETE must not be mirrored")
  eq(ngx2.var.dc_mirror, "0")
end)

test("the response body is buffered up to the cap and truncation is recorded", function()
  local ngx = mock.new()
  _G.ngx = ngx
  ngx.ctx.dc_mirror = true
  ngx.arg = { string.rep("x", 10), false }
  mirror.body_filter({ max_body = 12 })
  ngx.arg = { string.rep("y", 10), true }
  mirror.body_filter({ max_body = 12 })

  eq(ngx.ctx.dc_body_truncated, true, "the second chunk overflows the cap")
  eq(table.concat(ngx.ctx.dc_body), string.rep("x", 10), "only what fits is kept")
  eq(ngx.ctx.dc_body_done, true)
end)

-- ----------------------------------------------------------- bot heuristics --

local bots = require("bot_heuristics")

test("a self-identifying client scores high", function()
  local score, reasons = bots.score_request({
    headers = { ["user-agent"] = "curl/8.4.0", accept = "*/*" },
  }, bots.DEFAULTS)
  check(score >= 0.6, "curl should clear the default threshold, got " .. score)
  check(#reasons > 0, "and say why")
end)

test("a plausible browser scores low", function()
  local score = bots.score_request({
    headers = {
      ["user-agent"] = "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/124.0 Safari/537.36",
      accept = "text/html", ["accept-language"] = "en-GB", ["accept-encoding"] = "gzip",
    },
    order = { "host", "user-agent", "accept", "accept-language", "accept-encoding" },
  }, bots.DEFAULTS)
  check(score < 0.6, "a normal browser must not be flagged, got " .. score)
end)

test("missing headers and no user agent add up", function()
  local score = bots.score_request({ headers = {} }, bots.DEFAULTS)
  check(score >= 0.6, "no UA and no browser headers should clear the threshold, got " .. score)
end)

test("header order is scored by inversions against the browser order", function()
  eq(bots.order_penalty({ "host", "user-agent", "accept" }, bots.BROWSER_ORDER), 0)
  check(bots.order_penalty({ "accept-encoding", "accept", "user-agent", "host" }, bots.BROWSER_ORDER) > 0.9,
    "a fully reversed order is nearly all inversions")
  eq(bots.order_penalty({ "host", "x-custom" }, bots.BROWSER_ORDER), 0, "too few known headers to judge")
end)

test("a TLS fingerprint that contradicts the user agent is the strongest signal", function()
  local score = bots.score_request({
    headers = {
      ["user-agent"] = "Mozilla/5.0 Chrome/124.0", accept = "text/html",
      ["accept-language"] = "en", ["accept-encoding"] = "gzip",
    },
    order = bots.BROWSER_ORDER,
    ja3_family = "go-stdlib",
  }, bots.DEFAULTS)
  check(score >= 0.5, "a Chrome UA over a Go TLS stack should score high, got " .. score)
end)

test("the allowlist skips scoring entirely", function()
  local score = bots.score_request({ headers = { ["user-agent"] = "curl/8.4.0 statuscake" } },
    { allow_ua = { "statuscake" } })
  eq(score, 0)
end)

test("header order is read from the raw request, not the header hash", function()
  local order = bots.header_order("GET / HTTP/1.1\r\nHost: a\r\nUser-Agent: x\r\nAccept: */*\r\n\r\n")
  eq(order[1], "host")
  eq(order[2], "user-agent")
  eq(order[3], "accept")
end)

-- ------------------------------------------------------------------ geo_asn --

local geo = require("geo_asn")

test("CIDR matching handles prefixes, /32 and bad input", function()
  check(geo.in_cidr("10.0.0.5", "10.0.0.0/24"))
  check(not geo.in_cidr("10.0.1.5", "10.0.0.0/24"))
  check(geo.in_cidr("10.0.0.5", "10.0.0.5"), "a bare address is an implicit /32")
  check(geo.in_cidr("1.2.3.4", "0.0.0.0/0"))
  check(not geo.in_cidr("not-an-ip", "10.0.0.0/8"))
  check(not geo.in_cidr("999.1.1.1", "0.0.0.0/0"), "octets over 255 are not an address")
  check(not geo.in_cidr("2001:db8::1", "10.0.0.0/8"), "IPv6 falls through rather than matching")
end)

test("an allow CIDR beats every country and ASN rule", function()
  local allowed, why = geo.decide("10.1.2.3", "XX", 666, {
    allow_cidrs = { "10.0.0.0/8" }, deny_countries = { "XX" }, deny_asns = { 666 }, default_allow = true,
  })
  check(allowed, "the office range must never be lost to a country rule: " .. why)
end)

test("deny lists and allow lists behave as advertised", function()
  check(not (geo.decide("1.2.3.4", "XX", 1, { deny_countries = { "XX" }, default_allow = true })))
  check(geo.decide("1.2.3.4", "GB", 1, { deny_countries = { "XX" }, default_allow = true }))
  check(geo.decide("1.2.3.4", "GB", 1, { allow_countries = { "GB" }, default_allow = false }))
  check(not (geo.decide("1.2.3.4", "FR", 1, { allow_countries = { "GB" }, default_allow = true })),
    "an allowlist excludes everything not on it, whatever the default")
  check(not (geo.decide("1.2.3.4", "GB", 666, { deny_asns = { 666 }, default_allow = true })))
end)

test("a missing geoip2 variable falls back to the default instead of denying everything", function()
  local allowed, why = geo.decide("1.2.3.4", nil, nil, { allow_countries = { "GB" }, default_allow = true })
  check(allowed, "a broken geoip database must not black-hole the site")
  check(why:find("unknown"), "and it must say why: " .. why)
end)

-- ---------------------------------------------------------------------- jwt --

_G.ngx = mock.new()
local jwt = require("jwt")

local function b64url(s)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local chunk = {}
    for j = 1, 4 do
      local idx = math.floor(n / 2 ^ (24 - 6 * j)) % 64
      chunk[j] = chars:sub(idx + 1, idx + 1)
    end
    if not c then chunk[4] = "=" end
    if not b then chunk[3] = "=" end
    out[#out + 1] = table.concat(chunk)
  end
  return (table.concat(out):gsub("%+", "-"):gsub("/", "_"):gsub("=", ""))
end

-- A stand-in for cjson: only the shapes these tests use.
local function fake_json(s)
  if s:find('"alg"') then
    return { alg = s:match('"alg"%s*:%s*"([^"]+)"'), kid = s:match('"kid"%s*:%s*"([^"]+)"') }
  end
  local payload = { sub = s:match('"sub"%s*:%s*"([^"]+)"'), iss = s:match('"iss"%s*:%s*"([^"]+)"') }
  local exp = s:match('"exp"%s*:%s*(%d+)')
  if exp then payload.exp = tonumber(exp) end
  local aud = s:match('"aud"%s*:%s*"([^"]+)"')
  if aud then payload.aud = aud end
  return payload
end

test("base64url decoding handles padding and rejects nonsense", function()
  eq(jwt.b64url_decode(b64url("hello")), "hello")
  eq(jwt.b64url_decode(b64url("hi")), "hi")
  eq(jwt.b64url_decode(b64url("a")), "a")
  check(jwt.b64url_decode("a") == nil, "a one-character segment is not valid base64")
end)

test("parse splits a token without trusting it", function()
  local token = b64url('{"alg":"HS256"}') .. "." .. b64url('{"sub":"u1"}') .. ".sig"
  local parsed = jwt.parse("Bearer " .. token, fake_json)
  check(parsed, "should parse")
  eq(parsed.header.alg, "HS256")
  eq(parsed.payload.sub, "u1")
  eq(parsed.signing_input, token:match("^(.-%..-)%."), "the signing input is header.payload")

  check(jwt.parse("not.a", fake_json) == nil)
  check(jwt.parse(nil, fake_json) == nil)
end)

test("claim checks honour expiry, nbf, issuer, audience and leeway", function()
  local o = { leeway = 60, issuer = "https://issuer", audience = "api" }
  check(jwt.check_claims({ exp = 1000, iss = "https://issuer", aud = "api" }, o, 900))
  check(not jwt.check_claims({ exp = 1000 }, { leeway = 0 }, 1001), "expired")
  check(jwt.check_claims({ exp = 1000 }, { leeway = 60 }, 1030), "leeway covers clock skew")
  check(not jwt.check_claims({ nbf = 1000 }, { leeway = 0 }, 900), "not yet valid")
  check(not jwt.check_claims({ iss = "other" }, { issuer = "https://issuer" }, 0))
  check(not jwt.check_claims({ aud = "web" }, { audience = "api" }, 0))
  check(jwt.check_claims({ aud = { "web", "api" } }, { audience = "api" }, 0), "aud may be a list")
  check(not jwt.check_claims({ exp = "soon" }, { leeway = 0 }, 0), "a non-numeric exp is not a valid claim")
end)

test("HMAC follows RFC 2104 rather than hashing the key and message together", function()
  -- A fake SHA-256 that records what it was fed, so the construction can be
  -- checked without a real hash implementation.
  local calls = {}
  local function fake_sha()
    local buf = {}
    return {
      update = function(_, s) buf[#buf + 1] = s end,
      final = function()
        local joined = table.concat(buf)
        calls[#calls + 1] = joined
        return string.rep(string.char(#joined % 256), 32)
      end,
      reset = function() buf = {} end,
    }
  end

  local out = jwt.hmac_sha256("key", "message", fake_sha)
  eq(#out, 32, "the digest length must come through unchanged")
  eq(#calls, 2, "inner and outer hash, not one pass")
  eq(#calls[1], 64 + #"message", "inner hash is the ipad block plus the message")
  eq(#calls[2], 64 + 32, "outer hash is the opad block plus the inner digest")
  check(calls[1]:sub(1, 64) ~= calls[2]:sub(1, 64), "the two pads must differ")
end)

test("constant-time comparison rejects length and content mismatches", function()
  check(jwt.constant_time_equal("abc", "abc"))
  check(not jwt.constant_time_equal("abc", "abd"))
  check(not jwt.constant_time_equal("abc", "ab"))
  check(not jwt.constant_time_equal("abc", nil))
end)

test("alg:none and unlisted algorithms are refused before any verification", function()
  _G.ngx = mock.new()
  package.loaded["cjson.safe"] = { decode = fake_json, encode = function() return "{}" end }

  local token = b64url('{"alg":"none"}') .. "." .. b64url('{"sub":"u1"}') .. "."
  local payload, err = jwt.validate(token, { algorithms = { HS256 = true }, secret = "s" })
  check(payload == nil, "alg:none must never validate")
  check(err:find("not accepted"), err)

  local hs = b64url('{"alg":"HS512"}') .. "." .. b64url('{"sub":"u1"}') .. ".x"
  local _, err2 = jwt.validate(hs, { algorithms = { HS256 = true }, secret = "s" })
  check(err2:find("not accepted"), err2)
end)

test("an asymmetric token fails closed when the verifier is unavailable", function()
  _G.ngx = mock.new()
  package.loaded["cjson.safe"] = { decode = fake_json, encode = function() return "{}" end }
  package.loaded["resty.openssl.pkey"] = nil

  local token = b64url('{"alg":"RS256","kid":"k1"}') .. "." .. b64url('{"sub":"u1"}') .. ".sig"
  local payload = jwt.validate(token, { algorithms = { RS256 = true }, jwks = "https://issuer/jwks" })
  check(payload == nil, "an unverifiable token must be rejected, never passed through")
end)

-- ------------------------------------------------------------------ summary --

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
