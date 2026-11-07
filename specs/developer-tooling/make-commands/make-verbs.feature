@domain:developer-tooling @area:make-commands @from:nginx-lua-waf-kit/makefile
Feature: Discovering and running the standard make verbs
  Gives contributors the same predictable make verbs in every repository, each either doing its job or saying plainly why it does nothing here.

  Background:
    Given a contributor has a checkout of nginx-lua-waf-kit

  @id:developer-tooling.make-commands.001 @rule:tooling.make.bare-make-lists-verbs @inferred @source:Makefile#help
  Scenario: Running make with no verb lists every verb with its purpose
    When the contributor runs make with no verb
    Then one line is printed per verb, in the order help, setup, lint, test, analyze, build, install, run, format, clean
    And each line shows the verb name padded to ten characters followed by its one-line description
    And nothing is built, tested or changed

  @id:developer-tooling.make-commands.002 @rule:tooling.make.not-applicable-verbs-explain-themselves @inferred @source:Makefile#build
  Scenario Outline: A verb that does not apply succeeds and says why it does nothing
    When the contributor runs make <verb>
    Then the command exits with status 0
    And it prints "<message>"
    And no file in the checkout is created or changed

    Examples:
      | verb    | message                                                                |
      | build   | Nothing to build: pure Lua modules, loaded from nginx at request time. |
      | install | Nothing to install: point lua_package_path at this checkout, or copy   |
      | run     | Nothing to run: these modules are called by nginx per request.         |
      | clean   | nothing to clean                                                       |

  @id:developer-tooling.make-commands.003 @rule:tooling.make.analyze-refuses-without-luacheck @inferred @source:Makefile#analyze
  Scenario: Static analysis refuses to run when luacheck is missing and says how to install it
    Given luacheck is not installed
    When the contributor runs make analyze
    Then it prints "analyze needs luacheck: luarocks install luacheck" on standard error
    And make reports the analyze recipe failed with Error 69 and exits with status 2
    And no analysis is reported as passing

  @id:developer-tooling.make-commands.004 @rule:tooling.make.format-succeeds-after-rewriting @inferred @source:Makefile#format @questionable
  Scenario: Formatting reports success even when it had to rewrite files
    Given a file has trailing whitespace and no final newline
    When the contributor runs make format
    Then the trailing whitespace is removed and the final newline added in place
    And each fixer's own output is printed, with make noting the fixer's failure as ignored
    And the command exits with status 0
