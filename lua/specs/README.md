# Specifications of nginx-lua-waf-kit / lua

What this code does, one atomic Gherkin scenario per behaviour, read from the code by code-atlas.
Tags: `@verified` a test asserts it · `@inferred` read from the code only · `@gap` an entry point no test covers · `@human` written or amended by a person, never rewritten.

## Access policy

Allowing or denying traffic by where it comes from.

- **Country rules**: [Allowing and denying traffic by country and network](access-policy/country-rules/country-and-network-access-policy.feature) (2)

## Authentication

Verifying who is calling at the edge so upstreams only see authenticated traffic.

- **Signing keys**: [Verifying tokens against a published key set](authentication/signing-keys/published-signing-keys.feature) (1)
- **Token verification**: [Verifying bearer tokens at the edge](authentication/token-verification/edge-token-verification.feature) (2)

## Bot detection

Scoring how likely a request is to come from automation, with reasons, and acting on a chosen threshold.

- **Scoring and thresholds**: [Scoring requests for bot likelihood](bot-detection/bot-scoring/bot-scoring.feature) (7)

## Rate limiting

Capping how fast each client can send requests, consistently across worker processes.

- **Client keys**: [Counting a rate limit per client](rate-limiting/client-keys/ratelimit-client-keys.feature) (3)
- **Limit algorithms**: [Choosing a rate-limit algorithm](rate-limiting/limit-algorithms/ratelimit-algorithms.feature) (3)
- **Throttle responses**: [Throttling clients over their rate limit](rate-limiting/throttle-responses/ratelimit-throttling.feature) (3)

## Safe rollout

Introducing enforcement gradually and making every decision observable.

- **Log-only mode**: [Rolling out bot blocking](safe-rollout/log-only-mode/bot-blocking-rollout.feature) (3), [Rolling out a rate limit in log-only mode](safe-rollout/log-only-mode/ratelimit-log-only.feature) (3)

## Traffic mirroring

Safely copying live requests to a shadow environment for dark-canary testing.

- **Sensitive data scrubbing**: [Scrubbing sensitive data from mirrored captures](traffic-mirroring/data-scrubbing/mirror-data-scrubbing.feature) (1)
- **Kill switch**: [Stopping all mirroring with the kill switch](traffic-mirroring/kill-switch/mirror-kill-switch.feature) (2)
- **Request correlation**: [Pairing live and shadow requests for comparison](traffic-mirroring/request-correlation/mirror-request-correlation.feature) (2)
