# Specifications of nginx-lua-waf-kit / bench

What this code does, one atomic Gherkin scenario per behaviour, read from the code by code-atlas.
Tags: `@verified` a test asserts it · `@inferred` read from the code only · `@gap` an entry point no test covers · `@human` written or amended by a person, never rewritten.

## Performance measurement
Quantifying the cost each module adds to the request path.

- **Benchmark reporting**: [Reporting reproducible benchmark results](performance/benchmark-reporting/benchmark-results-report.feature) (3)
- **Benchmark scenarios**: [Benchmarking each module against a baseline](performance/benchmark-scenarios/benchmark-module-cost.feature) (5)
