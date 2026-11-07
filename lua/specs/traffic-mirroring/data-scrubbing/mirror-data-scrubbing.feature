@domain:traffic-mirroring @area:data-scrubbing @from:lua/mirror
Feature: Scrubbing sensitive data from mirrored captures
  Keeps credentials and personal data out of the captures that the edge node ships to the comparison collector.

  Background:
    Given the edge node has request mirroring wired in with a capture collector configured

  @id:lua.traffic-mirroring.data-scrubbing.001 @rule:traffic-mirroring.scrubbing.unmirrored-requests-not-captured @verified @source:lua/mirror.lua#capture @test:test/run.lua#capture() produces nothing for a request that was never mirrored
  Scenario: Requests that were not mirrored produce no capture
    Given a request was not selected for mirroring
    When the request completes at the edge node
    Then no capture is produced
    And nothing is sent to the collector for that request
