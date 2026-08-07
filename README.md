# nginx-lua-waf-kit

[![CI](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/code-quality.yml/badge.svg)](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/code-quality.yml)
[![Security](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/security.yml/badge.svg)](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/security.yml)
[![License](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/fabiocicerchia/nginx-lua-waf-kit/badge)](https://securityscorecards.dev/viewer/?uri=github.com/fabiocicerchia/nginx-lua-waf-kit)
[![CI carbon](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/fabiocicerchia/nginx-lua-waf-kit/gh-pages/badge.json)](.github/workflows/carbon-badge.yml)

An opt-in Lua module set for the existing nginx-lua image — **a kit, not a WAF
product**. Versioned tag-for-tag against nginx-lua releases so existing users
adopt it incrementally.

## Modules

| Module | Purpose |
| --- | --- |
| `lua/ratelimit.lua` | Shared-dict rate limiting; the five algorithms of the `/ratelimit` visualiser, under the same names. |
| `lua/bot_heuristics.lua` | Bot *scoring* on headers, header order and TLS fingerprint. |
| `lua/jwt.lua` | Edge JWT validation: signature, `exp`/`nbf`/`iss`/`aud`, JWKS cache. |
| `lua/geo_asn.lua` | Geo / ASN allow-deny policy over the geoip2 module's variables. |
| `lua/mirror.lua` | Request-mirroring hook — **also dark-canary's capture layer**. |

`examples/waf.conf.example` shows the whole wiring.

## Install

```sh
git clone https://github.com/fabiocicerchia/nginx-lua-waf-kit.git \
  /opt/nginx-lua-waf-kit
```

Then point nginx at the modules:

```nginx
lua_package_path "/opt/nginx-lua-waf-kit/lua/?.lua;;";
```

## Usage

```nginx
lua_shared_dict waf_ratelimit 10m;

init_by_lua_block {
  waf = { ratelimit = require "ratelimit" }
}
```

`examples/waf.conf.example` shows the whole wiring; every module is opt-in.

## Documentation

Full docs live in [`docs/`](docs/). Runnable examples live in [`examples/`](examples/).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues go through
[GitHub Security Advisories](https://github.com/fabiocicerchia/nginx-lua-waf-kit/security/advisories/new),
never a public issue — see [SECURITY.md](SECURITY.md).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
