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
  NGINX="Running"
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
DISK_STYLE=""
NGINX_STYLE=""
if [ "$DISK_PCT" -gt 80 ]; then
  WARNINGS="${WARNINGS}Disk is ${DISK_PCT}% full. "
  DISK_STYLE="border-color:#f87171;"
fi
if [ "$NGINX_OK" -eq 0 ]; then
  WARNINGS="${WARNINGS}Nginx is not running. "
  NGINX_STYLE="border-color:#f87171;"
fi

if [ -n "$WARNINGS" ]; then
  STATE_NOW="warning"
  BADGE="Warning"
  BADGE_STYLE="background:rgba(248,113,113,0.15);color:#f87171;"
  WARN_BOX="<div class=\"box\" style=\"border-color:#f87171;margin-bottom:18px;\"><span class=\"num\" style=\"background:none;color:#f87171;-webkit-text-fill-color:#f87171;\">WARNING</span><p style=\"color:#fecaca;font-weight:600;margin-top:6px;\">$WARNINGS</p></div>"
else
  STATE_NOW="ok"
  BADGE="All systems OK"
  BADGE_STYLE=""
  WARN_BOX=""
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
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/style.css">
</head>
<body>

  <header class="navbar">
    <a href="/index.html" class="logo">ROBIN<span>.</span></a>
    <nav>
      <a href="/index.html#home">Home</a>
      <a href="/index.html#team">Team</a>
      <a href="/index.html#pipeline">Pipeline</a>
      <a href="/index.html#release">Release</a>
      <a href="/live/status.html" class="live">Telemetry</a>
      <a href="/live/report.html" class="live">Traffic</a>
    </nav>
  </header>

  <section class="hero" style="padding-bottom:30px;">
    <span class="hero-tag">Live telemetry</span>
    <h1><span>Server Status</span></h1>
    <p>Refreshed every minute by a cron job on the server.</p>
    <span class="role" style="$BADGE_STYLE">$BADGE</span>
  </section>

  <section class="block" style="padding-top:20px;">
    $WARN_BOX

    <div class="steps">
      <div class="box">
        <span class="num">HOST</span>
        <h3>$HOST</h3>
        <p>Server hostname</p>
      </div>
      <div class="box">
        <span class="num">UPTIME</span>
        <h3>$UPTIME</h3>
        <p>Time since the last reboot</p>
      </div>
      <div class="box">
        <span class="num">LOAD</span>
        <h3>$LOAD</h3>
        <p>Average over 1, 5 and 15 minutes</p>
      </div>
      <div class="box">
        <span class="num">MEMORY</span>
        <h3>$MEM</h3>
        <p>RAM in use</p>
      </div>
      <div class="box" style="$DISK_STYLE">
        <span class="num">DISK</span>
        <h3>$DISK</h3>
        <p>Main disk (warns above 80%)</p>
      </div>
      <div class="box" style="$NGINX_STYLE">
        <span class="num">NGINX</span>
        <h3>$NGINX</h3>
        <p>Web server status</p>
      </div>
      <div class="box">
        <span class="num">LIVE RELEASE</span>
        <h3 style="word-break:break-all;">$RELEASE</h3>
        <p>Version currently served</p>
      </div>
    </div>

    <div class="box" style="margin-top:18px;">
      <span class="num">LAST 5 DEPLOYS</span>
      <p style="white-space:pre-wrap;font-family:ui-monospace,Menlo,monospace;font-size:12px;margin-top:10px;">$DEPLOYS</p>
    </div>
  </section>

  <footer class="footer">
    <h2>TEAM ROBIN</h2>
    <p>Page written: $NOW</p>
    <p class="version">This page refreshes itself every 30 seconds</p>
  </footer>

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