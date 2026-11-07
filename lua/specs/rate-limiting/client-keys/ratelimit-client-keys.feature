@domain:rate-limiting @area:client-keys @from:lua/ratelimit
Feature: Counting a rate limit per client
  Lets an operator decide whom a limit is counted against so one noisy client cannot use up another's quota, across every nginx worker.

  Background:
    Given the operator has enabled the rate limiter with capacity 2 using the token-bucket algorithm

  @id:lua.rate-limiting.client-keys.001 @rule:ratelimit.keys.counted-per-client-address-across-workers @inferred @source:lua/ratelimit.lua#_M.check
  Scenario Outline: Each client address has its own quota, shared by every worker
    Given no limit key is configured
    And the client at 203.0.113.7 has used its 2 requests, served by different workers
    When <client> sends a request
    Then the request is <outcome>

    Examples:
      | client                     | outcome  |
      | the client at 203.0.113.7  | refused  |
      | the client at 198.51.100.4 | admitted |

  @id:lua.rate-limiting.client-keys.002 @rule:ratelimit.keys.custom-key-groups-requests @verified @source:lua/ratelimit.lua#_M.check @test:test/run.lua#check() shares state across calls through the dict and fails open without one
  Scenario: An operator-chosen key counts all requests carrying it against one quota
    Given the operator set the limit key to the API key "key_acme"
    And requests with "key_acme" have used both requests of the quota
    When a different client address sends a request with "key_acme"
    Then the request is refused

  @id:lua.rate-limiting.client-keys.003 @rule:ratelimit.keys.limits-with-same-algorithm-share-a-quota @inferred @source:lua/ratelimit.lua#_M.check @questionable
  Scenario: Two limits using the same algorithm and key draw on one shared quota
    Given the operator limits /api with capacity 2 and /login with capacity 20, both token-bucket on the client address
    And the client at 203.0.113.7 has used 2 requests on /api
    When the client sends a request to /login at the same instant
    Then the request is refused, because /login starts from the tokens /api left rather than its own 20
    And the response carries X-RateLimit-Remaining: 0
