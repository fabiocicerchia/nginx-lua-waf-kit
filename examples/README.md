# Examples

Runnable, self-contained examples. Each subfolder (or file) should run with a
single command and show one clear use case.

- `basic/` — minimal end-to-end example.
- `log-only/` — all five modules loaded and **none of them enforcing**, plus
  `analyse.sh`, which turns a week of logs into a per-module would-reject rate.
  This is the first deployment: the thresholds shipped in
  `waf.conf.example` are a judgement until real traffic has been measured
  against them, and a bot heuristic tuned on somebody else's traffic will
  reject your customers.

## Versioning

These files are configuration for a specific nginx-lua release, named in
`compat.json` and tagged as `examples/nginx-lua-<release>`.

```sh
git checkout examples/nginx-lua-v1.31.2
```

**Releasing:** an nginx-lua release that changes anything these examples touch
needs the examples updated, `compat.json` bumped to the new release, and the
tag moved. Pushing the `compat.json` change to `main` does the tagging — see
`.github/workflows/example-tag.yml`, which refuses to tag against a release
that does not exist, because a tag naming a nonexistent runtime looks checkable
and is not.
