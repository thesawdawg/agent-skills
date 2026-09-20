#!/usr/bin/env bash
# run.sh — tests for the dave.sh state layer.
#
# Plain shell, no bats dependency. Every test runs against a throwaway DAVE_HOME
# under $TMPDIR, so running this can never touch the user's real ~/.dave.
#
#   ./test/run.sh            # run everything
#   ./test/run.sh focus      # run tests whose name matches a pattern

set -Euo pipefail
ERROR_LOG=$(mktemp)
trap 'rm -f "$ERROR_LOG"' EXIT
trap 'printf "unexpected failure at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >> "$ERROR_LOG"' ERR

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAVE="$TEST_DIR/../dave.sh"
FILTER="${1:-}"

PASS=0; FAIL=0; FAILED_NAMES=()

# A fresh, isolated state tree per test.
new_home() {
  DAVE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dave-test.XXXXXX")"
  export DAVE_HOME
}

dave() { "$DAVE" "$@"; }

# This device's journal file — fixtures that need a hand-written event (or a
# journal-side edit, since the views are derived) all go through this.
dev_journal() { printf '%s/journal/%s.jsonl\n' "$DAVE_HOME" "$(jq -r .id "$DAVE_HOME/.local/device.json")"; }

jsonl_count() { [ -f "$1" ] && grep -c . "$1" || echo 0; }

ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi
}
# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "output did not contain [$3]" ;; esac
}
# assert_exit <name> <expected-code> <command...>
assert_exit() {
  local name="$1" want="$2"; shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  assert_eq "$name" "$want" "$got"
}

run_test() {
  local name="$1"
  if [ "${DAVE_TEST_SKIP_SYNC:-0}" = 1 ] && [ "$name" = sync ]; then return 0; fi
  [ -z "$FILTER" ] || case "$name" in *"$FILTER"*) ;; *) return 0 ;; esac
  printf '%s\n' "$name"
  new_home
  "test_${name//[^a-zA-Z0-9]/_}"
  rm -rf "$DAVE_HOME"
}

# --------------------------------------------------------------------- setup

test_init() {
  local out; out="$(dave init)"
  assert_eq "init prints the home path" "$DAVE_HOME" "$out"
  assert_eq "init writes schema_version" "3" "$(jq -r .schema_version "$DAVE_HOME/.local/views/state.json")"
  for f in config.json priorities.md .local/config.json \
           .local/render/parking-lot.md \
           .local/views/state.json .local/device.json; do
    [ -f "$DAVE_HOME/$f" ] && ok "init creates $f" || no "init creates $f" "missing"
  done
  [ -d "$DAVE_HOME/journal" ] && ok "init creates journal/" || no "init creates journal/" "missing"
  for d in missions intake projects .local/render/log; do
    [ -d "$DAVE_HOME/$d" ] && ok "init creates $d/" || no "init creates $d/" "missing"
  done
  # The rendered tree is generated output — it must never sit at the vault root.
  [ ! -f "$DAVE_HOME/parking-lot.md" ] && ok "init writes no root parking-lot.md" \
    || no "init writes no root parking-lot.md" "found at root"
}

test_init_idempotent() {
  dave init >/dev/null
  echo "hand-edited" >> "$DAVE_HOME/priorities.md"
  local before; before="$(cat "$DAVE_HOME/priorities.md")"
  dave init >/dev/null
  assert_eq "init does not clobber priorities.md" "$before" "$(cat "$DAVE_HOME/priorities.md")"
}

test_not_set_up_exits_3() {
  assert_exit "config on an empty home exits 3" 3 dave config
  assert_exit "brief on an empty home exits 3" 3 dave brief
}

# A schema-2 tree by hand: every root file the old layout kept, two log days,
# an open and a retired parking item, a project carrying a path. Staged, not
# run, so both migrate tests can put variations on it.
stage_legacy_tree() {
  mkdir -p "$DAVE_HOME/log" "$DAVE_HOME/missions" "$DAVE_HOME/intake" \
           "$DAVE_HOME/projects/legacy-proj" "$DAVE_HOME/.git"
  cp "$TEST_DIR/../../templates/priorities-template.md" "$DAVE_HOME/priorities.md"
  echo 'node_modules' > "$DAVE_HOME/.gitignore"
  jq -n '{user:{name:"T"}, projects:{root:"/tmp/work"},
          hooks:{session_start:true}, sync:{remote:"git@x"}}' > "$DAVE_HOME/config.json"
  jq -n '{focus:{ref:"RM-1",label:"old work",started:"2026-01-05T10:00:00+00:00"},
          focus_stack:[], active_mission:null, drift_events:[],
          last_intake:"2026-01-01 (board)", last_brief:null,
          schema_version:2, created:"2025-12-01T08:00:00+00:00"}' > "$DAVE_HOME/state.json"
  echo '{}' > "$DAVE_HOME/notes.json"
  jq -n '[{id:"c1",who:"bob",what:"the thing",due:"2030-01-01",ref:"",project:"",
           created:"2026-01-01T00:00:00+00:00",status:"open",history:[]}]' \
    > "$DAVE_HOME/commitments.json"
  jq -n '{m1:{slug:"m1",project:"legacy-proj",status:"open"}}' > "$DAVE_HOME/missions.json"
  printf '%s\n' '{"ref":"RM-1","started":"2026-01-05T10:00:00+00:00","ended":"2026-01-05T11:00:00+00:00","minutes":60}' \
    > "$DAVE_HOME/sessions.jsonl"
  printf '%s\n' '{"id":"m1#1","mission":"m1","agent":"codex","status":"assigned"}' \
    > "$DAVE_HOME/assignments.jsonl"
  cat > "$DAVE_HOME/log/2026-01-05.md" <<'EOF'
# 2026-01-05
- `09:15` started work
- `10:30` **RM-1** — finished the thing
a stray line that does not parse
EOF
  printf -- '- `14:00` another entry\n' > "$DAVE_HOME/log/2026-01-06.md"
  cat > "$DAVE_HOME/parking-lot.md" <<'EOF'
# Parking lot
- [ ] revisit the idea _(parked 2026-01-03 16:00, while on RM-1)_
- [x] done item _(parked 2026-01-02 09:00)_ _(retired 2026-01-04)_
EOF
  jq -n '{slug:"legacy-proj", name:"Legacy Proj", path:"/code/legacy-proj",
          status:"active", cadence:"weekly", refs:["RM-1"],
          last_touched:"2026-01-05T12:00:00+00:00"}' \
    > "$DAVE_HOME/projects/legacy-proj/project.json"
}

test_migrate() {
  stage_legacy_tree

  assert_exit "un-migrated tree exits 4 on a read" 4 dave state
  assert_exit "init on a legacy tree exits 4" 4 dave init

  local out; out="$(dave migrate)"
  assert_contains "migrate reports the version change" "$out" "schema 2 -> 3"
  assert_contains "migrate counts the log import" "$out" "log.add: 4"
  assert_contains "migrate warns about a brief-less mission" "$out" "no brief file"

  assert_eq "schema stamped" "3" "$(jq -r .schema_version "$DAVE_HOME/.local/views/state.json")"
  assert_eq "focus preserved" "RM-1" "$(jq -r '.focus.ref' "$DAVE_HOME/.local/views/state.json")"
  assert_eq "created folds from the legacy stamp" "2025-12-01T08:00:00+00:00" \
    "$(jq -r .created "$DAVE_HOME/.local/views/state.json")"
  assert_eq "promise imported" "bob" "$(jq -r '.[0].who' "$DAVE_HOME/.local/views/commitments.json")"

  assert_eq "day one has all three lines (raw included)" "3" \
    "$(jq '.["2026-01-05"] | length' "$DAVE_HOME/.local/views/log.json")"
  assert_eq "day two has one line" "1" \
    "$(jq '.["2026-01-06"] | length' "$DAVE_HOME/.local/views/log.json")"
  assert_eq "log time preserved" "09:15" \
    "$(jq -r '.["2026-01-05"][] | select(.text == "started work") | .time' "$DAVE_HOME/.local/views/log.json")"
  assert_eq "log ref parsed" "RM-1" \
    "$(jq -r '.["2026-01-05"][] | select(.ref != "") | .ref' "$DAVE_HOME/.local/views/log.json")"
  assert_eq "unparseable line kept verbatim" "a stray line that does not parse" \
    "$(jq -r '.["2026-01-05"][] | select(.time == "00:00") | .text' "$DAVE_HOME/.local/views/log.json")"

  assert_eq "one open parked item" "1" \
    "$(jq '[.[] | select(.done == null)] | length' "$DAVE_HOME/.local/views/parked.json")"
  assert_eq "one retired parked item" "1" \
    "$(jq '[.[] | select(.done != null)] | length' "$DAVE_HOME/.local/views/parked.json")"
  assert_eq "retired date preserved" "2026-01-04" \
    "$(jq -r '.[] | select(.done != null) | .done' "$DAVE_HOME/.local/views/parked.json")"
  assert_eq "parked ref preserved" "RM-1" \
    "$(jq -r '.[] | select(.done == null) | .ref' "$DAVE_HOME/.local/views/parked.json")"
  assert_eq "import ids carry the marker" "2" \
    "$(jq '[.[] | select(.id | test("-import-"))] | length' "$DAVE_HOME/.local/views/parked.json")"

  assert_eq "project path moved to local config" "/code/legacy-proj" \
    "$(jq -r '.projects.paths["legacy-proj"]' "$DAVE_HOME/.local/config.json")"
  assert_eq "path stripped from project.json" "false" \
    "$(jq 'has("path")' "$DAVE_HOME/projects/legacy-proj/project.json")"
  assert_eq "legacy ref survived as a view event" "RM-1" \
    "$(jq -r '.["legacy-proj"].refs[0]' "$DAVE_HOME/.local/views/projects.json")"
  assert_eq "last_touched survived as a view event" "2026-01-05T12:00:00+00:00" \
    "$(jq -r '.["legacy-proj"].last_touched' "$DAVE_HOME/.local/views/projects.json")"
  assert_eq "projects.root moved to local config" "/tmp/work" \
    "$(jq -r '.projects.root' "$DAVE_HOME/.local/config.json")"
  assert_eq "hooks moved to local config" "true" \
    "$(jq -r '.hooks.session_start' "$DAVE_HOME/.local/config.json")"
  assert_eq "sync moved to local config" "git@x" \
    "$(jq -r '.sync.remote' "$DAVE_HOME/.local/config.json")"
  assert_eq "shared config sheds the local keys" "false" \
    "$(jq 'has("hooks") or has("sync") or (.projects | has("root"))' "$DAVE_HOME/config.json")"

  local dest; dest="$(printf '%s\n' "$DAVE_HOME"/.migrated-*)"
  local ok_all=1 f
  for f in state.json notes.json commitments.json missions.json sessions.jsonl \
           assignments.jsonl parking-lot.md log .git .gitignore; do
    [ -e "$dest/$f" ] || ok_all=0
  done
  [ "$ok_all" = 1 ] && ok ".migrated holds every original" \
    || no ".migrated holds every original" "$dest incomplete"
  assert_eq "import lives in its own journal" "1" \
    "$(printf '%s\n' "$DAVE_HOME"/journal/*-import.jsonl | grep -c .)"

  local out2; out2="$(dave migrate)"
  assert_contains "second migrate reports already migrated" "$out2" "already migrated"
  assert_exit "a migrated tree stops exiting 4" 0 dave state
}

# The M1 importer already folded the JSON into the journal but left markdown
# behind: migrate must import only log/park and never write a second snapshot.
test_migrate_partial() {
  stage_legacy_tree
  mkdir -p "$DAVE_HOME/journal"
  jq -nc --arg ts "2026-01-05T00:00:00+00:00" \
    '{ts:$ts, seq:0, dev:"olddev-import", sid:"migrate", type:"import.snapshot",
      data:{state:{focus:{ref:"X",label:"x",started:$ts}, focus_stack:[],
                   active_mission:null, drift_events:[], last_intake:null,
                   last_brief:null, schema_version:2,
                   created:"2026-01-01T00:00:00+00:00"}}}' \
    > "$DAVE_HOME/journal/olddev-import.jsonl"

  local out; out="$(dave migrate)"
  assert_contains "partial migrate still imports log" "$out" "log.add: 4"
  assert_contains "partial migrate still imports park" "$out" "park.add: 2"
  assert_eq "no second snapshot was written" "1" \
    "$(jq -sc '[.[] | select(.type == "import.snapshot")] | length' "$DAVE_HOME"/journal/*.jsonl)"
  assert_eq "snapshot focus came from the journal, not state.json" "X" \
    "$(jq -r '.focus.ref' "$DAVE_HOME/.local/views/state.json")"
  assert_exit "partial migrate leaves a clean tree" 0 dave state

  # The .migrated marker exists even though nothing moved, so a rerun is
  # refused rather than appending a second batch of project events.
  local lines_before out2
  lines_before="$(cat "$DAVE_HOME"/journal/*-import.jsonl | grep -c .)"
  out2="$(dave migrate)"
  assert_contains "partial rerun reports already migrated" "$out2" "already migrated"
  assert_eq "partial rerun appends nothing" "$lines_before" \
    "$(cat "$DAVE_HOME"/journal/*-import.jsonl | grep -c .)"

  # The narrower partial shape: a journal, no root legacy files at all, and a
  # project.json still carrying the inline fields. Nothing moves, so the
  # marker dir is the only thing the rerun guard can see.
  rm -rf "$DAVE_HOME"; new_home
  mkdir -p "$DAVE_HOME/journal" "$DAVE_HOME/projects/p1"
  printf '{}\n' > "$DAVE_HOME/config.json"
  printf '%s\n' '{"slug":"p1","path":"/code/p1","refs":["R1"],"last_touched":"2026-01-01T00:00:00+00:00"}' \
    > "$DAVE_HOME/projects/p1/project.json"
  jq -nc '{ts:"2026-01-05T00:00:00+00:00", seq:0, dev:"olddev-import",
           sid:"migrate", type:"import.snapshot",
           data:{state:{focus:null, focus_stack:[], active_mission:null,
                        drift_events:[], last_intake:null, last_brief:null,
                        schema_version:2, created:"2026-01-01T00:00:00+00:00"}}}' \
    > "$DAVE_HOME/journal/olddev-import.jsonl"

  dave migrate >/dev/null
  assert_eq "journal-only migrate strips the project fields" "false" \
    "$(jq 'has("path") or has("refs") or has("last_touched")' "$DAVE_HOME/projects/p1/project.json")"
  lines_before="$(cat "$DAVE_HOME"/journal/*-import.jsonl | grep -c .)"
  out2="$(dave migrate)"
  assert_contains "journal-only rerun reports already migrated" "$out2" "already migrated"
  assert_eq "journal-only rerun appends nothing" "$lines_before" \
    "$(cat "$DAVE_HOME"/journal/*-import.jsonl | grep -c .)"
}

# The merged-config memo must die on a local-config write inside the same
# process — a stale read here is exactly the bug the cache had to not cause.
test_config_cache() {
  dave init >/dev/null
  local before after
  before="$(dave config | jq -r '.x_probe // "absent"')"
  assert_eq "cache starts clean" "absent" "$before"
  # One shell, two calls: the write must invalidate the memo the read warms.
  # (DAVE_HOME is already exported by new_home, so the subshell inherits it.)
  after="$(bash -c '
    set -e
    . "'"$TEST_DIR"'/../lib/common.sh"
    config_get ".x_probe" "warm" >/dev/null
    json_edit "'"$DAVE_HOME"'/.local/config.json" ".x_probe = 42"
    config_get ".x_probe" "stale"
  ')"
  assert_eq "config_get sees a same-process local edit" "42" "$after"
}

# --------------------------------------------------------------------- focus

test_focus() {
  dave init >/dev/null
  assert_contains "focus show with none set" "$(dave focus show)" "(none set)"
  dave focus set RM-4471 "retry double-fire" >/dev/null
  assert_contains "focus show after set" "$(dave focus show)" "RM-4471 — retry double-fire"
  assert_eq "focus is stored" "RM-4471" "$(jq -r .focus.ref "$DAVE_HOME/.local/views/state.json")"
  dave focus clear >/dev/null
  assert_eq "focus clear empties it" "null" "$(jq -r '.focus // "null"' "$DAVE_HOME/.local/views/state.json")"
}

test_drift() {
  dave init >/dev/null
  assert_contains "drift with no focus" "$(dave drift)" "no focus set"
  dave focus set RM-4471 "retry" >/dev/null
  local out; out="$(dave drift)"
  assert_contains "drift reports minutes" "$out" "m on focus"
  assert_contains "drift flags an unlisted ref" "$out" "on-list: NO"
  printf '\n1. **RM-4471** — retry\n' >> "$DAVE_HOME/priorities.md"
  assert_contains "drift sees a listed ref" "$(dave drift)" "on-list: yes"
}

# ------------------------------------------------------------------- capture

test_journal() {
  dave init >/dev/null
  dave focus set RM-4471 "retry" >/dev/null
  dave log "traced it to the retry middleware" >/dev/null
  assert_contains "log stamps the focus ref" "$(dave today)" "**RM-4471**"
  assert_contains "log keeps the text" "$(dave today)" "traced it to the retry middleware"
  dave park "rewrite the CSV exporter" >/dev/null
  local parked; parked="$(dave parked)"
  assert_contains "park records the item" "$parked" "rewrite the CSV exporter"
  assert_contains "park stamps what it pulled against" "$parked" "while on RM-4471"
  assert_contains "standup covers today" "$(dave standup 1)" "retry middleware"
  assert_contains "standup with no history" "$(dave standup 99)" "retry middleware"
}

test_priorities_set() {
  dave init >/dev/null
  printf '# P\n\n## Now\n\n1. **RM-1** — the thing\n' | dave priorities set >/dev/null
  assert_contains "priorities set replaces the file" "$(dave priorities)" "**RM-1** — the thing"
  assert_contains "priorities set confirms" "$(printf '# P\n\nx\n' | dave priorities set)" "priorities: updated"
  local before; before="$(cat "$DAVE_HOME/priorities.md")"
  local got=0
  printf '   \n' | dave priorities set >/dev/null 2>&1 || got=$?
  assert_eq "whitespace-only stdin exits 1" "1" "$got"
  assert_eq "a refused write leaves the file intact" "$before" "$(cat "$DAVE_HOME/priorities.md")"
}

test_parked_done() {
  dave init >/dev/null
  dave park "first idea" >/dev/null
  dave park "second idea" >/dev/null
  dave park "third idea" >/dev/null
  local out; out="$(dave parked 'done' 2)"
  assert_contains "retire reports the item" "$out" "retired: second idea"
  assert_eq "two open items remain" "2" "$(dave parked | grep -c '^- \[ \]')"
  local parking="$DAVE_HOME/.local/render/parking-lot.md"
  grep -q '^- \[x\] second idea.*_(retired '"$(date +%F)"')_' "$parking" \
    && ok "the retired line is marked with its date" \
    || no "the retired line is marked with its date" "$(grep 'second' "$parking")"
  assert_exit "an out-of-range index is refused" 1 dave parked 'done' 9
  assert_exit "a non-numeric index is refused" 1 dave parked 'done' abc
  assert_eq "the open items were not renumbered" "1" \
    "$(grep -c '^- \[ \] third' "$parking")"
  assert_eq "rendered files carry the generated marker" "1" \
    "$(head -1 "$parking" | grep -c '^<!-- generated by dave.sh')"
}

test_intake() {
  dave init >/dev/null
  local path; path="$(printf 'Doing\n- SSO rollout\n' | dave intake "platform board")"
  [ -f "$path" ] && ok "intake archives the raw board" || no "intake archives the raw board" "no file at $path"
  assert_contains "intake keeps the text verbatim" "$(cat "$path")" "SSO rollout"
  assert_contains "intake stamps last_intake" "$(jq -r .last_intake "$DAVE_HOME/.local/views/state.json")" "platform board"
}

test_mission() {
  dave init >/dev/null
  local path; path="$(dave mission new "SSO rollout")"
  assert_contains "mission new returns a slugged path" "$path" "sso-rollout.md"
  assert_contains "mission show renders the template" "$(dave mission show sso-rollout)" "# Mission: sso-rollout"
  assert_contains "mission list names it" "$(dave mission list)" "sso-rollout"
  assert_exit "mission new refuses a duplicate" 1 dave mission new "SSO rollout"
}

test_brief() {
  dave init >/dev/null
  dave focus set RM-4471 "retry" >/dev/null
  dave log "something happened" >/dev/null
  local out; out="$(dave brief)"
  assert_contains "brief says when there is no project" "$out" "not in a registered project"
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" --goal "crawl politely" >/dev/null
  dave project link webcrawler RM-4471 >/dev/null
  local inproj; inproj="$(cd "$root/webcrawler" && dave brief)"
  assert_contains "brief resolves the project from cwd" "$inproj" "webcrawler  ·  active"
  assert_contains "brief shows the project goal" "$inproj" "crawl politely"
  assert_contains "brief shows linked refs" "$inproj" "refs: RM-4471"

  for section in "=== IDENTITY ===" "=== PROJECT" "=== FOCUS ===" "=== PRIORITIES ===" "=== TODAY" "=== PARKED (open) ===" "=== LAST INTAKE ==="; do
    assert_contains "brief has $section" "$out" "$section"
  done
  assert_contains "brief reports elapsed time" "$out" "elapsed:"
  assert_contains "brief stamps last_brief" "$(jq -r .last_brief "$DAVE_HOME/.local/views/state.json")" "-"
}

# ------------------------------------------------------------------ projects

test_project() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler/src/deep"
  assert_contains "project list when empty" "$(dave project list)" "(no projects registered"

  local out; out="$(dave project add "$root/webcrawler" --goal "crawl politely" --cadence daily)"
  assert_contains "project add confirms" "$out" "registered: webcrawler"
  assert_eq "project add stores a canonical path" "$root/webcrawler" \
    "$(jq -r '.projects.paths.webcrawler' "$DAVE_HOME/.local/config.json")"
  assert_eq "project add defaults status" "active" \
    "$(jq -r .status "$DAVE_HOME/projects/webcrawler/project.json")"
  assert_eq "project add takes cadence" "daily" \
    "$(jq -r .cadence "$DAVE_HOME/projects/webcrawler/project.json")"

  assert_contains "project list shows it" "$(dave project list)" "webcrawler"
  assert_exit "project add refuses a duplicate slug" 1 dave project add "$root/webcrawler"
  mkdir -p "$root/other"
  assert_exit "project add refuses a duplicate path" 1 \
    dave project add "$root/webcrawler" --slug second
  assert_exit "project add refuses a non-directory" 1 dave project add "$root/nope"
  assert_exit "project add validates cadence" 1 dave project add "$root/other" --cadence hourly
  assert_exit "project add validates status" 1 dave project add "$root/other" --status busy

  dave project status webcrawler paused >/dev/null
  assert_eq "project status changes it" "paused" \
    "$(jq -r .status "$DAVE_HOME/projects/webcrawler/project.json")"
  assert_exit "project status validates" 1 dave project status webcrawler elsewhere
  assert_contains "project list filters by status" "$(dave project list --status paused)" "webcrawler"
  assert_eq "project list --status excludes" "0" \
    "$(dave project list --status active --json | jq length)"

  dave project link webcrawler RM-4471 >/dev/null
  dave project link webcrawler RM-4471 >/dev/null   # idempotent
  assert_eq "project link is a set" "1" \
    "$(jq -r '.webcrawler.refs | length' "$DAVE_HOME/.local/views/projects.json")"
  assert_eq "project of finds the owner" "webcrawler" "$(dave project of RM-4471)"
  assert_eq "project of an unlinked ref is silent" "" "$(dave project of RM-9999)"

  dave project add "$root/other" >/dev/null
  assert_exit "project link refuses a ref owned elsewhere" 1 dave project link other RM-4471
  dave project unlink webcrawler RM-4471 >/dev/null
  assert_eq "project unlink removes it" "0" \
    "$(jq -r '.webcrawler.refs | length' "$DAVE_HOME/.local/views/projects.json")"

  assert_exit "project show on an unknown slug fails" 1 dave project show nosuch

  # A directory name that slugifies must still find its project — the user should
  # not have to remember what registration did to the name.
  mkdir -p "$root/dnd_5e_api"
  dave project add "$root/dnd_5e_api" >/dev/null
  assert_eq "add slugifies the directory name" "dnd-5e-api" \
    "$(jq -r .slug "$DAVE_HOME/projects/dnd-5e-api/project.json")"
  assert_exit "status accepts the raw directory name" 0 dave project status dnd_5e_api paused
  assert_eq "the raw name reached the right project" "paused" \
    "$(jq -r .status "$DAVE_HOME/projects/dnd-5e-api/project.json")"
  assert_exit "show accepts the raw directory name" 0 dave project show dnd_5e_api
  assert_exit "link accepts the raw directory name" 0 dave project link dnd_5e_api RM-77
  local show; show="$(dave project show webcrawler)"
  assert_contains "project show has the header" "$show" "=== PROJECT ==="
  assert_contains "project show reports goal" "$show" "crawl politely"
  assert_contains "project show handles a non-repo" "$show" "(not a git repository)"

  # A linked ref that the priority list no longer mentions is surfaced, not hidden.
  dave project link webcrawler RM-4471 >/dev/null
  assert_contains "project show flags a ref off the list" "$(dave project show webcrawler)" \
    "(not in priorities.md)"
  printf '\n1. **RM-4471** — retry\n' >> "$DAVE_HOME/priorities.md"
  case "$(dave project show webcrawler)" in
    *"(not in priorities.md)"*) no "project show clears the flag once listed" "still flagged" ;;
    *) ok "project show clears the flag once listed" ;;
  esac

  local before; before="$(jq -r '.webcrawler.last_touched' "$DAVE_HOME/.local/views/projects.json")"
  sleep 1
  dave project touch webcrawler >/dev/null
  case "$(jq -r '.webcrawler.last_touched' "$DAVE_HOME/.local/views/projects.json")" in
    "$before") no "project touch stamps the time" "unchanged" ;;
    *) ok "project touch stamps the time" ;;
  esac
}

test_project_resolve() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler/src/deep/dir"
  dave project add "$root/webcrawler" >/dev/null

  assert_eq "resolve at the project root" "webcrawler" "$(dave project resolve "$root/webcrawler")"
  assert_eq "resolve from a nested path" "webcrawler" \
    "$(dave project resolve "$root/webcrawler/src/deep/dir")"
  assert_eq "resolve outside any project is silent" "" "$(dave project resolve "$root")"
  assert_exit "resolve outside any project still exits 0" 0 dave project resolve /tmp
  assert_eq "resolve on a missing path is silent" "" "$(dave project resolve "$root/gone")"

  # cwd, not just an argument — this is how the hook and brief call it.
  assert_eq "resolve defaults to cwd" "webcrawler" \
    "$(cd "$root/webcrawler/src" && dave project resolve)"
  assert_eq "project show defaults to cwd" "webcrawler" \
    "$(cd "$root/webcrawler/src" && dave project show | sed -n 's/^slug: //p')"
}

# An un-migrated tree must degrade to a note, never to a broken hook.
test_hook_schema_note() {
  dave init >/dev/null
  jq 'del(.schema_version)' "$DAVE_HOME/.local/views/state.json" > "$DAVE_HOME/s" && mv "$DAVE_HOME/s" "$DAVE_HOME/.local/views/state.json"
  local ctx
  ctx="$(bash "$TEST_DIR/../../../../hooks/session-start.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
  assert_contains "hook notes a stale schema" "$ctx" "run \`dave.sh migrate\`"
  dave migrate >/dev/null
  ctx="$(bash "$TEST_DIR/../../../../hooks/session-start.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')"
  case "$ctx" in
    *"dave.sh migrate"*) no "hook drops the note after migrating" "note still present" ;;
    *) ok "hook drops the note after migrating" ;;
  esac
}

test_project_candidates() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/a" "$root/b"
  dave project add "$root/a" >/dev/null
  json_edit_config() { local t; t="$(mktemp)"; jq "$1" "$DAVE_HOME/config.json" > "$t" && mv "$t" "$DAVE_HOME/config.json"; }
  json_edit_config ".projects.root = \"$root\""
  case "$(dave project list)" in
    *unregistered*) no "candidates stay off unless asked" "listed with autodiscover false" ;;
    *) ok "candidates stay off unless asked" ;;
  esac
  json_edit_config '.projects.autodiscover = true'
  local out; out="$(dave project list)"
  assert_contains "autodiscover names a candidate" "$out" "$root/b"
  case "$out" in
    *"unregistered under"*"/a"*) no "autodiscover skips registered projects" "listed /a" ;;
    *) ok "autodiscover skips registered projects" ;;
  esac
}

# --------------------------------------------------------------- focus stack

test_focus_stack() {
  dave init >/dev/null
  local out; out="$(dave focus push RM-1 "parent")"
  assert_contains "push with nothing focused says so" "$out" "nothing was focused to stack"
  out="$(dave focus push RM-2 "detour")"
  assert_contains "push stacks the parent" "$out" "stacked over RM-1"
  assert_eq "the detour is current" "RM-2" "$(jq -r .focus.ref "$DAVE_HOME/.local/views/state.json")"
  assert_eq "the parent is stacked" "1" "$(jq -r '.focus_stack | length' "$DAVE_HOME/.local/views/state.json")"
  assert_contains "show lists the stack" "$(dave focus show)" "RM-1 — parent"

  out="$(dave focus pop)"
  assert_contains "pop returns to the parent" "$out" "RM-1 — parent"
  assert_eq "the stack is empty again" "0" "$(jq -r '.focus_stack | length' "$DAVE_HOME/.local/views/state.json")"
  # The parent's clock restarts: its earlier time is already banked, and the
  # detour must not be billed to it.
  local started; started="$(jq -r .focus.started "$DAVE_HOME/.local/views/state.json")"
  assert_eq "pop restarts the parent's clock" "$(date -d "$started" +%F)" "$(date +%F)"

  out="$(dave focus pop)"
  assert_contains "pop with an empty stack clears" "$out" "nothing stacked to return to"
  assert_eq "focus is cleared" "null" "$(jq -r '.focus // "null"' "$DAVE_HOME/.local/views/state.json")"

  dave focus push RM-9 >/dev/null
  dave focus clear >/dev/null
  assert_eq "clear empties the stack too" "0" "$(jq -r '.focus_stack | length' "$DAVE_HOME/.local/views/state.json")"
}

test_time_ledger() {
  dave init >/dev/null
  assert_contains "time with nothing recorded" "$(dave time)" "(nothing recorded)"

  # Backdate a focus so a closed segment has real minutes in it. The view is
  # derived, so the backdate has to land on the journal event itself — the next
  # command's rebuild then folds it into state.json.
  dave focus set RM-4471 "retry" >/dev/null
  local jf; jf="$(dev_journal)"
  jq -c --arg t "$(date -d '-90 min' -Iseconds)" \
    'if .type == "focus.set" then .data.started = $t else . end' "$jf" > "$jf.tmp" \
    && mv "$jf.tmp" "$jf"
  dave log "found the double-fire" >/dev/null
  dave focus set RM-9999 "something else" >/dev/null

  assert_eq "a segment was banked" "1" "$(jsonl_count "$DAVE_HOME/.local/views/sessions.jsonl")"
  local rec; rec="$(head -1 "$DAVE_HOME/.local/views/sessions.jsonl")"
  assert_eq "the segment names the ref" "RM-4471" "$(printf '%s' "$rec" | jq -r .ref)"
  assert_eq "the segment has ~90 minutes" "90" "$(printf '%s' "$rec" | jq -r .minutes)"
  assert_eq "the segment counted log activity" "1" "$(printf '%s' "$rec" | jq -r .log_lines)"

  local out; out="$(dave time RM-4471)"
  assert_contains "time reports the total" "$out" "1h30m across 1 segment"
  assert_contains "time reports the open segment" "$(dave time)" "open now:"
  assert_eq "time --json is machine readable" "RM-4471" "$(dave time --json | jq -r '.segments[0].ref')"
  assert_eq "time filters by ref" "0" "$(dave time RM-0 --json | jq '.segments | length')"

  # Time with no log activity behind it is real elapsed time with no evidence,
  # and must be reported separately rather than folded into the total.
  # The log is cleared first: backdating a segment would otherwise pull the
  # earlier test's log line inside this window, which real segments never do.
  # The rendered file is generated, so it is the log.add event that goes.
  local jf; jf="$(dev_journal)"
  jq -c 'select(.type != "log.add")' "$jf" > "$jf.tmp" && mv "$jf.tmp" "$jf"
  dave focus set RM-5 "unverified work" >/dev/null
  jq -c --arg t "$(date -d '-40 min' -Iseconds)" \
    'if .type == "focus.set" then .data.started = $t else . end' "$jf" > "$jf.tmp" \
    && mv "$jf.tmp" "$jf"
  dave focus clear >/dev/null
  assert_contains "unverified time is split out" "$(dave time RM-5)" "40m unverified"
}

test_time_open_cap() {
  dave init >/dev/null
  dave focus set RM-1 "held forever" >/dev/null
  local jf; jf="$(dev_journal)"
  jq -c --arg t "$(date -d '-16 hour' -Iseconds)" \
    'if .type == "focus.set" then .data.started = $t else . end' "$jf" > "$jf.tmp" \
    && mv "$jf.tmp" "$jf"
  local out; out="$(dave time)"
  assert_contains "an overnight focus is capped, not asserted" "$out" "4h0m"
  assert_contains "and the cap is disclosed" "$out" "capped"
  case "$out" in *16h*) no "the raw 16 hours never appears" "found 16h" ;; *) ok "the raw 16 hours never appears" ;; esac
}

test_drift_events() {
  dave init >/dev/null
  dave focus set RM-1 "work" >/dev/null
  assert_contains "drift still reports by default" "$(dave drift)" "on focus"
  dave drift record third-repo parked >/dev/null
  dave drift record third-repo continued >/dev/null
  dave drift record unlisted promoted >/dev/null
  assert_eq "events are recorded" "3" "$(jq -r '.drift_events | length' "$DAVE_HOME/.local/views/state.json")"
  assert_eq "the focus ref is captured" "RM-1" "$(jq -r '.drift_events[0].ref' "$DAVE_HOME/.local/views/state.json")"
  local out; out="$(dave drift events)"
  assert_contains "events summarise by kind" "$out" "third-repo: 2"
  assert_contains "events name the outcomes" "$out" "1 parked"
  assert_exit "an invalid kind is refused" 1 dave drift record nonsense parked
  assert_exit "an invalid outcome is refused" 1 dave drift record unlisted maybe
  assert_eq "events --json" "3" "$(dave drift events --json | jq length)"
}

# ------------------------------------------------------------------ tracking

test_next() {
  dave init >/dev/null
  assert_contains "next with nothing recorded" "$(dave next show)" "(no next actions recorded)"
  dave next set RM-4471 "instrument retry middleware ~line 88" >/dev/null
  assert_contains "next show returns it" "$(dave next show)" "instrument retry middleware"
  assert_contains "next show filters by ref" "$(dave next show RM-4471)" "line 88"
  assert_contains "next show on an unknown ref" "$(dave next show RM-0)" "(no next actions recorded)"
  dave next set RM-4471 "revised" >/dev/null
  assert_eq "next set overwrites" "revised" "$(jq -r '."RM-4471".text' "$DAVE_HOME/.local/views/notes.json")"
  dave next clear RM-4471 >/dev/null
  assert_contains "next clear removes it" "$(dave next show)" "(no next actions recorded)"
}

test_promise() {
  dave init >/dev/null
  assert_contains "promise list when empty" "$(dave promise list)" "(no commitments recorded)"
  local out; out="$(dave promise add "Maya" "SSO demo build" "$(date -d '+2 day' +%F)" --ref RM-4471)"
  assert_contains "promise add returns an id" "$out" "c1: promised Maya"
  dave promise add "Sam" "the exporter" "$(date -d '+30 day' +%F)" >/dev/null
  assert_eq "ids increment" "c2" "$(jq -r '.[1].id' "$DAVE_HOME/.local/views/commitments.json")"
  assert_exit "an unreadable date is refused" 1 dave promise add "X" "y" "not-a-date"

  # A date a human would actually say.
  dave promise add "Ana" "the review" "friday" >/dev/null
  assert_eq "a spoken date is normalized" "10" \
    "$(jq -r '.[2].due | length' "$DAVE_HOME/.local/views/commitments.json")"

  assert_contains "list shows all" "$(dave promise list)" "Maya — SSO demo build"
  local soon; soon="$(dave promise list --open --due-within 3)"
  assert_contains "due-within finds the near one" "$soon" "Maya"
  case "$soon" in *Sam*) no "due-within excludes the far one" "Sam listed" ;; *) ok "due-within excludes the far one" ;; esac

  dave promise move c1 "$(date -d '+9 day' +%F)" >/dev/null
  assert_eq "move keeps the history" "1" "$(jq -r '.[0].moved | length' "$DAVE_HOME/.local/views/commitments.json")"
  assert_eq "move keeps it open" "open" "$(jq -r '.[0].status' "$DAVE_HOME/.local/views/commitments.json")"
  dave promise keep c1 >/dev/null
  assert_eq "keep closes it" "kept" "$(jq -r '.[0].status' "$DAVE_HOME/.local/views/commitments.json")"
  dave promise miss c2 >/dev/null
  assert_eq "miss closes it" "missed" "$(jq -r '.[1].status' "$DAVE_HOME/.local/views/commitments.json")"
  assert_exit "an unknown id is refused" 1 dave promise keep c99

  # Overdue has to be visible without arithmetic on the reader's part.
  dave promise add "Lee" "the thing" "$(date -d '-2 day' +%F)" >/dev/null
  assert_contains "overdue is flagged" "$(dave promise list --open)" "OVERDUE"
}

test_scan() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/repo" "$root/plain"
  git -C "$root/repo" init -q
  git -C "$root/repo" config user.email t@t; git -C "$root/repo" config user.name t
  echo a > "$root/repo/f.txt"; git -C "$root/repo" add -A; git -C "$root/repo" commit -qm "feat: one"
  dave project add "$root/repo" >/dev/null
  dave project add "$root/plain" >/dev/null

  local out; out="$(dave scan)"
  assert_contains "scan reports the branch" "$out" "repo"
  assert_contains "scan reports a clean tree" "$out" "clean"
  assert_contains "scan tolerates a non-repo" "$out" "(not a repo)"
  assert_contains "scan dates the last commit" "$out" "committed today"
  [ -f "$DAVE_HOME/.local/scan-cache.json" ] && ok "scan writes a cache" || no "scan writes a cache" "missing"

  echo b >> "$root/repo/f.txt"
  case "$(dave scan)" in
    *clean*) ok "a cached scan is served from cache" ;;
    *) no "a cached scan is served from cache" "re-probed within the TTL" ;;
  esac
  assert_contains "--fresh bypasses the cache" "$(dave scan --fresh)" "1 dirty"
  assert_eq "scan filters to one project" "1" "$(dave scan repo --json | jq 'keys | length')"

  # A registered path that vanishes must not take the scan down with it.
  rm -rf "$root/plain"
  assert_contains "a missing path is reported" "$(dave scan --fresh)" "PATH GONE"

  dave project status repo archived >/dev/null
  assert_eq "archived projects are skipped" "0" "$(dave scan --fresh --json | jq 'keys | map(select(. == "repo")) | length')"
  assert_eq "--all includes them" "1" "$(dave scan --fresh --all --json | jq 'keys | map(select(. == "repo")) | length')"
}

test_brief_phase_b() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" >/dev/null
  dave project link webcrawler RM-4471 >/dev/null
  dave focus set RM-4471 "retry" >/dev/null
  dave next set RM-4471 "instrument the middleware" >/dev/null
  dave promise add "Maya" "SSO demo" "$(date -d '+1 day' +%F)" --ref RM-4471 >/dev/null

  local out; out="$(cd "$root/webcrawler" && dave brief)"
  assert_contains "brief shows where you left off" "$out" "next: instrument the middleware"
  assert_contains "brief surfaces a promise coming due" "$out" "PROMISED, DUE SOON"
  assert_contains "brief names who it was made to" "$out" "Maya"
  # The focused ref's note is on the focus line already; printing it twice is noise.
  assert_eq "the focused ref is not repeated below" "0" \
    "$(printf '%s' "$out" | grep -c '^RM-4471: instrument' || true)"
  dave next set RM-77 "a different ref" >/dev/null
  dave project link webcrawler RM-77 >/dev/null
  assert_contains "other refs still appear" "$(cd "$root/webcrawler" && dave brief)" "RM-77: a different ref"

  # Both sections vanish when empty rather than printing "(none)".
  dave next clear RM-4471 >/dev/null
  dave next clear RM-77 >/dev/null
  dave promise keep c1 >/dev/null
  out="$(cd "$root/webcrawler" && dave brief)"
  case "$out" in *"PROMISED, DUE SOON"*) no "the promise section vanishes when empty" "still shown" ;; *) ok "the promise section vanishes when empty" ;; esac
  case "$out" in *"WHERE YOU LEFT OFF"*) no "the notes section vanishes when empty" "still shown" ;; *) ok "the notes section vanishes when empty" ;; esac
}

# ------------------------------------------------------------------ missions

test_mission_ledger() {
  dave init >/dev/null
  dave mission new "SSO rollout" --ref RM-4471 >/dev/null
  assert_eq "mission new registers metadata" "RM-4471" \
    "$(jq -r '."sso-rollout".ref' "$DAVE_HOME/.local/views/missions.json")"
  assert_eq "a new mission is open" "open" \
    "$(jq -r '."sso-rollout".status' "$DAVE_HOME/.local/views/missions.json")"

  local id; id="$(dave mission assign sso-rollout scout "find out why the retry double-fires")"
  assert_eq "assign returns a readable id" "sso-rollout#1" "$id"
  local id2; id2="$(dave mission assign sso-rollout ideator "three approaches" --model opus)"
  assert_eq "ids increment per mission" "sso-rollout#2" "$id2"

  assert_contains "status lists what is outstanding" "$(dave mission status)" "sso-rollout#1"
  assert_contains "status names the agent" "$(dave mission status sso-rollout)" "scout"

  dave mission record "$id" --verdict partial --summary "cache claim unverified" >/dev/null
  local st; st="$(dave mission status sso-rollout)"
  case "$st" in *"sso-rollout#1"*) no "a recorded charge leaves the outstanding list" "still listed" ;;
                *) ok "a recorded charge leaves the outstanding list" ;; esac
  assert_contains "the other charge is still open" "$st" "sso-rollout#2"

  # The table is rendered from the ledger, not maintained by hand.
  local show; show="$(dave mission show sso-rollout)"
  assert_contains "show renders a table header" "$show" "| Id | Agent | Charge | Returned | Verdict |"
  assert_contains "show renders the verdict" "$show" "partial — cache claim unverified"
  assert_contains "show marks an open charge" "$show" "**open**"
  assert_contains "show notes the model when given" "$show" "ideator (opus)"
  assert_eq "the template table is not duplicated" "1" \
    "$(printf '%s' "$show" | grep -c '^## Assignments')"

  assert_exit "an orphan verdict is refused" 1 dave mission record "sso-rollout#99" --verdict trust
  assert_exit "an invalid verdict is refused" 1 dave mission record "$id2" --verdict lovely
  assert_exit "a verdict is required" 1 dave mission record "$id2"

  # The active mission is the default target, so a long session stops repeating itself.
  dave mission open sso-rollout >/dev/null
  assert_eq "open sets the active mission" "sso-rollout" "$(jq -r .active_mission "$DAVE_HOME/.local/views/state.json")"
  local id3; id3="$(dave mission assign critic "attack the plan")"
  assert_eq "assign defaults to the active mission" "sso-rollout#3" "$id3"

  local out; out="$(dave mission close sso-rollout --outcome "shipped")"
  assert_contains "close flags unrecorded charges" "$out" "closed without a recorded verdict"
  assert_eq "close clears the active mission" "null" "$(jq -r '.active_mission // "null"' "$DAVE_HOME/.local/views/state.json")"
  assert_eq "close records the outcome" "shipped" "$(jq -r '."sso-rollout".outcome' "$DAVE_HOME/.local/views/missions.json")"
  assert_eq "list --open excludes it" "0" "$(dave mission list --open --json | jq length)"
}

test_mission_legacy() {
  dave init >/dev/null
  # A brief written before missions.json existed must not read as broken.
  sed -e 's|{{SLUG}}|old-thing|g' -e "s|{{DATE}}|$(date +%F)|g" \
    "$TEST_DIR/../../templates/mission-brief-template.md" > "$DAVE_HOME/missions/old-thing.md"
  assert_contains "list finds an unregistered brief" "$(dave mission list)" "old-thing"
  local id; id="$(dave mission assign old-thing scout "have a look")"
  assert_eq "assigning backfills its metadata" "sso" "$(jq -r 'if ."old-thing" then "sso" else "missing" end' "$DAVE_HOME/.local/views/missions.json")"
  assert_eq "and the id is well formed" "old-thing#1" "$id"
}

test_mission_pack() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" >/dev/null
  dave mission new "retry bug" --ref RM-4471 --project webcrawler >/dev/null
  local path="$DAVE_HOME/missions/retry-bug.md"

  # An unfilled brief must say so rather than emitting a confident empty charge.
  local pack; pack="$(dave mission pack retry-bug --agent scout)"
  assert_contains "pack flags an empty brief" "$pack" "Incomplete brief"
  assert_contains "pack names the empty sections" "$pack" "objective"

  cat > "$path" <<'BRIEF'
# Mission: retry-bug

## Priority ref

RM-4471

## Objective

The retry middleware fires once per request.

## Definition of done

- [x] a failing test reproduces the double-fire

## Constraints

Do not touch the billing path.

## Context the agent won't have

The retry wrapper lives in src/mw/retry.py and was rewritten in June.

## Assignments

| Agent | Charge | Returned | Verdict |
|---|---|---|---|

## Open questions

## Outcome
BRIEF

  pack="$(dave mission pack retry-bug --agent scout)"
  case "$pack" in *"Incomplete brief"*) no "a filled brief packs cleanly" "still flagged" ;;
                  *) ok "a filled brief packs cleanly" ;; esac
  assert_contains "pack carries the objective" "$pack" "fires once per request"
  assert_contains "pack carries the done conditions" "$pack" "failing test reproduces"
  assert_contains "pack carries undiscoverable context" "$pack" "src/mw/retry.py"
  assert_contains "pack names the ref it serves" "$pack" "Serves: RM-4471"
  assert_contains "pack ends with the agent's return format" "$pack" "## Return format"
  assert_contains "pack quotes the real return contract" "$pack" "## Answer"
  case "$pack" in *"<!--"*) no "pack strips the template's prompts" "HTML comment leaked" ;;
                  *) ok "pack strips the template's prompts" ;; esac

  # A charge with no return contract is not a charge.
  assert_exit "pack refuses an unknown agent" 1 dave mission pack retry-bug --agent nosuch
  assert_exit "pack requires an agent" 1 dave mission pack retry-bug

  # Prior charges travel with the brief so a rerun knows what went wrong.
  local id; id="$(dave mission assign retry-bug scout "first look")"
  dave mission record "$id" --verdict rerun --summary "answered an easier question" >/dev/null
  pack="$(dave mission pack retry-bug --agent scout)"
  assert_contains "pack lists prior charges" "$pack" "Already asked on this mission"
  assert_contains "pack carries the prior verdict" "$pack" "rerun (answered an easier question)"

  # And the project's dossier is offered rather than re-derived.
  echo "# webcrawler map" | dave dossier set webcrawler >/dev/null
  pack="$(dave mission pack retry-bug --agent scout)"
  assert_contains "pack points at the cached dossier" "$pack" "dossier.md"

  # An untouched brief: every section empty, and the template's own unticked
  # checkbox must read as a skeleton rather than as a filled definition of done.
  dave mission new "skeleton" >/dev/null
  local bare; bare="$(dave mission pack skeleton --agent scout)"
  assert_contains "an empty section says so" "$bare" "_(none stated)_"
  assert_contains "a skeleton done-list still counts as empty" "$bare" "definition-of-done"
}

test_dossier() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/repo"
  git -C "$root/repo" init -q
  git -C "$root/repo" config user.email t@t; git -C "$root/repo" config user.name t
  echo a > "$root/repo/f"; git -C "$root/repo" add -A; git -C "$root/repo" commit -qm one
  dave project add "$root/repo" >/dev/null

  assert_contains "no dossier yet" "$(dave dossier get repo)" "(no dossier for repo"
  printf '# Map

It is a crawler.
' | dave dossier set repo >/dev/null
  assert_contains "dossier get returns it" "$(dave dossier get repo)" "It is a crawler."
  assert_contains "a fresh dossier is current" "$(dave dossier get repo)" "has not moved since"
  assert_eq "the dossier is stamped with a commit" "40" \
    "$(jq -r '.dossier.head | length' "$DAVE_HOME/projects/repo/project.json")"

  echo b > "$root/repo/f2"; git -C "$root/repo" add -A; git -C "$root/repo" commit -qm two
  assert_contains "one commit on is still current" "$(dave dossier get repo)" "1 commit(s) since"

  # Past the threshold it must say so plainly rather than being quietly trusted.
  jq '.projects.dossier_stale_commits = 1' "$DAVE_HOME/config.json" > "$DAVE_HOME/c" \
    && mv "$DAVE_HOME/c" "$DAVE_HOME/config.json"
  assert_contains "past the threshold it is stale" "$(dave dossier get repo)" "STALE"

  # A rewritten history must not produce a confident wrong answer.
  jq '.dossier.head = "0000000000000000000000000000000000000000"' \
    "$DAVE_HOME/projects/repo/project.json" > "$DAVE_HOME/p" \
    && mv "$DAVE_HOME/p" "$DAVE_HOME/projects/repo/project.json"
  assert_contains "an unknown commit is admitted" "$(dave dossier get repo)" "no longer in this repository"
}

# -------------------------------------------------------------------- review

# Builds a repo whose only commit is dated <age> days ago.
mkrepo() {
  local d="$1" when="$2"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  echo x > "$d/f"; git -C "$d" add -A
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" git -C "$d" commit -qm "feat: seed"
}

test_review_empty() {
  dave init >/dev/null
  local out; out="$(dave review)"
  assert_exit "review on a fresh tree exits 0" 0 dave review
  case "$out" in
    *Slipping*|*Rotting*|*Owed*) no "a fresh tree produces no alarms" "found a findings section" ;;
    *) ok "a fresh tree produces no alarms" ;;
  esac
  assert_contains "review always states the closure gap" "$out" "not recorded anywhere"
  assert_contains "review names the window" "$out" "Since "
  assert_eq "review --json is consumable" "7" "$(dave review --json | jq -r '.window.days')"
}

test_review_cadence() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"
  mkrepo "$root/daily-one"  "$(date -d '-1 day' -Iseconds)"
  mkrepo "$root/weekly-one" "$(date -d '-24 day' -Iseconds)"
  mkrepo "$root/maint-one"  "$(date -d '-60 day' -Iseconds)"
  mkrepo "$root/dormant-one" "$(date -d '-400 day' -Iseconds)"
  dave project add "$root/daily-one"   --cadence daily >/dev/null
  dave project add "$root/weekly-one"  --cadence weekly >/dev/null
  dave project add "$root/maint-one"   --cadence monthly >/dev/null
  dave project status maint-one maintenance >/dev/null
  dave project add "$root/dormant-one" --cadence dormant >/dev/null

  local j; j="$(dave review --json)"
  assert_eq "an active weekly project 24d quiet is slipping" "true" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "weekly-one") | .slipping')"
  assert_eq "a daily project committed yesterday is fine" "false" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "daily-one") | .slipping')"
  # The two that keep the sweep honest.
  assert_eq "a maintenance project quiet for 60d is not a finding" "false" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "maint-one") | .slipping')"
  assert_eq "a dormant project never slips" "false" \
    "$(printf '%s' "$j" | jq -r '.projects[] | select(.slug == "dormant-one") | .slipping')"

  local out; out="$(dave review)"
  assert_contains "slipping is reported with its number" "$out" "weekly-one — weekly cadence, nothing for 2"
  assert_contains "quiet and fine is a real section" "$out" "Quiet and fine:"
  assert_contains "the maintenance project is listed as fine" "$out" "maint-one (maintenance)"

  # Registration is not activity: a project registered today whose repo has been
  # silent for a month must still read as silent. last_touched lives in the
  # derived view now, not the shared document.
  assert_eq "registering does not reset the clock" "null" \
    "$(jq -r '."weekly-one".last_touched // "null"' "$DAVE_HOME/.local/views/projects.json")"
}

test_review_findings() {
  dave init >/dev/null
  # An overdue promise outranks everything: it is the one thing here the user
  # cannot see for themselves.
  dave promise add "Maya" "SSO demo" "$(date -d '-2 day' +%F)" >/dev/null
  dave promise add "Sam" "exporter" "$(date -d '+2 day' +%F)" >/dev/null
  local out; out="$(dave review)"
  assert_contains "an overdue promise is slipping" "$out" "Maya — SSO demo"
  assert_contains "and it is marked overdue" "$out" "OVERDUE"
  assert_contains "a future promise is only coming due" "$out" "Coming due:"
  case "$(printf '%s' "$out" | sed -n '/Slipping:/,/^$/p')" in
    *Sam*) no "a future promise is not slipping" "listed under Slipping" ;;
    *) ok "a future promise is not slipping" ;;
  esac

  # Parked items rot. They are journal events now — the rendered file is
  # regenerated on every command, so fixtures go into the journal.
  local jf; jf="$(dev_journal)"
  local dev; dev="$(jq -r .id "$DAVE_HOME/.local/device.json")"
  jq -nc --arg dev "$dev" --arg ts "$(date -d '-30 day' -Iseconds)" \
    '{ts:$ts, seq:900, dev:$dev, sid:"t", type:"park.add",
      data:{id:($ts+"-x-1"), text:"rewrite the exporter", ref:"RM-1", ts:$ts}}' \
    >> "$jf"
  jq -nc --arg dev "$dev" --arg ts "$(date -d '+0 min' -Iseconds)" \
    '{ts:$ts, seq:901, dev:$dev, sid:"t", type:"park.add",
      data:{id:($ts+"-x-2"), text:"something recent", ref:"", ts:$ts}}' \
    >> "$jf"
  dave rebuild >/dev/null
  assert_eq "only the old parked item counts" "1" "$(dave review --json | jq '.parked | length')"
  assert_contains "rotting names the oldest" "$(dave review)" "rewrite the exporter"

  # An AD- item that outlived its grace period should have become a ticket.
  printf '\n1. **AD-cache-warmup** — warm it\n' >> "$DAVE_HOME/priorities.md"
  jq -nc --arg dev "$dev" --arg ts "$(date -d '-11 day' -Iseconds)" \
    '{ts:$ts, seq:902, dev:$dev, sid:"t", type:"log.add",
      data:{ts:($ts[0:10]+"T09:00:00"+$ts[19:]), ref:"AD-cache-warmup", text:"started"}}' \
    >> "$jf"
  assert_contains "an aged ad-hoc item is flagged" "$(dave review)" "AD-cache-warmup first logged 11d ago"

  # Blocked items stay prose and get handed over, not judged.
  printf '\n## Blocked\n\n- **RM-88** — waiting on Ana for the schema\n' >> "$DAVE_HOME/priorities.md"
  out="$(dave review)"
  assert_contains "blocked items are handed to the reader" "$out" "which of these has nobody chased?"
  assert_contains "and quoted verbatim" "$out" "waiting on Ana"
}

test_review_owed() {
  dave init >/dev/null
  dave mission new "sso rollout" >/dev/null
  dave mission assign sso-rollout scout "have a look" >/dev/null
  # A charge sent moments ago is not a finding.
  case "$(dave review)" in
    *Owed*) no "a fresh charge is not owed" "listed under Owed" ;;
    *) ok "a fresh charge is not owed" ;;
  esac
  # One sent last week and never graded is exactly the thing to surface.
  local old_ts; old_ts="$(date -d '-5 day' -Iseconds)"
  jq -c --arg ts "$old_ts" '.ts = $ts' "$DAVE_HOME/.local/views/assignments.jsonl" > "$DAVE_HOME/a.tmp" \
    && mv "$DAVE_HOME/a.tmp" "$DAVE_HOME/.local/views/assignments.jsonl"
  local out; out="$(dave review)"
  assert_contains "an aged open charge is owed" "$out" "sso-rollout — 1 charge(s) outstanding"
  assert_contains "and it says how old" "$out" "oldest sent 5d ago"

  # Grading it closes the loop.
  dave mission record "sso-rollout#1" --verdict trust >/dev/null
  case "$(dave review)" in
    *"charge(s) outstanding"*) no "a graded charge stops being owed" "still listed" ;;
    *) ok "a graded charge stops being owed" ;;
  esac
}

test_review_drift() {
  dave init >/dev/null
  local root="$DAVE_HOME/work"; mkdir -p "$root/webcrawler"
  dave project add "$root/webcrawler" >/dev/null
  dave drift record third-repo continued --project webcrawler >/dev/null
  dave drift record third-repo parked --project webcrawler >/dev/null
  dave drift record unlisted promoted --project webcrawler >/dev/null
  local out; out="$(dave review)"
  assert_contains "drift is summarised by kind" "$out" "third-repo ×2"
  assert_contains "and points at where it went" "$out" "into webcrawler"
  # Old events fall outside the window rather than accumulating forever. Aged
  # explicitly rather than by asking for a zero-day window: the boundary is
  # inclusive and timestamps are second-resolution, so a zero-day window is a
  # race with the clock rather than a test.
  dave drift record no-focus parked >/dev/null
  jq --arg old "$(date -d '-30 day' -Iseconds)" \
     '.drift_events[3].at = $old' "$DAVE_HOME/.local/views/state.json" > "$DAVE_HOME/s.tmp" \
    && mv "$DAVE_HOME/s.tmp" "$DAVE_HOME/.local/views/state.json"
  assert_eq "the window excludes an old event" "3" "$(dave review --json | jq '.drift | length')"
  assert_eq "a wider window includes it" "4" "$(dave review --days 60 --json | jq '.drift | length')"
}

# ------------------------------------------------------------------- helpers

test_helpers() {
  dave init >/dev/null
  # shellcheck disable=SC1090
  . "$TEST_DIR/../lib/common.sh"

  local f="$DAVE_HOME/t.jsonl"
  printf '{"a":1}\n{"a":2}\n' > "$f"
  assert_eq "jsonl_stream reads clean records" "2" "$(jsonl_stream "$f" | wc -l)"
  printf '{"a":3' >> "$f"   # an append interrupted mid-write
  assert_eq "jsonl_stream survives a truncated tail" "2" "$(jsonl_stream "$f" | wc -l)"
  assert_eq "jsonl_fold folds to an array" "3" "$(jsonl_fold "$f" 'map(.a) | add')"
  assert_eq "jsonl_fold on a missing file" "null" "$(jsonl_fold "$DAVE_HOME/nope.jsonl" 'map(.a) | add')"

  jsonl_append "$f" '{"a":4}'
  assert_eq "jsonl_append adds a record" "3" "$(jsonl_stream "$f" | wc -l)"
  # The appended record must survive landing after a truncated one.
  assert_eq "jsonl_append survives a truncated tail" "4" "$(jsonl_fold "$f" 'map(.a) | max')"
  jsonl_append "$DAVE_HOME/fresh.jsonl" '{"a":9}'
  assert_eq "jsonl_append creates the file" "9" "$(jsonl_fold "$DAVE_HOME/fresh.jsonl" 'map(.a) | add')"

  assert_eq "json_get returns a value" "dry" "$(json_get "$CONFIG" '.personality.wit')"
  assert_eq "json_get falls back" "fallback" "$(json_get "$CONFIG" '.nothing.here' 'fallback')"
  assert_eq "json_get on a missing file" "d" "$(json_get "$DAVE_HOME/nope.json" '.x' 'd')"

  # The bug the session-start hook documents: `.x // true` cannot return false.
  json_edit "$CONFIG" '.hooks.session_start = false'
  assert_eq "config_bool respects an explicit false" "false" "$(config_bool '.hooks.session_start' true)"
  json_edit "$CONFIG" 'del(.hooks.session_start)'
  assert_eq "config_bool defaults when absent" "true" "$(config_bool '.hooks.session_start' true)"
}

test_git_probe() {
  dave init >/dev/null
  # shellcheck disable=SC1090
  . "$TEST_DIR/../lib/common.sh"

  assert_eq "git_probe on a missing path" "false" "$(git_probe "$DAVE_HOME/nope" | jq -r .exists)"
  mkdir -p "$DAVE_HOME/plain"
  assert_eq "git_probe on a non-repo" "false" "$(git_probe "$DAVE_HOME/plain" | jq -r .repo)"

  local repo="$DAVE_HOME/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hello > "$repo/f.txt"
  git -C "$repo" add f.txt && git -C "$repo" commit -qm "feat: first"
  local probe; probe="$(git_probe "$repo")"
  assert_eq "git_probe finds a repo"        "true"       "$(printf '%s' "$probe" | jq -r .repo)"
  assert_eq "git_probe reads the subject"   "feat: first" "$(printf '%s' "$probe" | jq -r .last_subject)"
  assert_eq "git_probe on a clean tree"     "0"          "$(printf '%s' "$probe" | jq -r .dirty)"
  echo dirty >> "$repo/f.txt"; echo new > "$repo/untracked.txt"
  probe="$(git_probe "$repo")"
  assert_eq "git_probe counts dirty files"  "1" "$(printf '%s' "$probe" | jq -r .dirty)"
  assert_eq "git_probe counts untracked"    "1" "$(printf '%s' "$probe" | jq -r .untracked)"
  assert_eq "git_probe with no upstream"    "0" "$(printf '%s' "$probe" | jq -r .ahead)"
}

# Transport is Syncthing now: dave.sh never pushes or pulls. Setup writes the
# ignore file and local config, status reads the journal folder, and conflict
# copies are the only state that ever needs resolving.
test_sync() {
  dave init >/dev/null
  assert_contains "status before setup says so" "$(dave sync status)" "not enabled"

  local out; out="$(dave sync setup)"
  assert_contains "setup prints the checklist" "$out" "Syncthing folder"
  assert_contains "checklist wants the same Folder ID" "$out" "same Folder ID"
  [ -f "$DAVE_HOME/.stignore" ] && ok "setup writes .stignore" || no "setup writes .stignore" "missing"
  # Root-anchored so the rule cannot be read as a match on a nested .local.
  assert_contains ".stignore keeps .local device-side" \
    "$(cat "$DAVE_HOME/.stignore")" "/.local"
  assert_eq "setup flips enabled in local config" "true" \
    "$(jq -r .sync.enabled "$DAVE_HOME/.local/config.json")"
  assert_eq "shared config stays out of sync bookkeeping" "null" \
    "$(jq -r '.sync // "null"' "$DAVE_HOME/config.json")"
  [ -f "$DAVE_HOME/.obsidian/app.json" ] && ok "setup marks the folder a vault" \
    || no "setup marks the folder a vault" "missing .obsidian/app.json"

  # --vault must refuse a different path rather than move anything.
  assert_exit "setup --vault refuses a foreign path" 1 dave sync setup --vault /tmp/other-vault

  # Status sees every journal file in the folder, whoever wrote it.
  dave focus set RM-1 "work" >/dev/null
  printf '%s\n' \
    '{"ts":"2026-09-19T00:00:00+00:00","seq":1,"dev":"laptop-x1","sid":"1","type":"next.set","data":{"ref":"R","text":"t","project":"","ts":"x"}}' \
    > "$DAVE_HOME/journal/laptop-x1.jsonl"
  local js; js="$(dave sync status --json)"
  assert_eq "status counts two journals" "2" "$(printf '%s' "$js" | jq '.journals | length')"
  assert_eq "status reports event counts" "1" \
    "$(printf '%s' "$js" | jq '.journals[] | select(.dev == "laptop-x1") | .events')"
  assert_eq "status reports view freshness" "fresh" "$(printf '%s' "$js" | jq -r .views)"
  assert_eq "status reports enabled" "true" "$(printf '%s' "$js" | jq .enabled)"

  # Conflict copies are listed and resolvable.
  printf 'local line\n' > "$DAVE_HOME/priorities.sync-conflict-20260919-120000-ABCDEF.md"
  out="$(dave sync conflicts)"
  assert_contains "conflicts lists the copy" "$out" "priorities.sync-conflict-20260919-120000-ABCDEF.md"
  assert_contains "and the file it shadows" "$out" "priorities.md"
  assert_eq "status counts the conflict" "1" "$(dave sync status --json | jq .conflicts)"
  assert_exit "a bogus path is refused" 1 dave sync conflicts resolve /etc/passwd keep-local
  assert_exit "a non-conflict name is refused" 1 dave sync conflicts resolve priorities.md keep-local
  out="$(dave sync conflicts resolve "$DAVE_HOME/priorities.sync-conflict-20260919-120000-ABCDEF.md" keep-local)"
  assert_contains "keep-local reports" "$out" "kept local"
  [ ! -f "$DAVE_HOME/priorities.sync-conflict-20260919-120000-ABCDEF.md" ] \
    && ok "keep-local removes the copy" || no "keep-local removes the copy" "still there"
  printf 'remote line\n' > "$DAVE_HOME/priorities.sync-conflict-20260919-120000-ABCDEF.md"
  out="$(dave sync conflicts resolve "$DAVE_HOME/priorities.sync-conflict-20260919-120000-ABCDEF.md" keep-remote)"
  assert_contains "keep-remote reports" "$out" "kept remote"
  assert_eq "keep-remote replaces the original" "remote line" "$(head -1 "$DAVE_HOME/priorities.md")"
  [ ! -f "$DAVE_HOME/priorities.sync-conflict-20260919-120000-ABCDEF.md" ] \
    && ok "keep-remote removes the copy" || no "keep-remote removes the copy" "still there"

  # brief must succeed with sync enabled and never touch git or the network —
  # there is no pull step anymore.
  [ ! -d "$DAVE_HOME/.git" ] && ok "no .git in the tree" || no "no .git in the tree" "found"
  out="$(dave brief)"
  assert_contains "brief still runs" "$out" "=== PRIORITIES ==="
  case "$out" in
    *"=== SYNC ==="*) no "brief does not lead with a pull" "found SYNC section" ;;
    *) ok "brief does not lead with a pull" ;;
  esac

  # sync rebuild is an alias for the top-level rebuild.
  out="$(dave sync rebuild)"
  assert_contains "sync rebuild aliases rebuild" "$out" "rebuilt"
}

# The guided half of setup: a stub syncthing binary and a canned REST api on
# PATH, credentials scraped from a fixture config.xml. STUB_VAULT/STUB_CAPTURE
# carry the test paths into the stub so it needs no interpolation.
test_sync_guided() {
  dave init >/dev/null
  local mock="$DAVE_HOME/mockbin" cap="$DAVE_HOME/post.json"
  mkdir -p "$mock" "$DAVE_HOME/sthome"
  cat > "$mock/syncthing" <<'STUB'
#!/usr/bin/env bash
echo "syncthing v1.27.0 (test stub)"
STUB
  cat > "$mock/curl" <<'STUB'
#!/usr/bin/env bash
url="${@: -1}"
method="GET"; data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -d|--data*) data="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$method $url" in
  GET*/rest/system/status) printf '{"myID":"STUB-ID-0001"}' ;;
  GET*/rest/config/folders)
    if [ -f "$STUB_CAPTURE" ]; then
      printf '[{"id":"dave-vault","path":"%s","versioning":{"type":"staggered"}}]' "$STUB_VAULT"
    else
      printf '[]'
    fi ;;
  POST*/rest/config/folders) printf '%s' "$data" > "$STUB_CAPTURE"; printf '{}' ;;
  *) exit 22 ;;
esac
STUB
  chmod +x "$mock/syncthing" "$mock/curl"

  # The <device> block's <address>dynamic</address> must NOT leak into the
  # gui credentials — only the <gui> range is read.
  cat > "$DAVE_HOME/sthome/config.xml" <<'STUB'
<configuration version="37">
    <device id="AAAA-BBBB"><address>dynamic</address></device>
    <gui enabled="true" tls="false" debugging="false">
        <address>127.0.0.1:8384</address>
        <apikey>stub-key-123</apikey>
    </gui>
</configuration>
STUB

  # No daemon binary → install instructions, never a hang or a crash.
  local out
  out="$(env "PATH=$mock:$PATH" SYNCTHING_BIN=dave-no-such-syncthing \
    "$DAVE" sync setup)"
  assert_contains "missing daemon prints install hint" "$out" "not installed"
  assert_contains "install hint names the package" "$out" "apt install syncthing"

  # Daemon present but no api key anywhere → manual instructions.
  out="$(env "PATH=$mock:$PATH" SYNCTHING_API_KEY="" \
    SYNCTHING_CONFIG=/nonexistent "$DAVE" sync setup)"
  assert_contains "no api key points at the gui" "$out" "no api key"

  # --auto registers the folder without prompting (tests are never a tty).
  out="$(env "PATH=$mock:$PATH" SYNCTHING_API_KEY="" \
    "SYNCTHING_CONFIG=$DAVE_HOME/sthome/config.xml" \
    "STUB_CAPTURE=$cap" "STUB_VAULT=$DAVE_HOME" \
    "$DAVE" sync setup --auto)"
  assert_contains "auto registers the folder" "$out" "registered 'dave-vault'"
  assert_contains "setup prints the daemon's device id" "$out" "STUB-ID-0001"
  assert_eq "POST carries the fixed folder id" "dave-vault" "$(jq -r .id "$cap")"
  assert_eq "POST covers the vault path" "$DAVE_HOME" "$(jq -r .path "$cap")"
  assert_eq "POST turns on the fs watcher" "true" "$(jq .fsWatcherEnabled "$cap")"
  assert_eq "POST turns on staggered versioning" "staggered" \
    "$(jq -r .versioning.type "$cap")"
  assert_eq "scraped api key is saved device-locally" "stub-key-123" \
    "$(jq -r .sync.syncthing_api_key "$DAVE_HOME/.local/config.json")"
  assert_eq "gui address came from the <gui> block, not a device" \
    "http://127.0.0.1:8384" \
    "$(jq -r .sync.syncthing_url "$DAVE_HOME/.local/config.json")"

  # Without --auto and without a tty, setup must skip rather than prompt.
  rm -f "$cap"
  out="$(env "PATH=$mock:$PATH" "STUB_CAPTURE=$cap" "STUB_VAULT=$DAVE_HOME" \
    "$DAVE" sync setup </dev/null)"
  assert_contains "no tty means skip, not prompt" "$out" "skipped"
  [ ! -f "$cap" ] && ok "skipped setup posts nothing" \
    || no "skipped setup posts nothing" "POST captured anyway"
  # A piped yes is still not a tty.
  out="$(printf 'y\n' | env "PATH=$mock:$PATH" "STUB_CAPTURE=$cap" \
    "STUB_VAULT=$DAVE_HOME" "$DAVE" sync setup)"
  assert_contains "piped input does not bypass the prompt" "$out" "skipped"

  # Once registered, a re-run reports it instead of posting again.
  env "PATH=$mock:$PATH" "STUB_CAPTURE=$cap" "STUB_VAULT=$DAVE_HOME" \
    "$DAVE" sync setup --auto >/dev/null
  out="$(env "PATH=$mock:$PATH" "STUB_CAPTURE=$cap" "STUB_VAULT=$DAVE_HOME" \
    "$DAVE" sync setup --auto)"
  assert_contains "second run sees the registered folder" "$out" "already registered"

  # Status uses the saved credentials and reports the daemon's id for pairing.
  local js
  js="$(env "PATH=$mock:$PATH" "STUB_CAPTURE=$cap" "STUB_VAULT=$DAVE_HOME" \
    "$DAVE" sync status --json)"
  assert_eq "status sees the registered folder" "folder registered" \
    "$(printf '%s' "$js" | jq -r .syncthing)"
  assert_eq "status reports the daemon device id" "STUB-ID-0001" \
    "$(printf '%s' "$js" | jq -r .syncthing_id)"
  assert_exit "status exits clean with a reachable daemon" 0 \
    env "PATH=$mock:$PATH" "STUB_CAPTURE=$cap" "STUB_VAULT=$DAVE_HOME" \
    "$DAVE" sync status
}

test_help() {
  local out; out="$(dave help)"
  for c in init migrate rebuild brief focus drift park log standup mission intake project \
           scan time next promise dossier review sync dashboard; do
    assert_contains "help lists $c" "$out" "  $c"
  done
  assert_exit "an unknown command fails" 1 dave frobnicate
}

# ------------------------------------------------------------- event journal

test_journal_events() {
  dave init >/dev/null
  local dev; dev="$(jq -r .id "$DAVE_HOME/.local/device.json")"
  dave focus set RM-1 "one" >/dev/null
  dave focus set RM-2 "two" >/dev/null
  local jf="$DAVE_HOME/journal/$dev.jsonl"
  [ -f "$jf" ] && ok "events land in journal/<dev>.jsonl" || no "events land in journal/<dev>.jsonl" "missing: $jf"
  # Two separate invocations must continue the same counter, not restart it.
  assert_eq "seq is a strict 1..N counter across invocations" "true" \
    "$(jq -s 'map(.seq) | . == [range(1; length + 1)]' "$jf")"
  assert_eq "every event names its device" "true" \
    "$(jq -s --arg d "$dev" 'all(.dev == $d)' "$jf")"
  assert_eq "the view still shows the latest" "RM-2" \
    "$(jq -r .focus.ref "$DAVE_HOME/.local/views/state.json")"
}

test_journal_device() {
  dave init >/dev/null
  local id; id="$(jq -r .id "$DAVE_HOME/.local/device.json")"
  case "$id" in
    *[a-z0-9-]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ok "device id matches <host>-<6hex>" ;;
    *) no "device id matches <host>-<6hex>" "got: $id" ;;
  esac
  dave focus set RM-1 >/dev/null
  assert_eq "device id is stable across invocations" "$id" \
    "$(jq -r .id "$DAVE_HOME/.local/device.json")"
}

test_views_empty() {
  dave init >/dev/null
  local s="$DAVE_HOME/.local/views/state.json"
  assert_eq "empty journal yields all state keys" \
    "active_mission created drift_events focus focus_stack identity_diagnostics last_brief last_intake schema_version" \
    "$(jq -r 'keys | join(" ")' "$s")"
  assert_eq "empty journal yields an empty stack" "[]" "$(jq -c .focus_stack "$s")"
  assert_eq "empty journal yields no drift" "[]" "$(jq -c .drift_events "$s")"
  assert_eq "empty journal yields schema" "3" "$(jq .schema_version "$s")"
  assert_eq "notes view is an empty object" "{}" "$(jq -c . "$DAVE_HOME/.local/views/notes.json")"
  assert_eq "commitments view is an empty array" "[]" "$(jq -c . "$DAVE_HOME/.local/views/commitments.json")"
}

test_views_truncated_tail() {
  dave init >/dev/null
  dave focus set RM-1 "kept" >/dev/null
  local jf; jf="$(printf '%s\n' "$DAVE_HOME"/journal/*.jsonl)"
  printf '{"ts":"2999-01-01T00:00:00+00:00","seq":9,"dev":"x","sid":"y","type":"focus.set","data":{"ref":"EVIL"' >> "$jf"
  dave rebuild >/dev/null
  assert_eq "a truncated tail is skipped" "RM-1" \
    "$(jq -r .focus.ref "$DAVE_HOME/.local/views/state.json")"
}

test_views_two_devices() {
  dave init >/dev/null
  local home_a="$DAVE_HOME"
  DAVE_HOME="$home_a" dave focus set RM-1 "from a" >/dev/null
  local home_b; home_b="$(mktemp -d "${TMPDIR:-/tmp}/dave-testB.XXXXXX")"
  DAVE_HOME="$home_b" dave init >/dev/null
  DAVE_HOME="$home_b" dave promise add bob thing 2030-01-01 >/dev/null
  # Exchange journals the way Syncthing would.
  cp "$home_a"/journal/*.jsonl "$home_b/journal/"
  cp "$home_b"/journal/*.jsonl "$home_a/journal/"
  DAVE_HOME="$home_a" dave state >/dev/null
  DAVE_HOME="$home_b" dave state >/dev/null
  local f same=1
  for f in state.json missions.json notes.json commitments.json \
           log.json parked.json projects.json \
           sessions.jsonl assignments.jsonl; do
    diff -q "$home_a/.local/views/$f" "$home_b/.local/views/$f" >/dev/null || { same=0; break; }
  done
  assert_eq "two devices fold to identical views" "1" "$same"
  assert_eq "b sees a's focus" "RM-1" \
    "$(jq -r .focus.ref "$home_b/.local/views/state.json")"
  assert_eq "a sees b's promise" "c1" \
    "$(jq -r '.[0].id' "$home_a/.local/views/commitments.json")"
  rm -rf "$home_b"
}

test_views_ordering() {
  dave init >/dev/null
  # Same ts, different devices: the higher dev name wins — deterministically,
  # on both sides.
  printf '%s\n' \
    '{"ts":"2026-09-19T00:00:00+00:00","seq":1,"dev":"aaa","sid":"1","type":"focus.set","data":{"ref":"AAA","label":"","project":"","started":"s"}}' \
    > "$DAVE_HOME/journal/aaa.jsonl"
  printf '%s\n' \
    '{"ts":"2026-09-19T00:00:00+00:00","seq":1,"dev":"bbb","sid":"1","type":"focus.set","data":{"ref":"BBB","label":"","project":"","started":"s"}}' \
    > "$DAVE_HOME/journal/bbb.jsonl"
  dave rebuild >/dev/null
  assert_eq "ts tie breaks on device id" "BBB" \
    "$(jq -r .focus.ref "$DAVE_HOME/.local/views/state.json")"
  # Same device, same ts: the higher seq wins.
  printf '%s\n' \
    '{"ts":"2026-09-19T00:00:00+00:00","seq":5,"dev":"aaa","sid":"1","type":"focus.set","data":{"ref":"SEQ5","label":"","project":"","started":"s"}}' \
    '{"ts":"2026-09-19T00:00:00+00:00","seq":9,"dev":"aaa","sid":"1","type":"focus.set","data":{"ref":"SEQ9","label":"","project":"","started":"s"}}' \
    > "$DAVE_HOME/journal/aaa.jsonl"
  rm -f "$DAVE_HOME/journal/bbb.jsonl"
  dave rebuild >/dev/null
  assert_eq "same-device tie breaks on seq" "SEQ9" \
    "$(jq -r .focus.ref "$DAVE_HOME/.local/views/state.json")"
}

test_views_fingerprint() {
  dave init >/dev/null
  local fp="$DAVE_HOME/.local/views/.fingerprint"
  local before; before="$(stat -c %Y "$fp")"
  sleep 1
  dave state >/dev/null
  assert_eq "no journal change means no rebuild" "$before" "$(stat -c %Y "$fp")"
  sleep 1
  printf '%s\n' \
    '{"ts":"2026-09-19T00:00:00+00:00","seq":1,"dev":"ext","sid":"1","type":"next.set","data":{"ref":"R","text":"t","project":"","ts":"x"}}' \
    >> "$DAVE_HOME/journal/ext.jsonl"
  dave state >/dev/null
  [ "$(stat -c %Y "$fp")" -gt "$before" ] && ok "a new journal file forces a rebuild" \
    || no "a new journal file forces a rebuild" "fingerprint unchanged"
  assert_eq "the external event folded in" "t" \
    "$(jq -r .R.text "$DAVE_HOME/.local/views/notes.json")"
}

# An interleaved write sequence replayed on two homes that share journals by
# copy must produce byte-identical views — the M2 conversion's core promise.
test_views_interleaved() {
  dave init >/dev/null
  local home_a="$DAVE_HOME" home_b
  home_b="$(mktemp -d "${TMPDIR:-/tmp}/dave-testB.XXXXXX")"
  DAVE_HOME="$home_b" dave init >/dev/null
  local seq
  for step in "a:focus set RM-1 one" "b:promise add bob thing 2030-01-01" \
              "a:next set RM-1 parked at the parser" "b:drift record unlisted parked" \
              "a:park a stray idea" "b:mission new shared-work" \
              "a:promise keep c1" "b:next set RM-2 other note"; do
    seq="${step%%:*}"; local cmd="${step#*:}"
    if [ "$seq" = a ]; then
      # shellcheck disable=SC2086  # cmd is a fixed test string, word-split on purpose
      DAVE_HOME="$home_a" dave $cmd >/dev/null
      cp "$home_a"/journal/*.jsonl "$home_b/journal/" 2>/dev/null || true
    else
      # shellcheck disable=SC2086
      DAVE_HOME="$home_b" dave $cmd >/dev/null
      cp "$home_b"/journal/*.jsonl "$home_a/journal/" 2>/dev/null || true
    fi
  done
  # Final exchange so both have every journal.
  cp "$home_a"/journal/*.jsonl "$home_b/journal/" 2>/dev/null || true
  cp "$home_b"/journal/*.jsonl "$home_a/journal/" 2>/dev/null || true
  DAVE_HOME="$home_a" dave state >/dev/null
  DAVE_HOME="$home_b" dave state >/dev/null
  local f same=1
  for f in state.json missions.json notes.json commitments.json \
           log.json parked.json projects.json \
           sessions.jsonl assignments.jsonl; do
    diff -q "$home_a/.local/views/$f" "$home_b/.local/views/$f" >/dev/null || { same=0; break; }
  done
  assert_eq "interleaved writes converge on identical views" "1" "$same"
  rm -rf "$home_b"
}

# Two devices minting ids from their own views will collide when they add
# offline. The reducer keeps the earlier event's id and rewrites the later one
# as <id>~<dev> — deterministically, so both homes agree which promise is which.
test_views_id_collision() {
  dave init >/dev/null
  local home_a="$DAVE_HOME" home_b
  home_b="$(mktemp -d "${TMPDIR:-/tmp}/dave-testB.XXXXXX")"
  DAVE_HOME="$home_b" dave init >/dev/null
  local dev_b; dev_b="$(jq -r .id "$home_b/.local/device.json")"
  # Both homes mint c1 before either has seen the other. The sleep makes the
  # event order deterministic — envelope ts is second-resolution, so b's add
  # must land in a strictly later second for the suffix to be b's.
  DAVE_HOME="$home_a" dave promise add ann "a thing" 2030-01-01 >/dev/null
  sleep 1
  DAVE_HOME="$home_b" dave promise add bob "b thing" 2030-01-01 >/dev/null
  cp "$home_a"/journal/*.jsonl "$home_b/journal/"
  cp "$home_b"/journal/*.jsonl "$home_a/journal/"
  DAVE_HOME="$home_a" dave state >/dev/null
  DAVE_HOME="$home_b" dave state >/dev/null
  local ids_a ids_b
  ids_a="$(jq -rc 'map(.id) | sort' "$home_a/.local/views/commitments.json")"
  ids_b="$(jq -rc 'map(.id) | sort' "$home_b/.local/views/commitments.json")"
  assert_eq "collided ids are both present, suffixed on the later device" \
    "[\"c1\",\"c1~$dev_b\"]" "$ids_a"
  assert_eq "both homes agree on the ids" "$ids_a" "$ids_b"
  # And they agree on which promise owns which id.
  local who_a who_b
  who_a="$(jq -rc 'sort_by(.id) | map(.who) | join(",")' "$home_a/.local/views/commitments.json")"
  who_b="$(jq -rc 'sort_by(.id) | map(.who) | join(",")' "$home_b/.local/views/commitments.json")"
  assert_eq "both homes agree which promise is which" "$who_a" "$who_b"
  assert_eq "the earlier event keeps the clean id" "ann" \
    "$(jq -r '.[] | select(.id == "c1") | .who' "$home_a/.local/views/commitments.json")"
  rm -rf "$home_b"
}

# ----------------------------------------------------------------------- run

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 1; }

for t in init init_idempotent not_set_up_exits_3 migrate migrate_partial \
         config_cache focus drift journal \
         priorities_set parked_done \
         intake mission project project_resolve project_candidates \
         hook_schema_note brief focus_stack time_ledger time_open_cap \
         drift_events next promise scan brief_phase_b \
         mission_ledger mission_legacy mission_pack dossier \
         review_empty review_cadence review_findings review_owed review_drift \
         helpers git_probe \
         journal_events journal_device \
         views_empty views_truncated_tail views_two_devices views_ordering \
         views_fingerprint views_interleaved views_id_collision \
         sync sync_guided help; do
  run_test "$t"
done

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed tests:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi

if [ -s "$ERROR_LOG" ]; then cat "$ERROR_LOG" >&2; exit 1; fi
