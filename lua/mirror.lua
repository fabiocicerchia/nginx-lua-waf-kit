-- Request-mirroring hook.
--
-- nginx's `mirror` directive already does the fire-and-forget subrequest. What
-- it does not do is decide *whether* to mirror, tie the two paths together, or
-- keep the shadow from doing damage. That is this module, and it is why the WAF
-- kit is built before dark-canary: this is dark-canary's capture layer.
--
-- Wiring (see ../examples/waf.conf.example):
--   set $dc_mirror 0;                         -- default off
--   access_by_lua_block { waf.mirror.decide() }
--   mirror /_shadow;                          -- nginx subrequests unconditionally...
--   location /_shadow { if ($dc_mirror = 0) { return 204; } proxy_pass ...; }
--
-- Safety posture, all on by default: reads only, low sampling, a kill switch
-- checked from local state on every request, PII scrubbed before anything
-- leaves the edge.

local _M = { _VERSION = "0.1.0" }

local DEFAULTS = {
  var           = "dc_mirror",         -- nginx variable gating the mirror location
  header        = "X-Dark-Canary-Id",  -- correlation id, injected on both paths
  sample_rate   = 0.01,                -- 1%: bounds load amplification on shared datastores
  reads_only    = true,                -- non-idempotent requests do real writes on the shadow
  kill_file     = "/etc/dark-canary/kill",
  kill_dict     = nil,                 -- optional shared dict holding a "kill" key
  kill_ttl      = 1,                   -- seconds to cache the kill-switch answer
  max_body      = 65536,
  scrub_headers = { "authorization", "cookie", "set-cookie", "x-api-key", "proxy-authorization" },
  scrub_args    = { "token", "password", "access_token", "api_key", "secret" },
  scrub_fields  = {},                  -- JSON body keys to redact, best effort
}

local REDACTED = "[redacted]"

local function merge(opts)
  local o = {}
  for k, v in pairs(DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  return o
end

local function set_lookup(list)
  local set = {}
  for _, v in ipairs(list or {}) do set[string.lower(v)] = true end
  return set
end

-- --- kill switch -------------------------------------------------------------
--
-- Must work when the control plane is down, so it reads only local state: a
-- shared dict flag (fast, set by whatever can still reach the control plane) or
-- a file on disk (works when nothing can). Cached for kill_ttl seconds, so the
-- happy path costs one clock read rather than one stat per request.

local kill_cache = { at = -math.huge, engaged = false }

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

function _M.killed(o, now)
  now = now or ngx.now()
  if now - kill_cache.at < o.kill_ttl then
    return kill_cache.engaged
  end

  local engaged = false
  if o.kill_dict then
    local dict = ngx.shared[o.kill_dict]
    if dict and dict:get("kill") then engaged = true end
  end
  if not engaged and o.kill_file and o.kill_file ~= "" then
    engaged = file_exists(o.kill_file)
  end

  kill_cache.at = now
  kill_cache.engaged = engaged
  return engaged
end

-- The cache is per worker; exposed for tests and for a reload hook.
function _M.reset_kill_cache()
  kill_cache.at = -math.huge
  kill_cache.engaged = false
end

-- --- decision ----------------------------------------------------------------

local IDEMPOTENT = { GET = true, HEAD = true, OPTIONS = true }

-- Pure, so the rules are testable without nginx. Returns allowed, reason.
function _M.should_mirror(o, method, roll, killed)
  if killed then return false, "kill switch engaged" end
  if o.reads_only and not IDEMPOTENT[method] then
    return false, "reads-only: " .. method .. " would write on the shadow"
  end
  if o.sample_rate <= 0 then return false, "sampling disabled" end
  if o.sample_rate < 1 and roll >= o.sample_rate then return false, "not sampled" end
  return true, "mirrored"
end

function _M.decide(opts)
  local o = merge(opts)

  local correl = ngx.var.request_id -- nginx >= 1.11.0: unique per request, free
  if not correl or correl == "" then
    correl = string.format("%08x%08x", math.random(0, 0xffffffff), math.random(0, 0xffffffff))
  end
  ngx.ctx.dc_correl_id = correl
  -- Injected on the primary request too, so the collector can pair the two
  -- sides without the shadow having to echo anything back.
  ngx.req.set_header(o.header, correl)

  local allowed, reason = _M.should_mirror(o, ngx.req.get_method(), math.random(), _M.killed(o))
  ngx.var[o.var] = allowed and "1" or "0"
  ngx.ctx.dc_mirror = allowed
  ngx.ctx.dc_reason = reason

  if allowed and o.max_body > 0 then
    ngx.req.read_body() -- the body must be read before it can be captured or scrubbed
  end
  return allowed, reason
end

-- --- scrubbing ---------------------------------------------------------------
--
-- Runs at the edge, before a capture is buffered or shipped, so PII never
-- reaches the collector or the UI in the first place. Body scrubbing is
-- deliberately a shallow key match: a real JSON walk means a parser in the
-- request path, and this is defence in depth, not the primary control.
-- ponytail: shallow "key":"value" match — swap in cjson-based redaction if
-- nested PII shows up in practice.

function _M.scrub_headers_table(headers, scrub)
  local out = {}
  for k, v in pairs(headers or {}) do
    out[k] = scrub[string.lower(k)] and REDACTED or v
  end
  return out
end

function _M.scrub_query(uri, scrub)
  if not uri then return uri end
  return (uri:gsub("([?&])([^=&]+)=([^&]*)", function(sep, key, value)
    if scrub[string.lower(key)] then return sep .. key .. "=" .. REDACTED end
    return sep .. key .. "=" .. value
  end))
end

function _M.scrub_body(body, fields)
  if not body or body == "" then return body end
  for _, field in ipairs(fields or {}) do
    body = body:gsub('("' .. field .. '"%s*:%s*)"[^"]*"', '%1"' .. REDACTED .. '"')
  end
  return body
end

-- --- capture -----------------------------------------------------------------

-- body_filter_by_lua: accumulate the response body up to max_body so the diff
-- engine has something to compare. Truncation is recorded, never silent.
function _M.body_filter(opts)
  local o = merge(opts)
  if not ngx.ctx.dc_mirror then return end

  local chunk, eof = ngx.arg[1], ngx.arg[2]
  if chunk and chunk ~= "" then
    local buf = ngx.ctx.dc_body or {}
    local size = (ngx.ctx.dc_body_size or 0) + #chunk
    if size <= o.max_body then
      buf[#buf + 1] = chunk
    else
      ngx.ctx.dc_body_truncated = true
    end
    ngx.ctx.dc_body = buf
    ngx.ctx.dc_body_size = size
  end
  if eof then
    ngx.ctx.dc_body_done = true
  end
end

-- log_by_lua: build the scrubbed capture. Returns the table so dark-canary (or
-- any other consumer) decides where to ship it.
function _M.capture(opts)
  local o = merge(opts)
  if not ngx.ctx.dc_mirror then return nil end

  local header_scrub = set_lookup(o.scrub_headers)
  local arg_scrub = set_lookup(o.scrub_args)

  return {
    correl_id   = ngx.ctx.dc_correl_id,
    path        = "primary",
    method      = ngx.req.get_method(),
    uri         = _M.scrub_query(ngx.var.request_uri, arg_scrub),
    status      = ngx.status,
    req_headers = _M.scrub_headers_table(ngx.req.get_headers(), header_scrub),
    res_headers = _M.scrub_headers_table(ngx.resp.get_headers(), header_scrub),
    body        = _M.scrub_body(table.concat(ngx.ctx.dc_body or {}), o.scrub_fields),
    truncated   = ngx.ctx.dc_body_truncated or false,
    latency_ms  = math.floor((ngx.now() - ngx.req.start_time()) * 1000),
    at          = ngx.now(),
  }
end

-- Ship one capture to the collector over a cosocket, from a timer so the
-- response is already on its way back to the client.
-- ponytail: one POST per capture; batch through a shared-dict queue if the log
-- phase ever shows up in the benchmarks.
function _M.ship(capture, collector)
  if not capture or not collector then return end
  local payload = require("cjson.safe").encode(capture)
  if not payload then return end

  local queued, err = ngx.timer.at(0, function(premature)
    if premature then return end
    local sock = ngx.socket.tcp()
    sock:settimeout(collector.timeout or 1000)
    local ok, cerr = sock:connect(collector.host, collector.port)
    if not ok then
      ngx.log(ngx.WARN, "dark-canary: collector unreachable: ", cerr)
      return
    end
    sock:send({
      "POST ", collector.path or "/captures", " HTTP/1.1\r\n",
      "Host: ", collector.host, "\r\n",
      "Content-Type: application/json\r\n",
      "Content-Length: ", #payload, "\r\n",
      "Connection: close\r\n\r\n",
      payload,
    })
    sock:close()
  end)
  if not queued then
    ngx.log(ngx.WARN, "dark-canary: could not queue capture: ", err)
  end
end

-- Convenience for the common wiring: capture, then ship.
function _M.log(opts)
  local o = merge(opts)
  _M.ship(_M.capture(o), o.collector)
end

_M.DEFAULTS = DEFAULTS
_M.REDACTED = REDACTED

return _M
