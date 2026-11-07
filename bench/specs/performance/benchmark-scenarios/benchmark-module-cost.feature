@domain:performance @area:benchmark-scenarios @from:bench/run
Feature: Benchmarking each module against a baseline
  Lets an operator weighing adoption measure what each module adds to the request path, by loading a baseline and every module configuration served by one nginx process.

  Background:
    Given Docker is available on the operator's machine

  @id:bench.performance.benchmark-scenarios.001 @rule:performance.benchmark.every-scenario-measured-against-baseline @inferred @source:bench/run.sh#SCENARIOS
  Scenario Outline: Every module configuration is loaded in turn alongside the baseline
    Given the benchmark server is up and answering on its port
    When the operator runs the benchmark
    Then the load generator drives /<scenario> for the configured duration
    And the results table gets one row for `<scenario>`
    And the rows appear in the order baseline, ratelimit, ratelimit-log, bots, geo, mirror, all

    Examples:
      | scenario      |
      | baseline      |
      | ratelimit     |
      | ratelimit-log |
      | bots          |
      | geo           |
      | mirror        |
      | all           |

  @id:bench.performance.benchmark-scenarios.002 @rule:performance.benchmark.load-settings-overridable @inferred @source:bench/run.sh#IMAGE
  Scenario Outline: Load settings use documented defaults unless the operator overrides them
    Given the operator sets <variable> to <override> (or leaves it unset)
    When the operator runs the benchmark
    Then the run uses <default> when <variable> is unset and <override> when it is set
    And the results header and reproduce command show the value that was used

    Examples:
      | variable    | default                    | override                             |
      | IMAGE       | openresty/openresty:alpine | registry.example.com/nginx-lua:1.2.3 |
      | DURATION    | 30s                        | 60s                                  |
      | THREADS     | 4                          | 8                                    |
      | CONNECTIONS | 100                        | 200                                  |

  @id:bench.performance.benchmark-scenarios.003 @rule:performance.benchmark.fail-fast-when-server-never-starts @inferred @source:bench/run.sh#cleanup
  Scenario: A benchmark server that never comes up stops the run with its logs
    Given the benchmark server does not answer /baseline within about 30 seconds
    When the operator runs the benchmark
    Then the operator sees "nginx did not come up:" followed by the server's logs on stderr
    And the run exits with status 1
    And no scenario is benchmarked and no results file is written

  @id:bench.performance.benchmark-scenarios.004 @rule:performance.benchmark.server-removed-after-run @inferred @source:bench/run.sh#cleanup
  Scenario: The benchmark server is removed when the run ends, and any stale one before it starts
    Given a container named waf-kit-bench may already exist from an earlier run
    When the operator runs the benchmark
    Then any existing waf-kit-bench container is removed before the new server starts
    And the waf-kit-bench container is removed when the run finishes, fails or is interrupted

  @id:bench.performance.benchmark-scenarios.005 @rule:performance.benchmark.load-generator-failure-aborts-run @inferred @source:bench/run.sh#SCENARIOS @questionable
  Scenario: A load generator that cannot run stops the benchmark with a partial results file
    Given the load generator image cannot be started
    When the operator runs the benchmark
    Then the run stops at the failing scenario with a non-zero status
    And the results file keeps the header and rows of earlier scenarios but no later rows and no closing note
