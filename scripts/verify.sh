#!/usr/bin/env bash
# Single repository verification entry point. See STRUCTURE.md.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

for command in git jq node npm python3 shellcheck; do
  command -v "$command" >/dev/null || { echo "Missing required executable: $command" >&2; exit 3; }
done
python3 -c 'import yaml' 2>/dev/null || {
  echo 'Missing PyYAML; run: pip install -r tests/requirements.txt' >&2
  exit 3
}
[ -f node_modules/skills/bin/cli.mjs ] || {
  echo 'Missing pinned skills CLI; run: npm ci' >&2
  exit 3
}

python3 scripts/validate.py

mapfile -t scripts_list < <(find . -name '*.sh' -not -path './node_modules/*')
for script in "${scripts_list[@]}"; do
  bash -n "$script"
done
shellcheck --severity=warning "${scripts_list[@]}"

node --check dogfood/scripts/browser-driver.mjs

# Any script advertising --selftest must honor it; discovery keeps the
# convention self-enforcing as helpers are added. Match the flag *handler*
# (a case arm or argv test), not a mention — this script must not match.
mapfile -t selftests < <(
  { grep -rlE --include='*.sh' -- '--selftest\)' .
    grep -rlE --include='*.py' -- "--selftest['\"]" . ; } \
    | grep -v node_modules | sort -u
)
[ "${#selftests[@]}" -gt 0 ] || { echo 'No --selftest handlers discovered' >&2; exit 1; }
for helper in "${selftests[@]}"; do
  case "$helper" in
    *.sh) bash "$helper" --selftest >/dev/null ;;
    *.py) python3 "$helper" --selftest >/dev/null ;;
  esac
done

bash scripts/preflight.sh
bash tests/test_bundles.sh
bash tests/test_doc_repo.sh
bash tests/test_fixture_runner.sh
python3 tests/test_helpers.py
python3 tests/test_installer.py
python3 tests/test_dashboard.py

# The sync exercise performs git pushes; keep it opt-in outside this suite.
DAVE_TEST_SKIP_SYNC=1 bash dave/skills/dave/scripts/test/run.sh | tail -3

if [ "${VERIFY_BROWSER:-0}" = 1 ]; then
  driver=$(bash dogfood/scripts/setup.sh --install-browser)
  BROWSER_DRIVER="$driver" python3 tests/test_browser.py
fi

printf 'verify.sh: all checks passed\n'
