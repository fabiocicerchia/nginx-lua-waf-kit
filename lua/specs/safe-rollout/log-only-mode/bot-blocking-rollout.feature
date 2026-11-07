@domain:safe-rollout @area:log-only-mode @from:lua/bot-heuristics
Feature: Rolling out bot blocking
  Lets operators watch what bot scoring would block before it blocks anyone, then enforce with a status code of their choice, so a heuristic tuned on someone else's traffic does not turn away real customers.

  Background:
    Given a client at 203.0.113.7 sends the user agent "curl/8.4.0" and an accept header only, which scores 0.8

  @id:lua.safe-rollout.log-only-mode.001 @rule:bots.rollout.log-only-by-default @verified @source:lua/bot_heuristics.lua#_M.score @test:test/run.lua#every enforcing module logs the same shape under log_only
  Scenario: By default a request scored as a bot is let through and logged as would-reject
    Given the operator has enabled bot scoring without choosing log-only or enforcing
    When the edge node scores the request
    Then the request reaches the upstream
    And the error log has the warning "bot_heuristics: would reject 203.0.113.7: score 0.8 (self-identifying client: curl/; missing accept-language, accept-encoding) (log_only)"
    And the error log has no line containing "bot_heuristics: rejected"

  @id:lua.safe-rollout.log-only-mode.002 @rule:bots.rollout.enforced-rejection @verified @source:lua/bot_heuristics.lua#_M.score @test:test/run.lua#every enforcing module logs the same shape under log_only
  Scenario Outline: With log-only turned off, a request scored as a bot is refused with the configured status
    Given the operator has turned log-only off for bot scoring
    And the operator has set the rejection status to <status>
    When the edge node scores the request
    Then the client receives status <status>
    And the error log has the warning "bot_heuristics: rejected 203.0.113.7: score 0.8 (self-identifying client: curl/; missing accept-language, accept-encoding)"
    And that line does not end with "(log_only)"

    Examples:
      | status            |
      | 403 (the default) |
      | 429               |

  @id:lua.safe-rollout.log-only-mode.003 @rule:bots.rollout.threshold-inclusive @inferred @source:lua/bot_heuristics.lua#_M.score
  Scenario Outline: A score exactly at the threshold counts as a bot, and one below it is left alone
    Given the operator has turned log-only off for bot scoring with a threshold of <threshold>
    And a client at 203.0.113.7 sends the user agent "curl/8.4.0" with every browser header in browser order, which scores 0.5
    When the edge node scores the request
    Then <outcome>

    Examples:
      | threshold | outcome                                                                             |
      | 0.5       | the client receives status 403 and "bot_heuristics: rejected 203.0.113.7" is logged |
      | 0.6       | the request reaches the upstream and no bot_heuristics line is logged               |
