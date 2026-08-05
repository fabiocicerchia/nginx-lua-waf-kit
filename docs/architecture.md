# Architecture

<!-- Diagram or bullet list of the main components and how they interact. -->

## Overview

## Components

## Data flow

## Decisions

Record significant choices here (or in a `docs/adr/` folder if they pile up).

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
