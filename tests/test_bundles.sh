#!/usr/bin/env bash
# Exercise a selected D.A.V.E. bundle without its plugin parent.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/dave/skills/dave" "$tmp/installed skill"
ln -s "$tmp/installed skill" "$tmp/linked skill"
mkdir "$tmp/unrelated"
cd "$tmp/unrelated"
for mode in installed linked; do
  export DAVE_HOME="$tmp/state-$mode"
  driver="$tmp/$mode skill/scripts/dave.sh"
  bash "$driver" init >/dev/null
  bash "$driver" mission new 'bundle test' >/dev/null
  bash "$driver" mission pack bundle-test --agent critic > "$tmp/pack"
  grep -q 'Fails when:' "$tmp/pack"
  # A spawned instance must work from an installed copy too: the project-role
  # templates and the role lookup chain travel with the bundle.
  mkdir "$tmp/proj-$mode"
  bash "$driver" project spawn "$tmp/proj-$mode" --enable-role maintenance-tech >/dev/null
  (cd "$tmp/proj-$mode" && bash "$driver" mission pack bundle-test --agent maintenance-tech | grep -q 'Proposals')
done
printf 'Installed and symlink bundle tests passed\n'
