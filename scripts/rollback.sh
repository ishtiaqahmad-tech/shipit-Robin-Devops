#!/usr/bin/env bash
# Usage: rollback.sh <base_dir> <who_pressed_the_button>
set -euo pipefail

BASE="${1:?usage: rollback.sh <base_dir> <who>}"
WHO="${2:-unknown}"

CURRENT="$(readlink -f "$BASE/current")"

RELEASES=()
for d in "$BASE"/releases/[0-9]*/; do
  [ -d "$d" ] && RELEASES+=("${d%/}")
done
mapfile -t RELEASES < <(printf '%s\n' "${RELEASES[@]}" | sort)

PREVIOUS=""
for i in "${!RELEASES[@]}"; do
  if [ "$(readlink -f "${RELEASES[$i]}")" = "$CURRENT" ]; then
    if [ "$i" -gt 0 ]; then PREVIOUS="${RELEASES[$((i-1))]}"; fi
    break
  fi
done

if [ -z "$PREVIOUS" ]; then
  echo "ERROR: no older release to roll back to."
  echo "$(date '+%F %T') ROLLBACK FAILED (no older release) by $WHO" >> "$BASE/deploys.log"
  exit 1
fi

ln -sfn "$PREVIOUS" "$BASE/current"
echo "Rolled back: $(basename "$CURRENT") -> $(basename "$PREVIOUS")"
echo "$(date '+%F %T') ROLLBACK to $(basename "$PREVIOUS") by $WHO" >> "$BASE/deploys.log"
