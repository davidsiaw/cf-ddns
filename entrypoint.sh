#!/bin/bash
set -euo pipefail

# nyan default cron: every 5 min
CRON="${CRON:-*/5 * * * *}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# Export env so cron job sees it (quote values: they contain spaces, e.g. CRON, IP_SERVICES)
: > /app/env.sh
for v in API_KEY CF_API ZONE SUBDOMAIN INTERFACE CRON PROXIED RECORD_TTL IP_SERVICE IP_SERVICES; do
  if [[ -n "${!v+x}" ]]; then
    printf 'export %s=%q\n' "$v" "${!v}" >> /app/env.sh
  fi
done

CRONFILE=/etc/crontabs/root
echo "$CRON . /app/env.sh; /app/update-ddns.sh >> /proc/1/fd/1 2>&1" > "$CRONFILE"

log "cf-ddns starting: iface=${INTERFACE:-eth1} sub=${SUBDOMAIN:-} zone=${ZONE:-?} cron='$CRON'"

# Run once at startup, then hand off to cron
. /app/env.sh
/app/update-ddns.sh || log "initial update failed"

# crond in foreground
exec crond -f -l 8
