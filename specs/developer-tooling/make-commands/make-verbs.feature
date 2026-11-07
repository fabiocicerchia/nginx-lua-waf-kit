@domain:developer-tooling @area:make-commands @from:nginx-lua-waf-kit/makefile
Feature: Discovering and running the standard make verbs
  Gives contributors the same predictable make verbs in every repository, each either doing its job or saying plainly why it does nothing here.

  Background:
    Given Given a contributor has a checkout of nginx-lua-waf-kit

  @id:developer-tooling.make-commands.001 @rule:tooling.make.bare-make-lists-verbs @inferred @source:Makefile#help
  Scenario: Running make with no verb lists every verb with its purpose
    When When the contributor runs make with no verb
    Then Then one line is printed per verb, in the order help, setup, lint, test, analyze, build, install, run, format, clean
    And And each line shows the verb name padded to ten characters followed by its one-line description
    And And nothing is built, tested or changed

  @id:developer-tooling.make-commands.002 @rule:tooling.make.not-applicable-verbs-explain-themselves @inferred @source:Makefile#build
  Scenario Outline: A verb that does not apply succeeds and says why it does nothing
    When When the contributor runs make <verb>
    Then Then the command exits with status 0
    And And it prints "<message>"
    And And no file in the checkout is created or changed

    Examples:
      | verb    | message                                                                |
      | build   | Nothing to build: pure Lua modules, loaded from nginx at request time. |
      | install | Nothing to install: point lua_package_path at this checkout, or copy   |
      | run     | Nothing to run: these modules are called by nginx per request.         |
      | clean   | nothing to clean                                                       |

  @id:developer-tooling.make-commands.003 @rule:tooling.make.analyze-refuses-without-luacheck @inferred @source:Makefile#analyze
  Scenario: Static analysis refuses to run when luacheck is missing and says how to install it
    Given And luacheck is not installed
    When When the contributor runs make analyze
    Then Then it prints "analyze needs luacheck: luarocks install luacheck" on standard error
    And And the command exits with status 69
    And And no analysis is reported as passing

  @id:developer-tooling.make-commands.004 @rule:tooling.make.format-succeeds-after-rewriting @inferred @source:Makefile#format @questionable
  Scenario: Formatting reports success even when it had to rewrite files
    Given And a file has trailing whitespace and no final newline
    When When the contributor runs make format
    Then Then the trailing whitespace, final newline and mixed line endings are fixed in place
    And And each fixer's own output is printed
    And And the command exits with status 0
