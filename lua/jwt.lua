-- Edge JWT validation: verify the signature and the standard claims here, so
-- upstreams only ever see authenticated traffic.
--
-- Structure: the parsing and claim checks are pure Lua and unit-tested; the
-- signature verification is the only part that needs the runtime. HS256 is
-- built from OpenResty's bundled resty.sha256 (HMAC by construction, no extra
-- module); RS256/ES256 use lua-resty-openssl when it is installed and fail
-- closed with a clear message when it is not.
--
-- Verification is NOT optional and NOT skippable by config. A JWT library with
-- an "unverified" mode is how `alg: none` bugs ship — the `alg` header here is
-- only ever used to *select* an algorithm from a fixed table, never to decide
-- whether to check.

local _M = { _VERSION = "0.1.0" }

local DEFAULTS = {
  algorithms  = { HS256 = true, RS256 = true },  -- what this deployment accepts
  secret      = nil,                             -- HS256 shared secret
  jwks        = nil,                             -- JWKS URL for RS256/ES256
  jwks_dict   = "waf_jwks",                      -- shared dict caching the JWKS
  jwks_ttl    = 3600,
  issuer      = nil,
  audience    = nil,
  leeway      = 60,                              -- seconds of clock skew tolerated
  header      = "Authorization",
  status      = 401,
  forward_sub = "X-Auth-Sub",                    -- pass the verified subject upstream
}

-- --- base64url ---------------------------------------------------------------

function _M.b64url_decode(s)
  if not s or s == "" then return nil end
  s = s:gsub("-", "+"):gsub("_", "/")
  local pad = #s % 4
  if pad == 2 then s = s .. "=="
  elseif pad == 3 then s = s .. "="
  elseif pad == 1 then return nil -- not a valid base64 length
  end
  if ngx and ngx.decode_base64 then return ngx.decode_base64(s) end
  return nil
end

-- --- parsing -----------------------------------------------------------------

-- Splits and decodes without verifying anything. Every caller of this must
-- verify before trusting a single field.
function _M.parse(token, decode_json)
  if type(token) ~= "string" then return nil, "no token" end
  token = token:gsub("^%s*[Bb]earer%s+", "")

  local h, p, s = token:match("^([%w%-_]+)%.([%w%-_]+)%.([%w%-_]*)$")
  if not h then return nil, "malformed token" end

  local header_json, payload_json = _M.b64url_decode(h), _M.b64url_decode(p)
  if not header_json or not payload_json then return nil, "malformed token" end

  local header = decode_json(header_json)
  local payload = decode_json(payload_json)
  if type(header) ~= "table" or type(payload) ~= "table" then return nil, "malformed token" end

  return {
    header = header,
    payload = payload,
    signature = s,
    signing_input = h .. "." .. p,
  }
end

-- --- claims ------------------------------------------------------------------

local function audience_ok(aud, expected)
  if not expected then return true end
  if type(aud) == "string" then return aud == expected end
  if type(aud) == "table" then
    for _, a in ipairs(aud) do
      if a == expected then return true end
    end
  end
  return false
end

-- Pure. Returns ok, error message.
function _M.check_claims(payload, o, now)
  local leeway = o.leeway or 0

  if payload.exp then
    if type(payload.exp) ~= "number" then return false, "exp is not a number" end
    if now - leeway >= payload.exp then return false, "token expired" end
  end
  if payload.nbf then
    if type(payload.nbf) ~= "number" then return false, "nbf is not a number" end
    if now + leeway < payload.nbf then return false, "token not yet valid" end
  end
  if o.issuer and payload.iss ~= o.issuer then
    return false, "unexpected issuer"
  end
  if not audience_ok(payload.aud, o.audience) then
    return false, "unexpected audience"
  end
  return true
end

-- --- signature ---------------------------------------------------------------

-- HMAC-SHA256 built from the SHA-256 primitive OpenResty already ships, so this
-- module needs no lua-resty-hmac. RFC 2104: H((K ^ opad) || H((K ^ ipad) || m)).
local function xor_pad(key, byte)
  local out = {}
  for i = 1, 64 do
    local k = i <= #key and key:byte(i) or 0
    -- No bit library in plain Lua 5.1; a 256-entry XOR is not worth it either,
    -- so do it arithmetically, one bit at a time.
    local x, bit_value, result = k, 1, 0
    local pad = byte
    for _ = 1, 8 do
      local kb, pb = x % 2, pad % 2
      if kb ~= pb then result = result + bit_value end
      x, pad, bit_value = math.floor(x / 2), math.floor(pad / 2), bit_value * 2
    end
    out[i] = string.char(result)
  end
  return table.concat(out)
end

function _M.hmac_sha256(key, message, sha256_new)
  local sha = sha256_new()
  if #key > 64 then
    sha:update(key)
    key = sha:final()
    sha:reset()
  end

  sha:update(xor_pad(key, 0x36))
  sha:update(message)
  local inner = sha:final()

  sha:reset()
  sha:update(xor_pad(key, 0x5c))
  sha:update(inner)
  return sha:final()
end

local function constant_time_equal(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do
    if a:byte(i) ~= b:byte(i) then diff = diff + 1 end
  end
  return diff == 0
end

_M.constant_time_equal = constant_time_equal

local function verify_hs256(parsed, o)
  if not o.secret then return false, "HS256 configured without a secret" end
  local ok, sha256 = pcall(require, "resty.sha256")
  if not ok then return false, "resty.sha256 unavailable" end

  local expected = _M.hmac_sha256(o.secret, parsed.signing_input, function() return sha256:new() end)
  local got = _M.b64url_decode(parsed.signature)
  return constant_time_equal(expected, got or ""), "signature mismatch"
end

local function verify_asymmetric(parsed, o, alg)
  local ok, pkey = pcall(require, "resty.openssl.pkey")
  if not ok then
    -- Fail closed: an unverifiable token is not a valid token.
    return false, alg .. " needs lua-resty-openssl, which is not installed"
  end
  local jwk, err = _M.jwks_key(o, parsed.header.kid)
  if not jwk then return false, err or "no key for kid" end

  local key, kerr = pkey.new(jwk)
  if not key then return false, "unusable JWKS key: " .. tostring(kerr) end

  local digest = alg == "ES256" and "sha256" or "sha256"
  local sig = _M.b64url_decode(parsed.signature)
  if not sig then return false, "malformed signature" end
  return key:verify(sig, parsed.signing_input, digest) == true, "signature mismatch"
end

-- --- JWKS --------------------------------------------------------------------

-- Cached in a shared dict so one fetch serves every worker, and a fetch failure
-- keeps serving the cached keys rather than rejecting all traffic.
function _M.jwks_key(o, kid)
  if not o.jwks then return nil, "no JWKS configured" end
  local dict = ngx.shared[o.jwks_dict]
  local cached = dict and dict:get("jwks")

  if not cached then
    local body, err = _M.fetch(o.jwks)
    if not body then
      return nil, "JWKS fetch failed: " .. tostring(err)
    end
    if dict then dict:set("jwks", body, o.jwks_ttl) end
    cached = body
  end

  local keys = require("cjson.safe").decode(cached)
  if type(keys) ~= "table" or type(keys.keys) ~= "table" then return nil, "malformed JWKS" end
  for _, key in ipairs(keys.keys) do
    if not kid or key.kid == kid then
      return require("cjson.safe").encode(key)
    end
  end
  return nil, "no key matching kid"
end

-- Overridable so tests (and anyone using a different HTTP client) can swap it.
function _M.fetch(url)
  local ok, http = pcall(require, "resty.http")
  if not ok then return nil, "resty.http not installed" end
  local client = http.new()
  client:set_timeout(2000)
  local res, err = client:request_uri(url, { method = "GET" })
  if not res then return nil, err end
  if res.status ~= 200 then return nil, "HTTP " .. res.status end
  return res.body
end

-- --- entry points ------------------------------------------------------------

local function merge(opts)
  local o = {}
  for k, v in pairs(DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  return o
end

-- Returns payload, error. Verifies the signature and the claims; never returns a
-- payload it has not verified.
function _M.validate(token, opts)
  local o = merge(opts)
  local decode = require("cjson.safe").decode

  local parsed, err = _M.parse(token, decode)
  if not parsed then return nil, err end

  local alg = parsed.header.alg
  if type(alg) ~= "string" or not o.algorithms[alg] then
    -- This is where `alg: none` dies.
    return nil, "algorithm not accepted: " .. tostring(alg)
  end

  local ok, reason
  if alg == "HS256" then
    ok, reason = verify_hs256(parsed, o)
  else
    ok, reason = verify_asymmetric(parsed, o, alg)
  end
  if not ok then return nil, reason end

  local claims_ok, claims_err = _M.check_claims(parsed.payload, o, ngx.time())
  if not claims_ok then return nil, claims_err end

  return parsed.payload
end

-- access_by_lua entry point: 401s unauthenticated traffic before it reaches the
-- upstream, and forwards the verified subject.
function _M.require_token(opts)
  local o = merge(opts)
  local payload, err = _M.validate(ngx.var["http_" .. o.header:lower():gsub("-", "_")], o)
  if not payload then
    ngx.log(ngx.WARN, "jwt: rejected: ", err)
    ngx.header["WWW-Authenticate"] = 'Bearer error="invalid_token"'
    return ngx.exit(o.status)
  end
  ngx.ctx.jwt = payload
  if o.forward_sub and payload.sub then
    ngx.req.set_header(o.forward_sub, payload.sub)
  end
  return payload
end

_M.DEFAULTS = DEFAULTS

return _M
