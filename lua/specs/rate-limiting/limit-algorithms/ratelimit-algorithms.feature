@domain:rate-limiting @area:limit-algorithms @from:lua/ratelimit
Feature: Choosing a rate-limit algorithm
  Lets an operator pick one of the five algorithms shown in the /ratelimit visualiser and get the same admit/refuse behaviour at the edge.

  Background:
    Given the operator has enabled the rate limiter on a location

  @id:lua.rate-limiting.limit-algorithms.001 @rule:ratelimit.algorithms.capacity-caps-a-burst @verified @source:lua/ratelimit.lua#_M.step @test:test/run.lua#token bucket starts full and refills at the configured rate @test:test/run.lua#leaky bucket admits at the drain rate, not in bursts @test:test/run.lua#fixed window resets on the boundary, which is its known flaw @test:test/run.lua#sliding log is exact and expires entries by time @test:test/run.lua#sliding counter smooths the boundary the fixed window jumps @test:test/run.lua#long algorithm spellings alias to the visualiser's names
  Scenario Outline: Every algorithm admits up to its capacity in a burst and refuses the next request
    Given the operator chose the "<algorithm>" algorithm with capacity 2 and a 10 second window
    And the client at 203.0.113.7 has made no requests yet
    When the client sends 3 requests at the same instant
    Then the first 2 requests are admitted
    And the 3rd request is refused

    Examples:
      | algorithm              |
      | token-bucket           |
      | leaky-bucket           |
      | fixed-window           |
      | sliding-log            |
      | sliding-window-log     |
      | sliding-counter        |
      | sliding-window-counter |

  @id:lua.rate-limiting.limit-algorithms.002 @rule:ratelimit.algorithms.window-boundary-burst @verified @source:lua/ratelimit.lua#_M.step @test:test/run.lua#sliding counter smooths the boundary the fixed window jumps @test:test/run.lua#fixed window resets on the boundary, which is its known flaw
  Scenario Outline: A fixed window lets a fresh burst through at its boundary while a sliding counter does not
    Given the operator chose the "<algorithm>" algorithm with capacity 2 and a 10 second window
    And the client used its 2 requests at 9.0s and 9.5s and was refused at 9.9s
    When the client sends requests at 10.1s and 10.2s
    Then the request at 10.1s is admitted
    And the request at 10.2s is <outcome>

    Examples:
      | algorithm       | outcome  |
      | fixed-window    | admitted |
      | sliding-counter | refused  |

  @id:lua.rate-limiting.limit-algorithms.003 @rule:ratelimit.algorithms.unknown-algorithm-refuses-to-run @verified @source:lua/ratelimit.lua#_M.step @test:test/run.lua#an unknown algorithm fails loudly rather than admitting everything @questionable
  Scenario: A misspelled algorithm name stops the limiter instead of admitting everything
    Given the operator configured the algorithm as "nonsense"
    When a client sends a request
    Then the request fails with an error naming the unknown algorithm "nonsense"
    And the request is not silently admitted unlimited
