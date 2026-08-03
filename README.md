# nginx-lua-waf-kit

[![CI](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/code-quality.yml/badge.svg)](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/code-quality.yml)
[![Security](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/security.yml/badge.svg)](https://github.com/fabiocicerchia/nginx-lua-waf-kit/actions/workflows/security.yml)
[![License](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/fabiocicerchia/nginx-lua-waf-kit/badge)](https://securityscorecards.dev/viewer/?uri=github.com/fabiocicerchia/nginx-lua-waf-kit)


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

## Design rules the modules follow

**Every module is pure logic plus a thin nginx entry point.** The decisions —
`ratelimit.step`, `bots.score_request`, `geo.decide`, `jwt.check_claims`,
`mirror.should_mirror` — are functions of their arguments, which is why they can
be tested outside nginx and why the rate limiter cannot drift from the
visualiser that explains it.

**Score before you block.** `bot_heuristics` defaults to `log_only`, and every
rejection carries the reasons that produced it. A heuristic that blocks silently
eventually blocks a customer.

**Fail in the safe direction, per module.** A missing `lua_shared_dict` fails the
rate limiter *open* and logs loudly — 503-ing every request over a config typo is
worse than not limiting. A JWT that cannot be verified fails *closed*: the `alg`
header only ever selects from a fixed table, so `alg: none` is refused before any
verification is attempted. A missing geoip database falls back to the configured
default instead of black-holing the site.

**Do not reimplement what the platform already does.** `geo_asn` reads the
variables `ngx_http_geoip2_module` already sets rather than parsing an `.mmdb`
per request; `jwt` builds HMAC-SHA256 from OpenResty's bundled `resty.sha256`
rather than adding `lua-resty-hmac`; `mirror` leaves the subrequest to nginx's
own `mirror` directive and supplies only the parts nginx has no opinion about —
whether to mirror, correlation, and safety.

## Why the mirror hook comes first

It is useful on its own, and it is dark-canary's capture layer — building it here
made dark-canary meaningfully cheaper. It adds the four things the `mirror`
directive has no answer for: a correlation id on both paths, a kill switch read
from local state (so it works when the control plane is down), reads-only
enforcement, and sampling before mirroring. PII is scrubbed at the edge, before
a capture is buffered or shipped.

## Tests

```
lua test/run.lua        # any Lua 5.1+, no framework, no dependencies
resty test/run.lua      # inside the nginx-lua image itself
```

35 assertions over the pure logic: every rate-limiting algorithm including the
fixed window's boundary burst and the sliding counter that smooths it, the mirror
safety rules, bot scoring and header-order inversions, CIDR/country/ASN
precedence, and JWT parsing, claim checks, HMAC construction and `alg: none`.
`test/mock_ngx.lua` is a small stand-in for the `ngx` API the modules touch.

## Ships dead without benchmarks

`bench/` now carries a harness — one nginx process serving baseline and
module-enabled locations, driven by `wrk` — but **no numbers yet**. That is still
the release blocker: this audience will not put Lua in the request path on faith.
Run `bench/run.sh` on hardware worth quoting and commit `bench/results.md`.

## Status

Modules implemented and unit-tested; not yet exercised under a live OpenResty
(there is no Lua runtime on the machine they were written on beyond the test
interpreter). The first deployment should be `log_only` everywhere. Remaining:
the benchmark run, and one example config tag per nginx-lua release. Gate: any
adoption signal from existing nginx-lua users — if none, dark-canary is built on
sand. See `../ROADMAP.md`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues go through
[GitHub Security Advisories](https://github.com/fabiocicerchia/nginx-lua-waf-kit/security/advisories/new),
never a public issue — see [SECURITY.md](SECURITY.md).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
