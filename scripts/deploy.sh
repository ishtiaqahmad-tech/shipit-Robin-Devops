#!/usr/bin/env bash
# Usage: deploy.sh <full-sha> <actor>
# Runs on the server as the "deploy" user. Works out the team folder
# from its own location, so no team name is written in this file.
set -euo pipefail

SHA="${1:?usage: deploy.sh <sha> <actor>}"
ACTOR="${2:-unknown}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(basename "$SCRIPT_DIR")" in
  bin) BASE="$(dirname "$SCRIPT_DIR")" ;;
  *)   BASE="$(dirname "$(dirname "$SCRIPT_DIR")")" ;;   # .../upload/scripts
esac

UPLOAD="$BASE/upload"
RELEASES="$BASE/releases"
BIN="$BASE/bin"
NOW="$(date +%Y%m%d-%H%M%S)"
REL="$RELEASES/${NOW}-${SHA:0:7}"

echo "Deploying ${SHA:0:7} by $ACTOR to $REL"

# 1. new release folder from the uploaded site
mkdir -p "$RELEASES"
cp -r "$UPLOAD/site" "$REL"

# 2. stamp the version into every page
VERSION="$SHA by $ACTOR at $(date)"
sed -i "s|__VERSION__|$VERSION|g" "$REL"/*.html
if ls "$REL"/members/*.html >/dev/null 2>&1; then
  sed -i "s|__VERSION__|$VERSION|g" "$REL"/members/*.html
fi
chmod -R a+rX "$REL"

# 3. switch the live link to the new release
ln -sfn "$REL" "$BASE/current"

# 4. log it
echo "$(date '+%F %T') DEPLOY ${SHA:0:7} by $ACTOR -> $(basename "$REL")" >> "$BASE/deploys.log"

# 5. keep only the 5 newest releases
ls -dt "$RELEASES"/* | tail -n +6 | xargs -r rm -rf

# 6. A13: install scripts, config and crontab
mkdir -p "$BIN"
cp "$UPLOAD"/scripts/*.sh "$BIN"/ 2>/dev/null || true
cp "$UPLOAD"/scripts/team.conf "$BIN"/ 2>/dev/null || true
chmod +x "$BIN"/*.sh 2>/dev/null || true

cat > "$BIN/crontab.txt" <<EOF
* * * * * $BIN/status.sh
*/5 * * * * $BIN/traffic-report.sh
EOF
crontab "$BIN/crontab.txt"

echo "Deploy finished"
