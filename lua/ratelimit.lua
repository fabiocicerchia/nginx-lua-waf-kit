-- Shared-dict rate limiting.
--
-- The five algorithms are the five the /ratelimit visualiser explains, under the
-- same names and the same semantics, so what an operator saw in the browser is
-- what the edge does. Each algorithm is a pure function of (state, now, opts) —
-- that is what the tests exercise, and it is why the visualiser and the edge
-- cannot quietly drift apart.
--
-- State lives in ngx.shared.DICT so limits are shared across worker processes.
--
-- ponytail: read-modify-write on the shared dict is not atomic, so a burst
-- across workers can over-admit by roughly (workers - 1) requests. That is the
-- same trade lua-resty-limit-req makes and the right one at this cost; if
-- exactness ever matters more than latency, wrap the read/write in resty.lock.

local _M = { _VERSION = "0.1.0" }

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local DEFAULTS = {
  dict     = "waf_ratelimit",
  algo     = "token-bucket",
  capacity = 20,      -- bucket size, or requests allowed per window
  rate     = 10,      -- refill / leak rate, requests per second
  window   = 1,       -- seconds, for the window algorithms
  key      = nil,     -- defaults to the client address
  status   = 429,
  log_only = false,   -- score and log but never reject: how you roll this out safely
}

-- --- algorithms --------------------------------------------------------------
--
-- Each returns: allowed, new_state, retry_after_seconds, remaining.

local A = {}

-- Classic token bucket: capacity tokens, refilled at `rate` per second.
-- Absorbs bursts, which is usually what an API wants.
A["token-bucket"] = function(state, now, o)
  local tokens = state.tokens or o.capacity
  tokens = min(o.capacity, tokens + (now - (state.at or now)) * o.rate)
  if tokens >= 1 then
    return true, { tokens = tokens - 1, at = now }, 0, floor(tokens - 1)
  end
  return false, { tokens = tokens, at = now }, (1 - tokens) / o.rate, 0
end

-- Leaky bucket as a queue: the bucket drains at a constant `rate` and a request
-- is admitted only if it fits. Smooths output instead of absorbing bursts.
A["leaky-bucket"] = function(state, now, o)
  local level = max(0, (state.level or 0) - (now - (state.at or now)) * o.rate)
  if level + 1 <= o.capacity then
    return true, { level = level + 1, at = now }, 0, floor(o.capacity - level - 1)
  end
  return false, { level = level, at = now }, (level + 1 - o.capacity) / o.rate, 0
end

-- Fixed window: cheapest, and the one with the boundary problem — up to 2×
-- capacity can pass across a window edge. The visualiser shows exactly this.
A["fixed-window"] = function(state, now, o)
  local window_start = floor(now / o.window) * o.window
  local count = (state.start == window_start) and state.count or 0
  if count < o.capacity then
    return true, { start = window_start, count = count + 1 }, 0, o.capacity - count - 1
  end
  return false, { start = window_start, count = count }, window_start + o.window - now, 0
end

-- Sliding log: exact, at the cost of one stored timestamp per admitted request.
-- The log is capped at `capacity` entries — beyond the limit the extra
-- timestamps change no decision, and an uncapped log is a memory leak with a
-- rate limiter attached.
A["sliding-log"] = function(state, now, o)
  local cutoff = now - o.window
  local kept = {}
  for _, t in ipairs(state.log or {}) do
    if t > cutoff then kept[#kept + 1] = t end
  end
  if #kept < o.capacity then
    kept[#kept + 1] = now
    return true, { log = kept }, 0, o.capacity - #kept
  end
  return false, { log = kept }, kept[1] + o.window - now, 0
end

-- Sliding counter: the practical compromise. Two counters, with the previous
-- window weighted by how much of it is still in view.
A["sliding-counter"] = function(state, now, o)
  local window_start = floor(now / o.window) * o.window
  local cur, prev = 0, 0
  if state.start == window_start then
    cur, prev = state.count or 0, state.prev or 0
  elseif state.start == window_start - o.window then
    prev = state.count or 0
  end

  local elapsed = (now - window_start) / o.window
  local estimate = prev * (1 - elapsed) + cur
  if estimate < o.capacity then
    return true, { start = window_start, count = cur + 1, prev = prev }, 0, floor(o.capacity - estimate - 1)
  end
  return false, { start = window_start, count = cur, prev = prev }, window_start + o.window - now, 0
end

-- The visualiser's names are canonical; the long spellings are accepted because
-- that is what people type from memory.
local ALIASES = {
  ["sliding-window-log"] = "sliding-log",
  ["sliding-window-counter"] = "sliding-counter",
}

_M.algorithms = A

function _M.step(state, now, o)
  local name = ALIASES[o.algo] or o.algo
  local algo = A[name]
  if not algo then
    error("ratelimit: unknown algorithm '" .. tostring(o.algo) .. "'")
  end
  return algo(state or {}, now, o)
end

-- --- shared dict plumbing ----------------------------------------------------
--
-- Serialised with the smallest thing that works: fixed fields joined by "|", and
-- the timestamp log as a comma-separated list. cjson would cost an encode and a
-- decode per request in the hot path for no benefit at this shape.

local function encode(state)
  if state.log then
    return "L|" .. table.concat(state.log, ",")
  end
  return table.concat({
    "S", state.tokens or "", state.level or "", state.at or "",
    state.start or "", state.count or "", state.prev or "",
  }, "|")
end

local function decode(raw)
  if not raw then return {} end
  if raw:sub(1, 2) == "L|" then
    local log = {}
    for t in raw:sub(3):gmatch("[^,]+") do log[#log + 1] = tonumber(t) end
    return { log = log }
  end
  -- Trailing separator + an anchored capture: "[^|]*" alone also matches the
  -- empty string between two "|", which shifts every field one slot and decodes
  -- the whole state as nil — i.e. a full bucket on every request.
  local fields = {}
  for f in (raw .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = f end
  return {
    tokens = tonumber(fields[2]), level = tonumber(fields[3]), at = tonumber(fields[4]),
    start = tonumber(fields[5]), count = tonumber(fields[6]), prev = tonumber(fields[7]),
  }
end

_M.encode, _M.decode = encode, decode

local function merge(opts)
  local o = {}
  for k, v in pairs(DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  return o
end

-- Decides without rejecting. Returns allowed, retry_after, remaining.
function _M.check(opts)
  local o = merge(opts)
  local dict = ngx.shared[o.dict]
  if not dict then
    -- Fail open, loudly: a missing lua_shared_dict is a config error, and
    -- 503-ing every request because of one is worse than not limiting.
    ngx.log(ngx.ERR, "ratelimit: no lua_shared_dict named '", o.dict, "' — failing open")
    return true, 0, -1
  end

  local key = o.key or ngx.var.binary_remote_addr or ngx.var.remote_addr
  local dict_key = o.algo .. ":" .. key
  local now = ngx.now()

  local allowed, state, retry_after, remaining = _M.step(decode(dict:get(dict_key)), now, o)

  -- The TTL covers the longest time this state can still change a decision, so
  -- idle keys expire themselves and the dict never needs sweeping.
  local ttl = max(o.window, o.capacity / max(o.rate, 0.001)) * 2
  dict:set(dict_key, encode(state), ttl)

  return allowed, retry_after, remaining
end

-- access_by_lua entry point: rejects with 429 and a Retry-After header.
function _M.limit(opts)
  local o = merge(opts)
  local allowed, retry_after, remaining = _M.check(o)

  if remaining >= 0 then
    ngx.header["X-RateLimit-Remaining"] = remaining
  end
  if allowed then return true end

  if o.log_only then
    ngx.log(ngx.WARN, "ratelimit: would reject ", tostring(ngx.var.remote_addr),
      ": over limit (log_only)")
    return true
  end

  ngx.header["Retry-After"] = ceil(retry_after)
  return ngx.exit(o.status)
end

_M.DEFAULTS = DEFAULTS

return _M
