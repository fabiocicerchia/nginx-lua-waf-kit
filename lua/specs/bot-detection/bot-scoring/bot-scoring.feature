@domain:bot-detection @area:bot-scoring @from:lua/bot-heuristics
Feature: Scoring requests for bot likelihood
  Gives operators a 0-to-1 bot score with plain-language reasons for every request, so they can tell automation from real browsers before deciding to block.

  Background:
    Given the operator has enabled bot scoring at the edge with the default threshold of 0.6

  @id:lua.bot-detection.bot-scoring.001 @rule:bots.scoring.plausible-browser-not-flagged @verified @source:lua/bot_heuristics.lua#_M.score_request @test:test/run.lua#a plausible browser scores low
  Scenario: A request that looks like a real browser scores zero and is let through
    Given a client claims to be Chrome in its user agent
    And the client sends accept, accept-language, accept-encoding and user-agent headers
    And the client sends its headers in the order host, user-agent, accept, accept-language, accept-encoding
    When the edge node scores the request
    Then the bot score is 0
    And no reasons are given
    And the request reaches the upstream

  @id:lua.bot-detection.bot-scoring.002 @rule:bots.scoring.self-identifying-client @inferred @source:lua/bot_heuristics.lua#user_agent_signal
  Scenario Outline: A client that names itself as an automation tool earns half a point
    Given a client sends the user agent "<user_agent>"
    And the client sends every header a browser sends, in browser order
    When the edge node scores the request
    Then the bot score is 0.5
    And the reasons include "self-identifying client: <matched>"
    And the score alone is below the default threshold, so the request reaches the upstream

    Examples:
      | user_agent                                                               | matched         |
      | curl/8.4.0                                                               | curl/           |
      | python-requests/2.31.0                                                   | python-requests |
      | Mozilla/5.0 HeadlessChrome/124.0                                         | headlesschrome  |
      | Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html) | bot             |

  @id:lua.bot-detection.bot-scoring.003 @rule:bots.scoring.missing-browser-headers @verified @source:lua/bot_heuristics.lua#missing_header_signal @test:test/run.lua#missing headers and no user agent add up @questionable
  Scenario Outline: Each browser header that is missing adds to the score, and a missing user agent adds more
    Given a client sends only the headers <sent>
    When the edge node scores the request
    Then the bot score is <score>
    And the reasons are <reasons>

    Examples:
      | sent                                            | score | reasons                                                                         |
      | none at all                                     | 0.95  | "no user agent"; "missing accept, accept-language, accept-encoding, user-agent" |
      | a Chrome user-agent and accept                  | 0.3   | "missing accept-language, accept-encoding"                                      |
      | a Chrome user-agent, accept and accept-language | 0.15  | "missing accept-encoding"                                                       |

  @id:lua.bot-detection.bot-scoring.004 @rule:bots.scoring.unusual-header-order @verified @source:lua/bot_heuristics.lua#header_order_signal @test:test/run.lua#header order is scored by inversions against the browser order
  Scenario Outline: Headers sent in an order no browser uses raise the score in proportion to how scrambled they are
    Given a client claims to be Chrome and sends every header a browser sends
    And the client sends its headers in the order <order>
    When the edge node scores the request
    Then the bot score is <score>
    And the reasons are <reasons>

    Examples:
      | order                                                      | score | reasons                |
      | accept-encoding, accept-language, accept, user-agent, host | 0.3   | "unusual header order" |
      | host, accept, user-agent, accept-language, accept-encoding | 0.03  | "unusual header order" |
      | host, user-agent, accept, accept-language, accept-encoding | 0     | none                   |

  @id:lua.bot-detection.bot-scoring.005 @rule:bots.scoring.tls-fingerprint-contradicts-user-agent @verified @source:lua/bot_heuristics.lua#tls_fingerprint_signal @test:test/run.lua#a TLS fingerprint that contradicts the user agent is the strongest signal @questionable
  Scenario Outline: A TLS fingerprint that contradicts the browser the user agent claims adds half a point
    Given a client claims to be Chrome and sends every header a browser sends, in browser order
    And the client's TLS fingerprint is identified as family "<family>"
    When the edge node scores the request
    Then the bot score is <score>
    And the reasons are <reasons>

    Examples:
      | family    | score | reasons                                                  |
      | go-stdlib | 0.5   | "TLS fingerprint (go-stdlib) contradicts the user agent" |
      | browser   | 0     | none                                                     |

  @id:lua.bot-detection.bot-scoring.006 @rule:bots.scoring.allowlisted-user-agent-exempt @verified @source:lua/bot_heuristics.lua#_M.score_request @test:test/run.lua#the allowlist skips scoring entirely @questionable
  Scenario Outline: A user agent on the operator's allowlist is not scored at all
    Given the operator allowlists user agents containing "<entry>"
    And a client sends the user agent "curl/8.4.0 statuscake" and no other headers
    When the edge node scores the request
    Then the bot score is <score>
    And the reasons are <reasons>

    Examples:
      | entry      | score | reasons                                                                              |
      | statuscake | 0     | "allowlisted user agent"                                                             |
      | StatusCake | 0.95  | "self-identifying client: curl/"; "missing accept, accept-language, accept-encoding" |

  @id:lua.bot-detection.bot-scoring.007 @rule:bots.scoring.http2-scored-without-order @verified @source:lua/bot_heuristics.lua#_M.score @test:test/run.lua#an HTTP/2 request is scored without its header order, not aborted
  Scenario: A request whose header order cannot be read is scored on its other signals instead of failing
    Given a client connects over HTTP/2, so its header order is not available
    And the client sends the user agent "curl/8.4.0" and an accept header only
    When the edge node scores the request
    Then the request is not failed with an error
    And the bot score is 0.8
    And the reasons do not include "unusual header order"
