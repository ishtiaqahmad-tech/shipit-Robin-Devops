#!/bin/bash
# status.sh - writes /var/www/TEAM/live/status.html (A11)
# Runs every minute from the deploy user's crontab.

# Load TEAM and DOMAIN from team.conf (same folder as this script)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/team.conf"

# If team.conf uses different variable names, fix them here:
TEAM="${TEAM:-${TEAM_NAME:-robin}}"

BASE="/var/www/$TEAM"
OUT="$BASE/live/status.html"
TMP="$OUT.tmp"
STATE="$BASE/.status_state"            # remembers last warning state (for Slack)
WEBHOOK_FILE="$HOME/.slack_webhook"    # chmod 600, only deploy can read

mkdir -p "$BASE/live"

# ---- Collect info ----
HOST=$(hostname)
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')
UPTIME=$(uptime -p)
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
MEM=$(free -h | awk '/^Mem:/ {print $3 " used of " $2}')
DISK_PCT=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
DISK=$(df -h / | awk 'NR==2 {print $3 " used of " $2 " (" $5 ")"}')

if systemctl is-active --quiet nginx; then
  NGINX="running"
  NGINX_OK=1
else
  NGINX="NOT running"
  NGINX_OK=0
fi

if [ -L "$BASE/current" ]; then
  RELEASE=$(basename "$(readlink -f "$BASE/current")")
else
  RELEASE="none yet"
fi

if [ -f "$BASE/deploys.log" ]; then
  DEPLOYS=$(tail -n 5 "$BASE/deploys.log" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
else
  DEPLOYS="no deploys yet"
fi

# ---- Warnings ----
WARNINGS=""
if [ "$DISK_PCT" -gt 80 ]; then
  WARNINGS="${WARNINGS}Disk is ${DISK_PCT}% full. "
fi
if [ "$NGINX_OK" -eq 0 ]; then
  WARNINGS="${WARNINGS}Nginx is not running. "
fi

if [ -n "$WARNINGS" ]; then
  STATE_NOW="warning"
  AVATAR="!"
  AVATAR_COLOR="#dc2626"
  BADGE="WARNING"
  BADGE_STYLE="background:#fee2e2;color:#dc2626;"
  WARN_TEXT="<p style=\"color:#dc2626;font-weight:bold;margin-bottom:12px;\">WARNING: $WARNINGS</p>"
else
  STATE_NOW="ok"
  AVATAR="OK"
  AVATAR_COLOR="#16a34a"
  BADGE="All systems OK"
  BADGE_STYLE=""
  WARN_TEXT=""
fi

# ---- Write the page (to a temp file, then move, so it is never half-written) ----
cat > "$TMP" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="30">
  <title>$TEAM server status</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <div class="team-card" style="max-width:520px;text-align:left;">
    <div class="avatar" style="background:$AVATAR_COLOR;">$AVATAR</div>
    <h2 style="text-align:center;">$TEAM server status</h2>
    <div style="text-align:center;"><h3 style="$BADGE_STYLE">$BADGE</h3></div>
    $WARN_TEXT
    <p><b>Hostname:</b> $HOST</p>
    <p><b>Page written:</b> $NOW</p>
    <p><b>Uptime:</b> $UPTIME</p>
    <p><b>Load (1/5/15 min):</b> $LOAD</p>
    <p><b>Memory:</b> $MEM</p>
    <p><b>Disk (/):</b> $DISK</p>
    <p><b>Nginx:</b> $NGINX</p>
    <p><b>Live release:</b> $RELEASE</p>
    <p style="margin-top:14px;"><b>Last 5 deploys:</b></p>
    <p style="white-space:pre-wrap;font-family:monospace;font-size:12px;">$DEPLOYS</p>
    <p style="margin-top:14px;text-align:center;"><a href="/index.html">Back to home</a></p>
  </div>
</body>
</html>
EOF
mv "$TMP" "$OUT"

# ---- Stretch: Slack message only when the state changes ----
LAST_STATE=$(cat "$STATE" 2>/dev/null || echo "ok")
if [ "$STATE_NOW" != "$LAST_STATE" ] && [ -f "$WEBHOOK_FILE" ]; then
  WEBHOOK=$(cat "$WEBHOOK_FILE")
  if [ "$STATE_NOW" = "warning" ]; then
    MSG=":warning: $TEAM server WARNING: $WARNINGS"
  else
    MSG=":white_check_mark: $TEAM server is back to normal."
  fi
  curl -s -X POST -H 'Content-type: application/json' \
       --data "{\"text\": \"$MSG\"}" "$WEBHOOK" > /dev/null
fi
echo "$STATE_NOW" > "$STATE"