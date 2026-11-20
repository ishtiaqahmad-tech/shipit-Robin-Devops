#!/bin/bash
# traffic-report.sh - writes /var/www/TEAM/live/report.html (A12)
# Reads the Nginx access log. Runs every 5 minutes from the deploy user's crontab.

# Load TEAM from team.conf (same folder as this script)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/team.conf"
TEAM="${TEAM:-${TEAM_NAME:-robin}}"

BASE="/var/www/$TEAM"
LOG="/var/log/nginx/$TEAM.access.log"
OUT="$BASE/live/report.html"
TMP="$OUT.tmp"
FILT=$(mktemp)
trap 'rm -f "$FILT"' EXIT

mkdir -p "$BASE/live"
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')

# ---- Read the log, leaving out /live/ pages ----
# Nginx "combined" format: $1 = IP, $7 = path, $9 = status code
if [ -r "$LOG" ]; then
  awk '$7 !~ /^\/live(\/|$)/' "$LOG" > "$FILT"
  LOG_NOTE=""
else
  : > "$FILT"
  LOG_NOTE="Cannot read $LOG yet."
fi

TOTAL=$(awk 'END {print NR+0}' "$FILT")
TOTAL_404=$(awk '$9 == 404 {n++} END {print n+0}' "$FILT")

TOP_PAGES=$(awk '$9 != 404 {print $7}' "$FILT" | sort | uniq -c | sort -rn | head -5)
TOP_IPS=$(awk '{print $1}' "$FILT" | sort | uniq -c | sort -rn | head -5)
TOP_404=$(awk '$9 == 404 {print $7}' "$FILT" | sort | uniq -c | sort -rn | head -5)

# Turn "count value" lines into table rows (values are escaped so they cannot inject HTML)
rows() {
  if [ -z "$1" ]; then
    echo '<tr><td colspan="2">No data yet</td></tr>'
  else
    echo "$1" | awk '{
      c = $1; $1 = ""; sub(/^ /, "")
      gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;"); gsub(/"/, "\\&quot;")
      printf "<tr><td>%s</td><td class=\"n\">%s</td></tr>\n", $0, c
    }'
  fi
}

PAGES_ROWS=$(rows "$TOP_PAGES")
IPS_ROWS=$(rows "$TOP_IPS")
MISSING_ROWS=$(rows "$TOP_404")

if [ -n "$LOG_NOTE" ]; then
  NOTE_HTML="<div class=\"box\" style=\"border-color:#f87171;margin-bottom:18px;\"><p style=\"color:#fecaca;font-weight:600;\">$LOG_NOTE</p></div>"
else
  NOTE_HTML=""
fi

# ---- Write the page (temp file first, then move, so it is never half-written) ----
cat > "$TMP" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>$TEAM traffic report</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/style.css">
  <style>
    table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 14px; }
    td { padding: 8px 0; border-bottom: 1px solid var(--glass-border); color: var(--muted); word-break: break-all; }
    tr:last-child td { border-bottom: 0; }
    td.n { text-align: right; color: var(--text); font-weight: 600; white-space: nowrap; padding-left: 12px; }
    .big { font-size: 2.2rem; font-weight: 800; margin: 6px 0; }
  </style>
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
    <span class="hero-tag">Live traffic</span>
    <h1><span>Traffic Report</span></h1>
    <p>Built from the Nginx access log every 5 minutes. Requests for /live/ pages are not counted.</p>
  </section>

  <section class="block" style="padding-top:20px;">
    $NOTE_HTML

    <div class="steps" style="margin-bottom:18px;">
      <div class="box">
        <span class="num">TOTAL REQUESTS</span>
        <div class="big">$TOTAL</div>
        <p>All requests to the website</p>
      </div>
      <div class="box">
        <span class="num">404 NOT FOUND</span>
        <div class="big">$TOTAL_404</div>
        <p>Requests for pages that do not exist</p>
      </div>
    </div>

    <div class="steps">
      <div class="box">
        <span class="num">TOP 5 PAGES</span>
        <table>$PAGES_ROWS</table>
      </div>
      <div class="box">
        <span class="num">TOP 5 VISITORS (IP)</span>
        <table>$IPS_ROWS</table>
      </div>
      <div class="box">
        <span class="num">TOP 5 MISSING PAGES</span>
        <table>$MISSING_ROWS</table>
      </div>
    </div>
  </section>

  <footer class="footer">
    <h2>TEAM ROBIN</h2>
    <p>Report written: $NOW</p>
    <p class="version">Updated every 5 minutes</p>
  </footer>

</body>
</html>
EOF
mv "$TMP" "$OUT"