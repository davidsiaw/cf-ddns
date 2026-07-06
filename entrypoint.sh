#!/bin/bash
set -euo pipefail

# nyan default cron: every 5 min
CRON="${CRON:-*/5 * * * *}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# Export env so cron job sees it
printenv | grep -E '^(API_KEY|CF_API|ZONE|SUBDOMAIN|INTERFACE|CRON|PROXIED|RECORD_TTL|IP_SERVICE|IP_SERVICES)=' \
  | sed 's/^/export /' > /app/env.sh

CRONFILE=/etc/crontabs/root
echo "$CRON . /app/env.sh; /app/update-ddns.sh >> /proc/1/fd/1 2>&1" > "$CRONFILE"

log "cf-ddns starting: iface=${INTERFACE:-eth1} sub=${SUBDOMAIN:-} zone=${ZONE:-?} cron='$CRON'"

# Run once at startup, then hand off to cron
. /app/env.sh
/app/update-ddns.sh || log "initial update failed"

# crond in foreground
exec crond -f -l 8
