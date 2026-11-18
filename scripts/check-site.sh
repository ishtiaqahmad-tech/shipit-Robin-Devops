#!/bin/bash
# check-site.sh - checks the website before merging (A8)
# Usage: ./scripts/check-site.sh site
# Exit 1 with a message for every problem, or print "All checks passed" and exit 0.

SITE="${1:-site}"
ERRORS=0

if [ ! -d "$SITE" ]; then
  echo "ERROR: site folder '$SITE' not found"
  exit 1
fi

# 1. Every HTML page needs a <title>
while IFS= read -r file; do
  if ! grep -qi "<title>[^<]\+</title>" "$file"; then
    echo "ERROR: $file has no <title>"
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "$SITE" -type f -name "*.html")

# 2. Links (href= or src=) to files inside the site must exist
while IFS= read -r file; do
  dir=$(dirname "$file")
  while IFS= read -r link; do
    # skip external sites, anchors, mail/tel links and /live/ pages
    case "$link" in
      http://*|https://*|//*|mailto:*|tel:*|\#*|/live/*|"") continue ;;
    esac

    path="${link%%#*}"     # remove #anchor
    path="${path%%\?*}"    # remove ?query
    [ -z "$path" ] && continue

    if [[ "$path" == /* ]]; then
      target="$SITE$path"          # absolute link: from the site root
    else
      target="$dir/$path"          # relative link: from this file's folder
    fi

    # a link to a folder uses its index.html
    if [ -d "$target" ]; then
      target="${target%/}/index.html"
    fi

    if [ ! -e "$target" ]; then
      echo "ERROR: $file links to '$link' but the file does not exist"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(grep -oE "(href|src)=\"[^\"]*\"" "$file" | sed -E 's/^(href|src)="//; s/"$//')
done < <(find "$SITE" -type f -name "*.html")

# 3. No file bigger than 1 MB
while IFS= read -r big; do
  echo "ERROR: $big is bigger than 1 MB"
  ERRORS=$((ERRORS + 1))
done < <(find "$SITE" -type f -size +1048576c)

if [ "$ERRORS" -gt 0 ]; then
  echo "$ERRORS problem(s) found"
  exit 1
fi

echo "All checks passed"
exit 0