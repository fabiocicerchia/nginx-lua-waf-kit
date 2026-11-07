@domain:traffic-mirroring @area:request-correlation @from:lua/mirror
Feature: Pairing live and shadow requests for comparison
  Lets the comparison collector match each live request with its shadow copy and compare their outcomes, without slowing the live response.

  Background:
    Given the edge node has request mirroring to a shadow deployment wired in

  @id:lua.traffic-mirroring.request-correlation.001 @rule:traffic-mirroring.correlation.shared-id-on-both-paths @verified @source:lua/mirror.lua#decide @test:test/run.lua#decide() sets the gate variable and the correlation id on both paths @test:test/run.lua#capture() scrubs headers, query and body together
  Scenario: Live and shadow requests carry the same correlation id
    Given nginx assigned the request id "abc123"
    When a client sends a GET request that is selected for mirroring
    Then the live request reaches the upstream with header "X-Dark-Canary-Id: abc123"
    And the shadow copy carries the same "X-Dark-Canary-Id: abc123"
    And the capture sent to the collector has correlation id "abc123"

  @id:lua.traffic-mirroring.request-correlation.002 @rule:traffic-mirroring.correlation.shipping-never-blocks-response @verified @source:lua/mirror.lua#ship @test:test/run.lua#ship() hands off to a timer instead of blocking the response
  Scenario: Sending captures to the collector never delays or fails the live response
    Given the collector at 127.0.0.1:8099 is unreachable
    When a mirrored request completes at the edge node
    Then the client receives its response unaffected
    And the attempt to post the capture to the collector happens after the response is on its way
    And the edge node logs "dark-canary: collector unreachable" as a warning and drops the capture
