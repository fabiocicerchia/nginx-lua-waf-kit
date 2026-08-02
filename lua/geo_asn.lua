-- Geo / ASN allow-deny.
--
-- The MaxMind lookup is NOT done here. nginx's ngx_http_geoip2_module already
-- reads the .mmdb and puts the answer in variables; parsing a binary database in
-- Lua on every request to learn the same thing would be slower and wrong more
-- often. This module is the policy layer over those variables:
--
--   geoip2 /usr/share/GeoIP/GeoLite2-Country.mmdb { $geoip2_country_code country iso_code; }
--   geoip2 /usr/share/GeoIP/GeoLite2-ASN.mmdb     { $geoip2_asn autonomous_system_number; }
--
-- Precedence, in order: explicit CIDR allow, explicit CIDR deny, allow lists,
-- deny lists, default. CIDR entries come first because "our office" and "our
-- monitoring" must never be lost to a country rule.

local _M = { _VERSION = "0.1.0" }

local DEFAULTS = {
  default_allow  = true,   -- deny-listing is the common posture; flip for an allowlist
  status         = 403,
  log_only       = false,
  allow_countries = nil,   -- e.g. { "GB", "IE" }
  deny_countries  = nil,
  allow_asns      = nil,   -- e.g. { 15169 }
  deny_asns       = nil,   -- hosting providers, when you know what you are doing
  allow_cidrs     = nil,   -- always wins
  deny_cidrs      = nil,
}

-- --- IPv4 CIDR ---------------------------------------------------------------
--
-- IPv4 only, deliberately: an IPv6 prefix match wants a 128-bit compare, and
-- every use of the CIDR lists so far is "our office" or "our monitoring", which
-- are v4. An IPv6 address simply falls through to the country/ASN rules.
-- ponytail: v4-only CIDR match, add v6 when a v6 allowlist is actually needed.

function _M.ipv4_to_int(ip)
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
  return a * 16777216 + b * 65536 + c * 256 + d
end

function _M.in_cidr(ip, cidr)
  local network, bits = cidr:match("^([%d%.]+)/(%d+)$")
  if not network then
    network, bits = cidr, "32"
  end
  bits = tonumber(bits)
  local ip_int, net_int = _M.ipv4_to_int(ip), _M.ipv4_to_int(network)
  if not ip_int or not net_int or bits < 0 or bits > 32 then return false end
  if bits == 0 then return true end

  -- No bit library: LuaJIT has one, plain Lua 5.1 does not, and this is two
  -- divisions.
  local size = 2 ^ (32 - bits)
  return math.floor(ip_int / size) == math.floor(net_int / size)
end

local function any_cidr(ip, cidrs)
  for _, cidr in ipairs(cidrs or {}) do
    if _M.in_cidr(ip, cidr) then return cidr end
  end
  return nil
end

local function listed(value, list)
  if not list then return nil end
  for _, entry in ipairs(list) do
    if tostring(entry) == tostring(value) then return entry end
  end
  return nil
end

-- Pure decision. Returns allowed, reason.
function _M.decide(ip, country, asn, rules)
  local hit = any_cidr(ip, rules.allow_cidrs)
  if hit then return true, "allow cidr " .. hit end
  hit = any_cidr(ip, rules.deny_cidrs)
  if hit then return false, "deny cidr " .. hit end

  if rules.allow_countries then
    if listed(country, rules.allow_countries) then
      return true, "allow country " .. tostring(country)
    end
    -- An allowlist that cannot see the country would deny everything on a
    -- missing database, so say which it is.
    if not country or country == "" then
      return rules.default_allow, "country unknown (geoip2 variable unset)"
    end
    return false, "country " .. tostring(country) .. " not on the allowlist"
  end
  if listed(country, rules.deny_countries) then
    return false, "deny country " .. tostring(country)
  end

  if rules.allow_asns then
    if listed(asn, rules.allow_asns) then
      return true, "allow ASN " .. tostring(asn)
    end
    if not asn or asn == "" then
      return rules.default_allow, "ASN unknown (geoip2 variable unset)"
    end
    return false, "ASN " .. tostring(asn) .. " not on the allowlist"
  end
  if listed(asn, rules.deny_asns) then
    return false, "deny ASN " .. tostring(asn)
  end

  return rules.default_allow, "default"
end

local function merge(opts)
  local o = {}
  for k, v in pairs(DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  return o
end

-- access_by_lua entry point. `ip` defaults to the client address, and the
-- country/ASN come from the geoip2 module's variables.
function _M.check(ip, rules)
  local o = merge(rules)
  ip = ip or ngx.var.remote_addr

  local allowed, reason = _M.decide(
    ip,
    o.country or ngx.var.geoip2_country_code,
    o.asn or ngx.var.geoip2_asn,
    o
  )

  ngx.ctx.geo_reason = reason
  if allowed then return true, reason end

  ngx.log(ngx.WARN, "geo_asn: ", ip, " rejected: ", reason)
  if o.log_only then return true, reason end
  return ngx.exit(o.status)
end

_M.DEFAULTS = DEFAULTS

return _M
