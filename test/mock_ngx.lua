-- A mock `ngx` good enough to exercise the modules' logic outside nginx.
--
-- Deliberately small: it covers the API surface the kit actually touches, so the
-- pure logic (algorithms, scoring, policy, claim checks) can be tested with any
-- Lua 5.1+ — including `resty test/run.lua` inside the image itself, where the
-- real ngx wins if it is present.

local M = {}

local function base64_decode(s)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  s = s:gsub("[^" .. chars .. "=]", "")
  local out = {}
  local bits, count = 0, 0
  for c in s:gmatch(".") do
    if c ~= "=" then
      local idx = chars:find(c, 1, true)
      if not idx then return nil end
      bits = bits * 64 + (idx - 1)
      count = count + 6
      if count >= 8 then
        count = count - 8
        local byte = math.floor(bits / 2 ^ count)
        bits = bits - byte * 2 ^ count
        out[#out + 1] = string.char(byte)
      end
    end
  end
  return table.concat(out)
end

-- A shared dict with the handful of methods the modules use.
local function new_dict()
  local store = {}
  local dict = {}
  function dict:get(k)
    local entry = store[k]
    if not entry then return nil end
    if entry.expires and entry.expires < (M.ngx and M.ngx.now() or 0) then
      store[k] = nil
      return nil
    end
    return entry.value
  end
  function dict:set(k, v, ttl)
    store[k] = { value = v, expires = ttl and ttl > 0 and (M.ngx.now() + ttl) or nil }
    return true
  end
  dict.safe_set = dict.set
  function dict:delete(k) store[k] = nil end
  function dict:flush_all() store = {} end
  return dict
end

function M.new(opts)
  opts = opts or {}
  local clock = opts.now or 0

  local ngx = {
    ctx = {},
    var = opts.var or {},
    header = {},
    status = opts.status or 200,
    shared = {},
    WARN = "warn", ERR = "err", INFO = "info",
    logs = {},
    exited = nil,
  }

  for _, name in ipairs(opts.dicts or { "waf_ratelimit", "waf_jwks" }) do
    ngx.shared[name] = new_dict()
  end

  function ngx.now() return clock end
  function ngx.time() return math.floor(clock) end
  function ngx.set_now(t) clock = t end
  function ngx.log(level, ...)
    local parts = {}
    for _, v in ipairs({ ... }) do parts[#parts + 1] = tostring(v) end
    ngx.logs[#ngx.logs + 1] = { level = level, message = table.concat(parts) }
  end
  function ngx.exit(status)
    ngx.exited = status
    return status
  end
  ngx.decode_base64 = base64_decode

  ngx.req = {
    headers = opts.headers or {},
    method = opts.method or "GET",
    raw = opts.raw_header,
    start = clock,
    set_headers = {},
  }
  function ngx.req.get_method() return ngx.req.method end
  function ngx.req.get_headers() return ngx.req.headers end
  function ngx.req.set_header(k, v) ngx.req.set_headers[k] = v end
  function ngx.req.read_body() ngx.req.body_read = true end
  function ngx.req.start_time() return ngx.req.start end
  if opts.raw_header then
    function ngx.req.raw_header() return opts.raw_header end
  else
    ngx.req.raw_header = nil
  end

  ngx.resp = {}
  function ngx.resp.get_headers() return opts.resp_headers or {} end

  ngx.timer = {}
  ngx.timer.queued = {}
  function ngx.timer.at(_, fn)
    ngx.timer.queued[#ngx.timer.queued + 1] = fn
    return true
  end

  M.ngx = ngx
  return ngx
end

return M
