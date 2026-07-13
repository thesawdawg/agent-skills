#!/usr/bin/env bash
# Offload a task to an Ollama model, local or remote, over the HTTP API.
#
# Usage:
#   ollama-task.sh models  <host>
#   ollama-task.sh run     <host> <model> <prompt>
#   ollama-task.sh start   <state-file> <host> <model> <system-or-empty> <prompt>
#   ollama-task.sh send    <state-file> <prompt>
#
# <host> e.g. http://localhost:11434 or an external Ollama API base URL.
# <state-file> holds a JSON {"host":..,"model":..,"messages":[...]} for a
# multi-turn chat thread. One state file = one conversation.
#
# Prints only the model's reply to stdout. On failure prints the raw HTTP
# response body to stderr and exits non-zero.

set -euo pipefail

cmd="${1:-}"
[ -n "$cmd" ] || { echo "usage: ollama-task.sh {models|run|start|send} ..." >&2; exit 2; }
shift

need_jq() { command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }; }

case "$cmd" in
  models)
    host="${1:?host required}"
    curl -fsS "$host/api/tags" | (need_jq; jq -r '.models[].name')
    ;;

  run)
    host="${1:?host required}"; model="${2:?model required}"; prompt="${3:?prompt required}"
    need_jq
    body=$(jq -n --arg model "$model" --arg prompt "$prompt" \
      '{model: $model, prompt: $prompt, stream: false}')
    resp=$(curl -fsS "$host/api/generate" -d "$body") || { echo "$resp" >&2; exit 1; }
    echo "$resp" | jq -r '.response'
    ;;

  start)
    state_file="${1:?state-file required}"; host="${2:?host required}"; model="${3:?model required}"
    system="${4:-}"; prompt="${5:?prompt required}"
    need_jq
    messages="[]"
    if [ -n "$system" ]; then
      messages=$(jq -n --arg c "$system" '[{role:"system", content:$c}]')
    fi
    messages=$(echo "$messages" | jq --arg c "$prompt" '. + [{role:"user", content:$c}]')
    body=$(jq -n --arg model "$model" --argjson messages "$messages" \
      '{model: $model, messages: $messages, stream: false}')
    resp=$(curl -fsS "$host/api/chat" -d "$body") || { echo "$resp" >&2; exit 1; }
    reply=$(echo "$resp" | jq -r '.message.content')
    messages=$(echo "$messages" | jq --arg c "$reply" '. + [{role:"assistant", content:$c}]')
    jq -n --arg host "$host" --arg model "$model" --argjson messages "$messages" \
      '{host: $host, model: $model, messages: $messages}' > "$state_file"
    echo "$reply"
    ;;

  send)
    state_file="${1:?state-file required}"; prompt="${2:?prompt required}"
    [ -f "$state_file" ] || { echo "no active session: $state_file not found (run 'start' first)" >&2; exit 1; }
    need_jq
    host=$(jq -r '.host' "$state_file")
    model=$(jq -r '.model' "$state_file")
    messages=$(jq --arg c "$prompt" '.messages + [{role:"user", content:$c}]' "$state_file")
    body=$(jq -n --arg model "$model" --argjson messages "$messages" \
      '{model: $model, messages: $messages, stream: false}')
    resp=$(curl -fsS "$host/api/chat" -d "$body") || { echo "$resp" >&2; exit 1; }
    reply=$(echo "$resp" | jq -r '.message.content')
    messages=$(echo "$messages" | jq --arg c "$reply" '. + [{role:"assistant", content:$c}]')
    jq -n --arg host "$host" --arg model "$model" --argjson messages "$messages" \
      '{host: $host, model: $model, messages: $messages}' > "$state_file"
    echo "$reply"
    ;;

  *)
    echo "usage: ollama-task.sh {models|run|start|send} ..." >&2
    exit 2
    ;;
esac
