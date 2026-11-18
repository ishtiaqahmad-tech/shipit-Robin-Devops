#!/bin/bash
# deploy.sh - runs ON THE SERVER as the deploy user (A9, steps 2-6, plus A13)
# Usage: deploy.sh COMMIT_SHA PUSHER_NAME
# The workflow first uploads site/ and scripts/ to /var/www/TEAM/upload/

set -euo pipefail

COMMIT="${1:?missing commit}"
PUSHER="${2:?missing pusher}"
SHORT="${COMMIT:0:7}"

TEAM="${TEAM:-robin}"
BASE="/var/www/$TEAM"
UPLOAD="$BASE/upload"
RELEASES="$BASE/releases"
LOG="$BASE/deploys.log"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
RELEASE="$RELEASES/$(date '+%Y%m%d-%H%M%S')-$SHORT"

# Two deployments must never run at the same time
exec 9>"$BASE/.deploy.lock"
if ! flock -n 9; then
  echo "ERROR: another deployment is running"
  exit 1
fi

[ -d "$UPLOAD/site" ] || { echo "ERROR: $UPLOAD/site not found"; exit 1; }

# 2. New release folder with a copy of site/
mkdir -p "$RELEASES"
mkdir "$RELEASE"
cp -r "$UPLOAD/site/." "$RELEASE/"

# 3. Replace __VERSION__ in every page
VERSION="$SHORT by $PUSHER at $NOW"
VERSION_ESC=$(printf '%s' "$VERSION" | sed 's/[&|\\]/\\&/g')
find "$RELEASE" -type f -name "*.html" -exec sed -i "s|__VERSION__|$VERSION_ESC|g" {} +

# 4. Switch current to the new release (atomic)
ln -sfn "$RELEASE" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"

# 5. Log line
echo "$NOW | deployed $SHORT | by $PUSHER | $(basename "$RELEASE")" >> "$LOG"

# 6. Keep only the 5 newest releases
ls -1dt "$RELEASES"/*/ 2>/dev/null | tail -n +6 | xargs -r rm -rf

# A13: install the scripts and the crontab
if [ -d "$UPLOAD/scripts" ]; then
  mkdir -p "$BASE/bin" "$BASE/live"
  for f in status.sh traffic-report.sh rollback.sh team.conf; do
    [ -f "$UPLOAD/scripts/$f" ] && cp "$UPLOAD/scripts/$f" "$BASE/bin/$f"
  done
  chmod +x "$BASE/bin/"*.sh 2>/dev/null || true

  cat <<CRON | crontab -
* * * * * $BASE/bin/status.sh
*/5 * * * * $BASE/bin/traffic-report.sh
CRON
fi

echo "Deployed $SHORT to $RELEASE"