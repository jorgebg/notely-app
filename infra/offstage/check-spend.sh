#!/usr/bin/env bash
# Prints the latest spend the budget reported, and exits 1 once it passes the budget.
# Run before every apply of a rehearsal. Billing data arrives hours late: a quiet answer
# means "nothing reported yet", not "nothing spent".
set -euo pipefail
source "$(dirname "$0")/../demo.env"
LAST="$(dirname "$0")/.last-spend.json"

# One JSON array of messages; each data field is base64 of a (possibly multi-line) JSON object.
# Keep the newest month's highest cost (it only grows within a month).
latest="$(gcloud pubsub subscriptions pull budget-check --project "$GUARD_PROJECT" \
    --limit 100 --auto-ack --format=json 2>/dev/null \
  | jq -r '.[].message.data' | while read -r b64; do base64 -d <<<"$b64"; echo; done \
  | jq -s 'map(select(.costAmount != null)) | sort_by(.costIntervalStart, .costAmount) | last')"
[[ -n "$latest" && "$latest" != "null" ]] && echo "$latest" > "$LAST"
[[ -f "$LAST" ]] || { echo "no budget update received yet"; exit 0; }

jq -r '"spend since \(.costIntervalStart[:10]): \(.costAmount) of \(.budgetAmount) \(.currencyCode)"' "$LAST"
jq -e '.costAmount <= .budgetAmount' "$LAST" >/dev/null || { echo "OVER BUDGET: stop" >&2; exit 1; }
