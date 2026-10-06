#!/usr/bin/env bash
# Call a System One model (TypeSafe's Jev or a wire-compatible local server)
# over the /v1/systemone API.
#
# Usage:
#   systemone.sh probe  [base-url ...]
#   systemone.sh models <base-url>
#   systemone.sh ask    <base-url> <model-or-empty> <request-file|->
#
# <base-url> e.g. http://127.0.0.1:8000 or https://api.typesafe.ai.
# probe prints the first base URL whose GET /v1/models answers; candidates are
# explicit arguments, then $TYPESAFE_BASE_URL, then http://127.0.0.1:8000,
# http://127.0.0.1:8080, and https://api.typesafe.ai only when
# $TYPESAFE_API_KEY is set. ask posts the request body (a JSON object), sets
# .model to the argument unless it is empty, and prints the response JSON on
# success; '-' reads the request from stdin.
#
# Sends "Authorization: Bearer $TYPESAFE_API_KEY" only when that variable is
# non-empty. On failure prints the HTTP status and raw response body to
# stderr and exits non-zero.

set -euo pipefail
umask 077
tmp=""
body_tmp=""
trap '[ -z "$tmp" ] || rm -f "$tmp"; [ -z "$body_tmp" ] || rm -f "$body_tmp"' EXIT

cmd="${1:-}"
[ -n "$cmd" ] || { echo "usage: systemone.sh {probe|models|ask} ..." >&2; exit 2; }
shift

need_jq() { command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }; }

auth=()
if [ -n "${TYPESAFE_API_KEY:-}" ]; then
  auth=(-H "Authorization: Bearer $TYPESAFE_API_KEY")
fi

case "$cmd" in
  probe)
    need_jq
    if [ "$#" -gt 0 ]; then
      candidates=("$@")
    else
      candidates=()
      [ -n "${TYPESAFE_BASE_URL:-}" ] && candidates+=("$TYPESAFE_BASE_URL")
      candidates+=("http://127.0.0.1:8000" "http://127.0.0.1:8080")
      [ -n "${TYPESAFE_API_KEY:-}" ] && candidates+=("https://api.typesafe.ai")
    fi
    tried=()
    found=""
    for base in "${candidates[@]}"; do
      base="${base%/}"
      tried+=("$base")
      if curl -sS --connect-timeout 5 --max-time 10 "${auth[@]}" "$base/v1/models" 2>/dev/null \
        | jq -e 'type == "object" and (.models | type) == "array"' >/dev/null 2>&1; then
        found="$base"
        break
      fi
    done
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
    else
      echo "no System One endpoint answered (tried: ${tried[*]})" >&2
      exit 1
    fi
    ;;

  models)
    base="${1:?base-url required}"
    need_jq
    base="${base%/}"
    tmp=$(mktemp)
    status=$(curl -sS --connect-timeout 10 --max-time 30 -o "$tmp" -w '%{http_code}' \
      "${auth[@]}" "$base/v1/models") || status="000"
    case "$status" in
      2*) ;;
      *)
        echo "HTTP $status" >&2
        cat "$tmp" >&2
        exit 1
        ;;
    esac
    jq -er '.models[] | [.name, (.description // "")] | @tsv' "$tmp" || {
      cat "$tmp" >&2
      exit 1
    }
    ;;

  ask)
    base="${1:?base-url required}"; model="${2-}"; request="${3:?request-file required}"
    need_jq
    base="${base%/}"
    if [ "$request" = "-" ]; then
      body=$(cat)
    else
      body=$(cat -- "$request") || { echo "cannot read request file: $request" >&2; exit 2; }
    fi
    echo "$body" | jq -e 'type == "object"' >/dev/null 2>&1 || {
      echo "request body must be a JSON object" >&2
      exit 2
    }
    if [ -n "$model" ]; then
      body=$(echo "$body" | jq --arg model "$model" '.model = $model')
    fi
    body_tmp=$(mktemp)
    printf '%s' "$body" > "$body_tmp"
    tmp=$(mktemp)
    status=$(curl -sS --connect-timeout 10 --max-time 120 -o "$tmp" -w '%{http_code}' \
      "${auth[@]}" -H "Content-Type: application/json" --data-binary "@$body_tmp" \
      "$base/v1/systemone") || status="000"
    case "$status" in
      2*) ;;
      *)
        echo "HTTP $status" >&2
        cat "$tmp" >&2
        exit 1
        ;;
    esac
    jq -e 'type == "object" and (.answers | type) == "object"' "$tmp" >/dev/null 2>&1 || {
      echo "malformed response (no answers object)" >&2
      cat "$tmp" >&2
      exit 1
    }
    jq . "$tmp"
    ;;

  *)
    echo "usage: systemone.sh {probe|models|ask} ..." >&2
    exit 2
    ;;
esac
