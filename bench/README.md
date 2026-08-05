# Benchmarks

This directory must carry real latency numbers before the kit is released — the
target audience will not enable Lua in the request path without them.

## Status: harness built, numbers NOT measured

`results.md` does not exist yet. Nobody has run this on hardware worth quoting,
and inventing numbers would be worse than having none. **This is still the
release blocker** — it is now one command away from being answered.

## Running it

```
./run.sh                                   # openresty/openresty:alpine, 30s per scenario
IMAGE=your/nginx-lua:tag DURATION=60s ./run.sh
```

Needs docker. Writes `results.md` with the image tag, host and load-generator
settings baked in, so a number is never quotable without the conditions it was
measured under.

## Method

`nginx.conf` serves every scenario from **one nginx process**: same build, same
hardware, same upstream (a static 200), with the Lua in the request path as the
only variable. `run.sh` drives each location with `wrk` and records req/s and
p50/p90/p99 latency.

| Scenario | What it isolates |
| --- | --- |
| `baseline` | no Lua at all — every other row is read as a delta from this |
| `ratelimit` | token bucket, limit set high enough that nothing is rejected |
| `ratelimit-log` | sliding log, the expensive algorithm, for the worst case |
| `bots` | header scoring, including the raw-header order parse |
| `geo` | country/ASN policy over the geoip2 variables |
| `mirror` | the decision, sampling and correlation id — not the mirrored request |
| `all` | everything on, which is what an adopter actually runs |

The rate limiter is deliberately configured **not to reject** during the
benchmark: the cost being measured is the cost of deciding, not the cost of
returning a 429.

## Also required before release

- Memory: `lua_shared_dict` sizing guidance for the rate limiter. Roughly one
  key per client per algorithm; the sliding log stores one timestamp per admitted
  request within the window, so size it from `capacity × clients`.
- The mirrored subrequest's own cost, measured separately — the `mirror` row
  above measures the decision, not the shadow traffic it generates.
