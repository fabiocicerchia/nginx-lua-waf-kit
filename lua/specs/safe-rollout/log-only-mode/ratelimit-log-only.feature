@domain:safe-rollout @area:log-only-mode @from:lua/ratelimit
Feature: Rolling out a rate limit in log-only mode
  Lets an operator see who a new rate limit would throttle before it turns any traffic away, counted by the rollout analysis from the log line.

  Background:
    Given the operator has enabled the rate limiter with capacity 1

  @id:lua.safe-rollout.log-only-mode.004 @rule:ratelimit.rollout.log-only-admits-and-records @verified @source:lua/ratelimit.lua#_M.limit @test:test/run.lua#log_only rolls the limiter out without rejecting anyone @test:test/run.lua#every enforcing module logs the same shape under log_only
  Scenario: In log-only mode an over-limit request is admitted and logged as one that would be rejected
    Given the limiter runs in log-only mode
    And the client at 203.0.113.7 has already used its quota
    When the client sends another request
    Then the request reaches the upstream
    And the log reads "ratelimit: would reject 203.0.113.7: over limit (log_only)"
    And the request is recorded as one ratelimit would have rejected

  @id:lua.safe-rollout.log-only-mode.005 @rule:ratelimit.rollout.enforced-rejection-logged-as-rejected @verified @source:lua/ratelimit.lua#_M.limit @test:test/run.lua#every enforcing module logs the same shape under log_only
  Scenario: An enforced rejection is logged as rejected, never as log-only
    Given the limiter is enforcing
    And the client at 203.0.113.7 has already used its quota
    When the client sends another request
    Then the client is refused
    And the log reads "ratelimit: rejected 203.0.113.7: over limit" with no "(log_only)" tag
    And the request is recorded as rejected by ratelimit

  @id:lua.safe-rollout.log-only-mode.006 @rule:ratelimit.rollout.log-only-still-shows-exhausted-quota @inferred @source:lua/ratelimit.lua#_M.limit @questionable
  Scenario: In log-only mode a client over the limit still sees its quota as exhausted
    Given the limiter runs in log-only mode
    And the client at 203.0.113.7 has already used its quota
    When the client sends another request
    Then the request reaches the upstream
    And the response carries X-RateLimit-Remaining: 0
    And the response carries no Retry-After header
