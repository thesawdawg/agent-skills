# shellcheck shell=bash
# Integrity metadata is local; source journals are never rewritten by inspection.

# Validate a journal and retain valid records with file/line-only diagnostics.
_journal_validate_file() { # <file> <output-json>
  local partial=false
  if [ -s "$1" ] && [ -n "$(tail -c1 "$1")" ]; then partial=true; fi
  jq -Rn --arg file "$(basename "$1")" --argjson partial "$partial" \
    -f "$DAVE_LIB_DIR/journal-validate.jq" "$1" > "$2"
}

# Build a validated, deduplicated snapshot. The caller verifies source signatures
# before/after this operation because file arrival is outside the local locks.
_journal_snapshot() { # <events-output> <diagnostics-output>
  local stage f n=0
  stage="$(mktemp -d "$LOCAL/.integrity.XXXXXX")" || return 1
  for f in "$JOURNAL_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    case "$(basename "$f")" in
      *.sync-conflict-*)
        jq -nc --arg file "$(basename "$f")" \
          '{events:[],diagnostics:[{file:$file,code:"journal_conflict",severity:"warning"}]}' \
          > "$stage/$n.json" ;;
      *) _journal_validate_file "$f" "$stage/$n.json" || { rm -rf "$stage"; return 1; } ;;
    esac
  done
  [ "$n" -gt 0 ] || printf '{"events":[],"diagnostics":[]}\n' > "$stage/0.json"
  jq -s '
    {events:map(.events) | add, diagnostics:map(.diagnostics) | add}
    | (.events | group_by([.dev,.seq])) as $groups
    | .diagnostics += [$groups[] | select((unique|length) > 1)
        | {code:"divergent_event_identity",severity:"error",dev:.[0].dev,seq:.[0].seq}]
    | .events = [$groups[] | .[0]]' "$stage"/*.json > "$stage/result.json" \
    || { rm -rf "$stage"; return 1; }
  jq -c '.events[]' "$stage/result.json" > "$1"
  jq '.diagnostics' "$stage/result.json" > "$2"
  rm -rf "$stage"
}

# Atomically publish current scan results even when a bad record prevents views
# from being rebuilt. Status remains useful when ordinary reads cannot proceed.
_integrity_store() { # <diagnostics-json>
  local tmp
  tmp="$(mktemp "$LOCAL/.integrity-report.XXXXXX")" || return 1
  jq --arg checked "$(now_iso_utc)" \
    '{checked_at:$checked,diagnostics:.,healthy:all(.[]; .severity != "error")}' \
    "$1" > "$tmp" && mv "$tmp" "$LOCAL/integrity.json"
}

# Read-only preview by default. Applying requires the digest returned by preview,
# preserves the original locally, and imports events into an immutable recovery
# journal rather than changing any device-owned live journal.
_journal_recover() { # <conflict-file> [--apply <sha256>]
  local input="${1:-}" expected="${3:-}" file stage digest apply=0
  [ -n "$input" ] || die "usage: sync journal-conflicts <file> [--apply <sha256>]"
  if [ $# -gt 1 ]; then
    [ $# -eq 3 ] && [ "$2" = --apply ] || die "usage: sync journal-conflicts <file> [--apply <sha256>]"
    apply=1
  fi
  case "$input" in /*) ;; *) input="$DAVE_HOME/$input" ;; esac
  file="$(realpath -e -- "$input")" || die "journal conflict not found"
  [ ! -L "$input" ] && [ -f "$file" ] && \
    [ "$(dirname "$file")" = "$(realpath -e "$JOURNAL_DIR")" ] \
    || die "journal recovery requires a regular file directly inside journal/"
  case "$(basename "$file")" in *.sync-conflict-*.jsonl) ;; *) die "not a journal conflict copy" ;; esac
  digest="$(sha256sum "$file" | cut -d ' ' -f1)"
  stage="$(mktemp -d "$LOCAL/.recovery.XXXXXX")" || return 1
  (
    trap 'rm -rf -- "$stage"' EXIT
    _journal_snapshot "$stage/current.jsonl" "$stage/diagnostics.json" || exit 1
    _journal_validate_file "$file" "$stage/copy.json" || exit 1
    jq -e 'all(.[]; .severity != "error")' "$stage/diagnostics.json" >/dev/null && \
      jq -e '.diagnostics | length == 0' "$stage/copy.json" >/dev/null \
      || { echo "dave: repair malformed records before journal recovery" >&2; exit 1; }
    jq -c '.events[]' "$stage/copy.json" > "$stage/copy.jsonl"
    jq -s '
      group_by([.dev,.seq])
      | {divergent:[.[] | select((unique|length) > 1) | {dev:.[0].dev,seq:.[0].seq}],
         events:[.[] | .[0]]}' "$stage/current.jsonl" "$stage/copy.jsonl" > "$stage/union.json"
    jq -e '.divergent | length == 0' "$stage/union.json" >/dev/null || {
      jq '{error:"divergent_event_identity",events:.divergent}' "$stage/union.json"
      exit 1
    }
    jq -s --arg digest "$digest" --slurpfile copy "$stage/copy.json" '
      # Identities are compared as whole pairs; index/2 would read an array
      # argument as a subsequence and never match one.
      (map([.dev,.seq] | tojson) | INDEX(.)) as $known
      | ($copy[0].events | unique_by([.dev,.seq])) as $incoming
      | [$incoming[] | ([.dev,.seq] | tojson) as $id | $known | has($id)] as $seen
      | {digest:$digest,
         unique_events:([$seen[] | select(. | not)] | length),
         duplicate_events:([$seen[] | select(.)] | length)}' \
      "$stage/current.jsonl"
    [ "$apply" -eq 1 ] || exit 0
    [ "$digest" = "$expected" ] && \
      [ "$(sha256sum "$file" | cut -d ' ' -f1)" = "$digest" ] \
      || { echo "dave: conflict changed; refresh the recovery preview" >&2; exit 1; }
    mkdir -p "$LOCAL/recovery"
    cp -p -- "$file" "$LOCAL/recovery/$digest.jsonl" || exit 1
    # Publish original event identities. Valid identical records are deduplicated
    # on replay, so repeating this import cannot duplicate history.
    jq -c -s 'unique_by([.dev,.seq]) | sort_by(.ts,.dev,.seq)[]' \
      "$stage/copy.jsonl" > "$stage/recovered.jsonl" || exit 1
    local recovery_digest target
    recovery_digest="$(sha256sum "$stage/recovered.jsonl" | cut -d ' ' -f1)"
    target="$JOURNAL_DIR/recovery-$recovery_digest.jsonl"
    cp "$stage/recovered.jsonl" "$target.tmp" && mv -f "$target.tmp" "$target" || exit 1
    # Recheck after backup/import, before removing the conflict source.
    [ "$(sha256sum "$file" | cut -d ' ' -f1)" = "$digest" ] || {
      echo "dave: conflict changed during recovery; preserved source and imported snapshot" >&2; exit 1;
    }
    rm -- "$file"
    views_rebuild || {
      echo "dave: journal recovery recorded; views stale, do not repeat import" >&2
      exit 0
    }
  )
}
