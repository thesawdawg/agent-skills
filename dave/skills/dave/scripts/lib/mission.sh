# shellcheck shell=bash
# shellcheck disable=SC2034  # paths are consumed by the sibling libs, not this file
# mission.sh — mission briefs. The assignment ledger lands here in Phase C.
# Sourced by dave.sh.

cmd_mission() {
  require_init
  local sub="${1:-list}"
  case "$sub" in
    new)
      [ $# -ge 2 ] || die "usage: mission new <name>"
      local slug path
      slug="$(slugify "$2")"
      path="$MISSIONS/$slug.md"
      [ -f "$path" ] && die "mission already exists: $path"
      sed -e "s|{{SLUG}}|$slug|g" -e "s|{{DATE}}|$(today)|g" \
        "$TEMPLATES/mission-brief-template.md" > "$path"
      echo "$path"
      ;;
    show)
      [ $# -ge 2 ] || die "usage: mission show <slug>"
      cat "$MISSIONS/$(slugify "$2").md"
      ;;
    list)
      ls -1 "$MISSIONS" 2>/dev/null | sed 's/\.md$//' || echo "(no missions)"
      ;;
    *) die "unknown mission subcommand: $sub" ;;
  esac
}
