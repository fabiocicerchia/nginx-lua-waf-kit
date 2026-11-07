@domain:rate-limiting @area:throttle-responses @from:lua/ratelimit
Feature: Throttling clients over their rate limit
  Lets an operator cap how fast each client may call a site, telling admitted clients their remaining quota and rejected ones when to come back.

  Background:
    Given the operator has enabled the rate limiter on a location

  @id:lua.rate-limiting.throttle-responses.001 @rule:ratelimit.throttle.admitted-request-reports-remaining-quota @verified @source:lua/ratelimit.lua#_M.limit @test:test/run.lua#limit() sets the rate-limit headers and rejects with the configured status
  Scenario Outline: A request within the limit is admitted and told how much quota is left
    Given the limit allows a burst of <capacity> requests
    And the client at 203.0.113.7 has made no requests yet
    When the client sends a request
    Then the request reaches the upstream
    And the response carries X-RateLimit-Remaining: <remaining>

    Examples:
      | capacity | remaining |
      | 20       | 19        |
      | 1        | 0         |

  @id:lua.rate-limiting.throttle-responses.002 @rule:ratelimit.throttle.over-limit-rejected-with-retry-after @verified @source:lua/ratelimit.lua#_M.limit @test:test/run.lua#limit() sets the rate-limit headers and rejects with the configured status
  Scenario Outline: A request over the limit is refused with a retry hint in whole seconds
    Given the limit allows 1 request and refills 1 per second
    And the rejection status is configured as <status>
    And the client at 203.0.113.7 has already used its quota
    When the client sends another request
    Then the client receives status <status>
    And the response carries Retry-After: 1
    And the response carries X-RateLimit-Remaining: 0

    Examples:
      | status        |
      | 429 (default) |
      | 503           |

  @id:lua.rate-limiting.throttle-responses.003 @rule:ratelimit.throttle.fails-open-without-shared-zone @verified @source:lua/ratelimit.lua#_M.check @test:test/run.lua#check() shares state across calls through the dict and fails open without one
  Scenario: A limiter whose shared memory zone is missing lets every request through and says so
    Given the configured shared memory zone "waf_ratelimit" is not declared in nginx
    When a client sends a request
    Then the request reaches the upstream
    And the response carries no X-RateLimit-Remaining header
    And the error log says the limiter is failing open for the missing zone
