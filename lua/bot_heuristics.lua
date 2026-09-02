-- Bot heuristics on header and TLS fingerprints.
--
-- Not a bot *blocker*: a scorer. It returns a 0..1 score and the reasons behind
-- it, and the operator picks the threshold and the action. Anything that
-- silently blocks on a heuristic eventually blocks a customer, and the reasons
-- are what makes that debuggable at 3am.
--
-- Signals, cheapest first:
--   * headers a real browser always sends, missing
--   * header *order* — browsers are consistent, hand-rolled clients are not
--   * self-identifying user agents (curl, python-requests, headless Chrome)
--   * TLS fingerprint mismatch: a JA3 that says "Go stdlib" behind a UA that
--     says "Chrome" is the strongest signal here. Optional — it needs a JA3 the
--     nginx build actually provides.

local _M = { _VERSION = "0.1.0" }

local DEFAULTS = {
  threshold = 0.6,   -- score at or above this counts as a bot
  status    = 403,
  log_only  = true,  -- score first, enforce later: the safe default
  allow_ua  = {},    -- substrings that skip scoring entirely (your own monitoring)
}

-- Headers every mainstream browser sends. Absence is not proof, which is why
-- each contributes only a fraction of the score.
local EXPECTED = { "accept", "accept-language", "accept-encoding", "user-agent" }

-- The client telling you what it is. Honest automation is still automation, and
-- this is the cheapest signal available.
local SELF_IDENTIFYING = {
  "curl/", "wget/", "python-requests", "python-urllib", "go-http-client",
  "java/", "okhttp", "libwww-perl", "scrapy", "httpclient", "axios/",
  "headlesschrome", "phantomjs", "puppeteer", "playwright", "bot", "crawler", "spider",
}

-- Browsers emit these in a stable relative order. A client that sends
-- user-agent after accept-encoding is not a browser pretending well.
local BROWSER_ORDER = { "host", "user-agent", "accept", "accept-language", "accept-encoding" }

local function contains_any(haystack, needles)
  if not haystack then return nil end
  local lower = string.lower(haystack)
  for _, needle in ipairs(needles or {}) do
    if lower:find(needle, 1, true) then return needle end
  end
  return nil
end

-- Counting inversions against the expected order. A longest-increasing-
-- subsequence would be exact; at five headers this answers the same question in
-- two loops. Returns 0..1.
function _M.order_penalty(order, expected)
  local rank = {}
  for i, name in ipairs(expected or BROWSER_ORDER) do rank[name] = i end

  local seen = {}
  for _, name in ipairs(order or {}) do
    local r = rank[string.lower(name)]
    if r then seen[#seen + 1] = r end
  end
  if #seen < 3 then return 0 end -- too few known headers to judge

  local inversions, checked = 0, 0
  for i = 1, #seen do
    for j = i + 1, #seen do
      checked = checked + 1
      if seen[i] > seen[j] then inversions = inversions + 1 end
    end
  end
  return inversions / checked
end

-- --- signals -----------------------------------------------------------------
--
-- One per signal in the header comment, each a pure (req, headers, ua) and each
-- returning its points and the reason that earned them — or nothing when the
-- signal does not fire. The weight lives at its single use because it is only
-- meaningful next to the thing it weighs; SIGNALS below is the whole policy,
-- and its order is the order the reasons come back in.

local function user_agent_signal(_, _, ua)
  if not ua or ua == "" then return 0.35, "no user agent" end
  local hit = contains_any(ua, SELF_IDENTIFYING)
  if hit then return 0.5, "self-identifying client: " .. hit end
end

local function missing_header_signal(_, headers, _)
  local missing = {}
  for _, name in ipairs(EXPECTED) do
    if not headers[name] then missing[#missing + 1] = name end
  end
  if #missing > 0 then
    return 0.15 * #missing, "missing " .. table.concat(missing, ", ")
  end
end

local function header_order_signal(req, _, _)
  if not req.order then return end
  local penalty = _M.order_penalty(req.order, BROWSER_ORDER)
  if penalty > 0 then return 0.3 * penalty, "unusual header order" end
end

-- The strongest signal available when the build provides a JA3: a TLS stack
-- that does not match the browser the UA claims to be.
local function tls_fingerprint_signal(req, _, ua)
  if not req.ja3_family or not ua then return end
  local claims_browser = contains_any(ua, { "chrome", "firefox", "safari", "edge" })
  if claims_browser and req.ja3_family ~= "browser" then
    return 0.5, "TLS fingerprint (" .. req.ja3_family .. ") contradicts the user agent"
  end
end

local SIGNALS = {
  user_agent_signal,
  missing_header_signal,
  header_order_signal,
  tls_fingerprint_signal,
}

-- Pure: everything the scorer needs is passed in. `req` is
-- { headers = {...}, order = {...}, ja3_family = "..." }.
function _M.score_request(req, opts)
  local o = opts or DEFAULTS
  local headers = req.headers or {}
  local ua = headers["user-agent"]

  if ua and contains_any(ua, o.allow_ua) then
    return 0, { "allowlisted user agent" }
  end

  local score, reasons = 0, {}
  for _, signal in ipairs(SIGNALS) do
    local points, reason = signal(req, headers, ua)
    if points then
      score = score + points
      reasons[#reasons + 1] = reason
    end
  end

  if score > 1 then score = 1 end
  return score, reasons
end

-- Header order as it came off the wire. This is the whole point: the hash table
-- from get_headers() has no order left to inspect.
function _M.header_order(raw)
  local order = {}
  for line in (raw or ""):gmatch("[^\r\n]+") do
    local name = line:match("^([%w%-]+):")
    if name then order[#order + 1] = string.lower(name) end
  end
  return order
end

local function merge(opts)
  local o = {}
  for k, v in pairs(DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  return o
end

-- access_by_lua entry point. Returns score, reasons; enforces only when
-- log_only is off and the score clears the threshold.
function _M.score(opts)
  local o = merge(opts)

  local headers = ngx.req.get_headers()
  local order = nil
  if ngx.req.raw_header then
    order = _M.header_order(ngx.req.raw_header(true))
  end

  local score, reasons = _M.score_request({
    headers = headers,
    order = order,
    ja3_family = o.ja3_family or ngx.var.http_x_ja3_family,
  }, o)

  ngx.ctx.bot_score = score
  ngx.ctx.bot_reasons = reasons

  if score >= o.threshold then
    ngx.log(ngx.WARN, "bot_heuristics: score ", score, " (", table.concat(reasons, "; "), ")")
    if not o.log_only then return ngx.exit(o.status) end
  end
  return score, reasons
end

_M.DEFAULTS = DEFAULTS
_M.SELF_IDENTIFYING = SELF_IDENTIFYING
_M.BROWSER_ORDER = BROWSER_ORDER

return _M
