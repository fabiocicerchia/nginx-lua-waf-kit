@domain:performance @area:benchmark-reporting @from:bench/run
Feature: Reporting reproducible benchmark results
  Gives anyone reading the published numbers the exact build, hardware, revision and command behind them, so a figure can be reproduced or distrusted.

  Background:
    Given the benchmark server came up

  @id:bench.performance.benchmark-reporting.001 @rule:performance.benchmark.results-record-provenance @inferred @source:bench/run.sh#cleanup
  Scenario: The results file records the exact build, hardware, revision and command behind the numbers
    Given the image tag openresty/openresty:alpine resolves to a pinned digest
    When the operator runs the benchmark
    Then results.md lists the image tag, image digest and the build string reported by the running server
    And results.md lists the kit revision, host kernel and architecture, core count and CPU model
    And results.md lists the wrk threads, connections and duration and a UTC generation timestamp
    And results.md contains a copy-paste command that re-runs with the same image, duration, threads and connections
    And results.md has a table with columns scenario, req/s, p50, p90, p99
    And the same contents are printed to the operator's terminal at the end

  @id:bench.performance.benchmark-reporting.002 @rule:performance.benchmark.unknown-provenance-marked @inferred @source:bench/run.sh#cleanup @questionable
  Scenario Outline: Provenance that cannot be determined is recorded as unknown rather than guessed
    Given <detail> cannot be determined on this machine
    When the operator runs the benchmark
    Then results.md shows <shown> for <detail>

    Examples:
      | detail                                                          | shown   |
      | image digest (image has no registry digest)                     | unknown |
      | kit revision (not a git checkout)                               | unknown |
      | core count                                                      | ?       |
      | CPU model (no model name in /proc/cpuinfo, e.g. many ARM hosts) | (blank) |

  @id:bench.performance.benchmark-reporting.003 @rule:performance.benchmark.unparsed-figure-shown-as-question-mark @inferred @source:bench/run.sh#SCENARIOS
  Scenario Outline: A figure the load generator did not report is shown as a question mark
    Given the load generator output for a scenario lacks <figure>
    When the operator runs the benchmark
    Then that scenario's row shows ? in the <figure> column
    And the other figures in the row are still shown

    Examples:
      | figure |
      | req/s  |
      | p50    |
      | p90    |
      | p99    |
