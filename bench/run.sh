#!/usr/bin/env bash
# Measure what each module adds to the request path, against a baseline from the
# same nginx process. Writes results.md.
#
#   ./run.sh                       # defaults below
#   IMAGE=... DURATION=60s ./run.sh
#
# Needs docker. The load generator runs in a container too, so the only thing
# that varies between runs is the machine.

set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${IMAGE:-openresty/openresty:alpine}"
WRK_IMAGE="${WRK_IMAGE:-williamyeh/wrk}"
DURATION="${DURATION:-30s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
PORT="${PORT:-8080}"
NAME="waf-kit-bench"

SCENARIOS=(baseline ratelimit ratelimit-log bots geo mirror all)

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "starting $IMAGE"
docker run -d --name "$NAME" -p "$PORT:8080" \
  -v "$PWD/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro" \
  -v "$PWD/..:/kit:ro" \
  "$IMAGE" >/dev/null

# Fail fast and loudly rather than benchmarking a container that never came up.
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/baseline" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "${ready:-0}" != "1" ]; then
  echo "nginx did not come up:" >&2
  docker logs "$NAME" >&2
  exit 1
fi

hw="$(uname -srm)"
cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"

{
  echo "# Results"
  echo
  echo "- image: \`$IMAGE\`"
  echo "- host: $hw, $cores cores"
  echo "- wrk: $THREADS threads, $CONNECTIONS connections, $DURATION"
  echo "- generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "| scenario | req/s | p50 | p90 | p99 |"
  echo "| --- | --- | --- | --- | --- |"
} > results.md

for scenario in "${SCENARIOS[@]}"; do
  echo "benchmarking /$scenario"
  out="$(docker run --rm --network host "$WRK_IMAGE" \
    -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" --latency \
    "http://127.0.0.1:$PORT/$scenario")"

  rps="$(awk '/Requests\/sec/ {print $2}' <<< "$out")"
  p50="$(awk '/^ *50%/ {print $2}' <<< "$out")"
  p90="$(awk '/^ *90%/ {print $2}' <<< "$out")"
  p99="$(awk '/^ *99%/ {print $2}' <<< "$out")"
  echo "| \`$scenario\` | ${rps:-?} | ${p50:-?} | ${p90:-?} | ${p99:-?} |" >> results.md
done

{
  echo
  echo "Added latency and throughput cost are the difference from the"
  echo "\`baseline\` row, which is the same nginx build with no Lua in the path."
} >> results.md

echo
cat results.md
