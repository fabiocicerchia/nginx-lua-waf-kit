# The first deployment: everything on, nothing enforcing

`mirror`, `ratelimit`, `jwt`, `geo_asn` and `bot_heuristics` have never run
against real traffic. Until they have, the thresholds shipped in the examples
are somebody's judgement, not a measurement — and a bot heuristic tuned on
somebody else's traffic will reject your customers.

So the first deployment enforces nothing. Every module scores, decides, writes
down what it **would** have done, and lets the request through.

```sh
cd examples/log-only
docker compose up -d
# point real traffic at :8080 and leave it for a week
./analyse.sh
```

> **Nothing here has been run.** The config and the analyser are written and
> shell-checked; no OpenResty has loaded them and no traffic has reached them.
> That is the half of this that needs a host — and it is the half the issue is
> actually about.

## What comes out

```
log_only rollout — 184203 request(s) in the window

module           would-reject      rate  verdict
------------------------------------------------------------
ratelimit                 412     0.22%  —
bot_heuristics           2911     1.58%  TOO HIGH to enforce — these are your
                                          users until proven otherwise
jwt                         0     0.00%  nothing scored — either clean traffic
                                          or the module is not wired in
geo_asn                    17     0.01%  —
```

(Shape, not a measurement — the numbers above are illustrative.)

**The rate is the point, not the count.** Counting "would reject" lines tells
you how many requests a module scored badly; it does not tell you what fraction
of your traffic that is, and the fraction is the whole decision. The denominator
comes from the access log, which is why `nginx.conf` writes both.

The bands differ per module, deliberately: a rate limiter that would reject 2%
of requests is doing its job, and a bot heuristic that would reject 2% is about
to remove one customer in fifty.

## The log line is an interface

Every enforcing module writes the same shape, which is what makes the analyser
one loop instead of four parsers:

```
<module>: would reject <subject>: <why> (log_only)
<module>: rejected     <subject>: <why>
```

`geo_asn` used to log `rejected` for a request it had let through. Anybody
counting rejections during a rollout would have read a module that blocked
nothing as having blocked everything it scored — wrong in the direction
that gets a rollout cancelled. There is a test for it now.

`jwt` had no `log_only` at all, which meant "all five in log_only" was not
a configuration that existed. It has one now: it validates, logs the
verdict, and returns the error to the caller without rejecting.

If the analyser reports a module `rejected` anything, it says so loudly — a
log_only rollout that turns traffic away is not measuring what it thinks it is.

## What to do with the answer

1. **Read some lines by hand.** A would-reject rate is a false-positive rate
   only if none of that traffic was hostile. On an internet-facing host some of
   it was; on an internal one, almost none. The reason field is what tells the
   two apart.
2. **Enforce one module at a time**, starting with the lowest rate, and leave a
   week between each. `log_only = false` on that module only.
3. **Feed the thresholds back.** The defaults in `examples/waf.conf.example` are
   what this exercise exists to correct — a rate measured on real traffic beats
   a number chosen in advance, every time.

## Privacy

`analyse.sh` prints counts and percentages. No IPs, no tokens, no user-agents,
no paths — the guarantee is that the script never reads a field that could carry
one, rather than that it strips them afterwards. Its output is safe to post.

The **logs themselves are not**: they carry client addresses and, for the JWT
module, the reason a token failed. They stay on the host.
