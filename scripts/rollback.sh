#!/usr/bin/env bash
# Usage: rollback.sh <actor>
# Points "current" at the next older release. Exits with an error if none exists.
set -euo pipefail

ACTOR="${1:-unknown}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(basename "$SCRIPT_DIR")" in
  bin) BASE="$(dirname "$SCRIPT_DIR")" ;;
  *)   BASE="$(dirname "$(dirname "$SCRIPT_DIR")")" ;;
esac

RELEASES="$BASE/releases"
CURRENT="$(readlink -f "$BASE/current")"

TARGET=""
FOUND=0
# newest first; the target is the one right after the current release
while IFS= read -r rel; do
  if [ "$FOUND" -eq 1 ]; then
    TARGET="$rel"
    break
  fi
  if [ "$(readlink -f "$rel")" = "$CURRENT" ]; then
    FOUND=1
  fi
done < <(ls -dt "$RELEASES"/*)

if [ -z "$TARGET" ]; then
  echo "ERROR: no older release to roll back to" >&2
  exit 1
fi

ln -sfn "$TARGET" "$BASE/current"
echo "$(date '+%F %T') ROLLBACK $(basename "$CURRENT") -> $(basename "$TARGET") by $ACTOR" >> "$BASE/deploys.log"
echo "Rolled back to $(basename "$TARGET")"
