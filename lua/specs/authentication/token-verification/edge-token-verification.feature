@domain:authentication @area:token-verification @from:lua/jwt
Feature: Verifying bearer tokens at the edge
  Lets operators guarantee upstream services only ever receive requests carrying a token whose signature the edge has verified.

  Background:
    Given Given the edge requires a bearer token in the Authorization header
    And And the edge accepts HS256 tokens signed with the shared secret "example-secret"

  @id:lua.authentication.token-verification.001 @rule:auth.tokens.fail-closed-without-verifier @verified @source:lua/jwt.lua#verify_asymmetric @test:test/run.lua#an asymmetric token fails closed when the verifier is unavailable @test:test/run.lua#a correctly signed HS256 token validates end to end
  Scenario Outline: A token the edge has no means to verify is refused, never passed through
    Given Given <misconfiguration>
    When When a client presents a <alg> token
    Then Then the response status is 401
    And And the logged reason is "<reason>"

    Examples:
      | misconfiguration                                                      | alg   | reason                                                |
      | the deployment accepts HS256 but no shared secret is configured       | HS256 | HS256 configured without a secret                     |
      | the deployment accepts RS256 but the OpenSSL library is not installed | RS256 | RS256 needs lua-resty-openssl, which is not installed |

  @id:lua.authentication.token-verification.002 @rule:auth.tokens.es256-signature-format @inferred @source:lua/jwt.lua#verify_asymmetric @questionable
  Scenario: An ES256 token signed by the published key is refused
    Given Given the deployment accepts ES256 tokens verified against its published key set
    And And a client holds an ES256 token correctly signed by a key in that set
    When When the client sends a request with that token
    Then Then the response status is 401
    And And the logged reason is "signature mismatch"
