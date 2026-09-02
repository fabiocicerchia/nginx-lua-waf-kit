#!/usr/bin/env bash
# Per-module would-reject rates, from the logs a log_only rollout produces.
#
# WHY THIS IS A SCRIPT AND NOT A GREP YOU TYPE: the number that matters is a
# RATE, and a rate needs a denominator. Counting "would reject" lines tells you
# how many requests each module scored badly; it does not tell you what
# fraction of your traffic that is, and the fraction is the whole decision.
# The denominator comes from the ACCESS log, which is why the config writes
# both.
#
#   ./analyse.sh                                   # the paths compose.yml uses
#   ./analyse.sh /var/log/nginx/waf.log /var/log/nginx/access.log
#
# What comes out is postable: counts and percentages, no IPs, no tokens, no
# user-agents, no paths. The issue this closes asks for aggregate rates only,
# and the way to be sure of that is for the script never to print a field that
# could carry one.
set -euo pipefail

ERROR_LOG="${1:-./logs/waf.log}"
ACCESS_LOG="${2:-./logs/access.log}"

for f in "$ERROR_LOG" "$ACCESS_LOG"; do
  if [ ! -r "$f" ]; then
    echo "cannot read $f" >&2
    echo "  run 'docker compose up -d', send traffic, then try again." >&2
    exit 1
  fi
done

total="$(wc -l < "$ACCESS_LOG" | tr -d ' ')"
if [ "$total" -eq 0 ]; then
  echo "the access log is empty: no traffic has reached this yet, so" >&2
  echo "there is nothing to compute a rate against." >&2
  exit 1
fi

# Every module logs the same shape, which is what makes this one loop:
#   <module>: would reject <subject>: <why> (log_only)
MODULES=(ratelimit bot_heuristics jwt geo_asn)

printf 'log_only rollout — %s request(s) in the window\n\n' "$total"
printf '%-16s %10s %9s  %s\n' "module" "would-reject" "rate" "verdict"
printf -- '------------------------------------------------------------\n'

any_enforcing=0
for m in "${MODULES[@]}"; do
  n="$(grep -c "$m: would reject " "$ERROR_LOG" || true)"
  # A "rejected" line under a log_only rollout means that module is NOT in
  # log_only. Worth shouting about: the run is then measuring a configuration
  # that is already turning traffic away.
  enforced="$(grep -c "$m: rejected " "$ERROR_LOG" || true)"
  pct="$(awk -v n="$n" -v t="$total" \
    'BEGIN { printf "%.2f", (t ? 100*n/t : 0) }')"

  verdict="—"
  # Bands, not a threshold: what is tolerable depends on the module. A rate
  # limiter that would reject 2% of requests is doing its job; a bot heuristic
  # that would reject 2% is about to remove one customer in fifty.
  case "$m" in
    ratelimit)
      awk -v p="$pct" 'BEGIN { exit !(p > 5) }' &&
        verdict="high for a limiter — check the capacity" ;;
    bot_heuristics|geo_asn|jwt)
      awk -v p="$pct" 'BEGIN { exit !(p > 1) }' &&
        verdict="TOO HIGH to enforce — your users until proven otherwise" ;;
  esac
  if [ "$n" -eq 0 ]; then
    verdict="nothing scored — clean traffic, or the module is not wired in"
  fi

  printf '%-16s %10s %8s%%  %s\n' "$m" "$n" "$pct" "$verdict"
  if [ "$enforced" -gt 0 ]; then
    any_enforcing=1
    printf '%-16s %10s %9s  %s\n' "" "$enforced" "" \
      "!! REJECTED for real — this module is not in log_only"
  fi
done

# The mirror module has no reject path at all; its number is how much traffic
# it duplicated, which is a load question rather than a false-positive one.
mirrored="$(grep -c "mirror: " "$ERROR_LOG" || true)"
printf '\n%-16s %10s %9s  %s\n' "mirror" "$mirrored" "" \
  "requests duplicated (load, not false positives)"

echo
if [ "$any_enforcing" -eq 1 ]; then
  echo "WARNING: at least one module rejected a request. A log_only run"
  echo "that turns traffic away is not measuring what it thinks it is —"
  echo "the rates above are for a configuration already enforcing."
fi

cat <<'NOTE'

Reading this
  A would-reject rate is a FALSE-POSITIVE rate only if you believe none of that
  traffic was hostile. On an internet-facing host some of it was; on an internal
  one, almost none. Sample the lines by hand before trusting either reading —
  they carry the reason, which is the part that says which.

  Rate the threshold, not the count. A week at 0.1% and a day at 0.1% are the
  same answer; a week at 0.1% and a week of one client retrying are not, and
  only the reasons tell them apart.

Nothing above identifies a client. Post it as it is.
NOTE
