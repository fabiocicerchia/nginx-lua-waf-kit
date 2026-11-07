@domain:access-policy @area:country-rules @from:lua/geo-asn
Feature: Allowing and denying traffic by country and network
  Lets an operator restrict who reaches a site by the client's country and network operator, try the policy without blocking, and choose what unmatched traffic gets.

  Background:
    Given nginx resolves each client's country code and network number before the policy runs

  @id:lua.access-policy.country-rules.001 @rule:access-policy.geo.country-allowlist-overrides-network-rules @inferred @source:lua/geo_asn.lua#list_decision @questionable
  Scenario Outline: When a country allowlist is set, network rules are never consulted
    Given the operator allows only country GB
    And the operator denies network 64501
    When a client from country <country> on network 64501 requests a page
    Then the request is <outcome>
    And the recorded reason is "<reason>"

    Examples:
      | country | outcome                 | reason                          |
      | GB      | admitted                | allow country GB                |
      | US      | refused with status 403 | country US not on the allowlist |

  @id:lua.access-policy.country-rules.002 @rule:access-policy.geo.unknown-country-follows-default @inferred @source:lua/geo_asn.lua#list_decision
  Scenario Outline: A client whose country cannot be resolved follows the default posture instead of the allowlist
    Given the operator allows only country GB
    And unmatched traffic is <posture>
    When a client whose country nginx could not resolve requests a page
    Then the request is <outcome>
    And the recorded reason is "country unknown (geoip2 variable unset)"

    Examples:
      | posture | outcome                 |
      | allowed | admitted                |
      | denied  | refused with status 403 |
