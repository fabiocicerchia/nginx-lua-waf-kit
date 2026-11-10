@domain:traffic-mirroring @area:kill-switch @from:lua/mirror
Feature: Stopping all mirroring with the kill switch
  Gives an operator a way to stop shadow traffic that works even when the control plane is down.

  Background:
    Given the edge node has request mirroring to a shadow deployment wired in

  @id:lua.traffic-mirroring.kill-switch.001 @rule:traffic-mirroring.kill-switch.stops-all-mirroring @verified @source:lua/mirror.lua#killed @test:test/run.lua#the kill switch beats every other rule @questionable
  Scenario Outline: An engaged kill switch stops every request from being mirrored
    Given mirroring is configured to mirror every request, including writes
    And the kill switch is engaged by <trigger>
    When a client sends a GET request
    Then the request is not mirrored to the shadow
    And the reason recorded for the decision is "kill switch engaged"

    Examples:
      | trigger                                                       |
      | a "kill" flag set in the configured shared flag store         |
      | the kill file /etc/dark-canary/kill existing on the edge node |

  @id:lua.traffic-mirroring.kill-switch.002 @rule:traffic-mirroring.kill-switch.takes-effect-within-ttl @verified @source:lua/mirror.lua#killed @test:test/run.lua#the kill switch is cached but not forever
  Scenario Outline: Engaging the kill switch takes effect within the refresh interval
    Given the kill switch refresh interval is 1 second
    And mirroring was running when the operator engaged the kill switch
    When a client sends a GET request <elapsed> after the edge node last checked the kill switch
    Then the request is <outcome> to the shadow

    Examples:
      | elapsed     | outcome                   |
      | 0.5 seconds | still mirrored if sampled |
      | 1.5 seconds | not mirrored              |
