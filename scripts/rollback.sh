#!/bin/bash
# rollback.sh - runs ON THE SERVER as the deploy user (A10)
# Usage: rollback.sh PUSHER_NAME
# Points "current" back to the release before the one that is live now.

set -euo pipefail

PUSHER="${1:-unknown}"
TEAM="${TEAM:-robin}"
BASE="/var/www/$TEAM"
RELEASES="$BASE/releases"
LOG="$BASE/deploys.log"
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Do not run at the same time as a deploy
exec 9>"$BASE/.deploy.lock"
if ! flock -n 9; then
  echo "ERROR: a deployment or rollback is running"
  exit 1
fi

if [ ! -L "$BASE/current" ]; then
  echo "ERROR: no live release found"
  exit 1
fi

LIVE=$(basename "$(readlink -f "$BASE/current")")

# Release names start with a timestamp, so sorting by name sorts by time.
# Take the newest release that is older than the live one.
PREVIOUS=$(ls -1 "$RELEASES" | sort | awk -v live="$LIVE" '$0 < live' | tail -n 1)

if [ -z "$PREVIOUS" ]; then
  echo "ERROR: no older release to roll back to (live: $LIVE)"
  exit 1
fi

# Switch atomically
ln -sfn "$RELEASES/$PREVIOUS" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"

echo "$NOW | rollback to $PREVIOUS | by $PUSHER | from $LIVE" >> "$LOG"

echo "Rolled back from $LIVE to $PREVIOUS"
