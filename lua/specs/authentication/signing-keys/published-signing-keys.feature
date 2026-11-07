@domain:authentication @area:signing-keys @from:lua/jwt
Feature: Verifying tokens against a published key set
  Lets operators verify public-key-signed tokens against their identity provider's published keys without trusting the token to choose its own key.

  Background:
    Given the deployment accepts RS256 tokens
    And its key set is published at "https://issuer.example.com/jwks" with keys "k1" and "k2"

  @id:lua.authentication.signing-keys.001 @rule:auth.keys.shared-secret-only-for-hs256 @inferred @source:lua/jwt.lua#verify_hs256
  Scenario: A shared-secret token is never checked against the published keys
    Given the deployment also accepts HS256 tokens signed with its own shared secret
    And an attacker signs an HS256 token using the text of published key "k1" as the secret
    When the attacker presents the token
    Then the response status is 401
    And the logged reason is "signature mismatch"
