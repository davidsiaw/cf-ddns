#!/bin/bash
set -uo pipefail   # NOTE: no -e; we handle errors explicitly for diagnostics

# nyan env vars
: "${API_KEY:?need API_KEY (Cloudflare API token)}"
: "${ZONE:?need ZONE (e.g. arrakis.net)}"
SUBDOMAIN="${SUBDOMAIN:-}"
IFACE="${INTERFACE:-eth1}"
RECORD_TTL="${RECORD_TTL:-120}"
PROXIED="${PROXIED:-false}"
# Space-separated list of public-IP echo services (tried in order)
IP_SERVICES="${IP_SERVICES:-${IP_SERVICE:-https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com https://ipv4.icanhazip.com https://checkip.amazonaws.com}}"
CF_API="${CF_API:-https://api.cloudflare.com/client/v4}"

# Build FQDN: muaddib + arrakis.net -> muaddib.arrakis.net (empty sub -> apex)
if [[ -n "$SUBDOMAIN" ]]; then
  RECORD="${SUBDOMAIN}.${ZONE}"
else
  RECORD="$ZONE"
fi

log() { echo "[$(date -u +%FT%TZ)] $*"; }
dbg() { echo "[$(date -u +%FT%TZ)] DEBUG: $*"; }

# ---- Diagnostics: environment ----
dbg "ZONE=$ZONE SUBDOMAIN='$SUBDOMAIN' RECORD=$RECORD IFACE=$IFACE TTL=$RECORD_TTL PROXIED=$PROXIED"
dbg "CF_API=$CF_API"
dbg "API_KEY length=${#API_KEY} (first4=${API_KEY:0:4}...)"
dbg "IP_SERVICES=$IP_SERVICES"

# ---- Diagnostics: interface ----
if command -v ip >/dev/null 2>&1; then
  dbg "interfaces present:"
  ip -brief addr 2>&1 | sed 's/^/    /'
  if ! ip link show "$IFACE" >/dev/null 2>&1; then
    log "ERROR: interface '$IFACE' does not exist on this host"
    log "       (with network_mode: host, container must see the real iface name)"
  fi
else
  dbg "'ip' tool not available; skipping interface listing"
fi

# ---- Public IP via each reflector ----
IP=""
for svc in $IP_SERVICES; do
  dbg "trying reflector: curl --interface $IFACE $svc"
  RESP="$(curl -sS --max-time 10 --interface "$IFACE" "$svc" 2>/tmp/curl.err)"
  RC=$?
  ERR="$(cat /tmp/curl.err 2>/dev/null)"
  CLEAN="$(printf '%s' "$RESP" | tr -d '[:space:]')"
  if [[ $RC -ne 0 ]]; then
    log "reflector curl failed: $svc (exit=$RC) ${ERR:+-- $ERR}"
    continue
  fi
  if [[ "$CLEAN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IP="$CLEAN"
    log "Public IP via $IFACE: $IP  (from $svc, record: $RECORD)"
    break
  fi
  log "reflector returned non-IP: $svc -> '${CLEAN:0:80}'"
done
if [[ -z "$IP" ]]; then
  log "ERROR: all reflectors failed via $IFACE"
  exit 1
fi

# api CALL...; captures body+HTTP status, logs on failure. Sets API_BODY.
api() {
  local body status
  body="$(curl -sS -w $'\n%{http_code}' \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" "$@" 2>/tmp/api.err)"
  local rc=$?
  status="$(printf '%s' "$body" | tail -n1)"
  API_BODY="$(printf '%s' "$body" | sed '$d')"
  if [[ $rc -ne 0 ]]; then
    log "ERROR: curl failed (exit=$rc): $(cat /tmp/api.err 2>/dev/null)"
    return 1
  fi
  dbg "HTTP $status  <- $* "
  if [[ "$status" -ge 400 ]]; then
    log "ERROR: Cloudflare API HTTP $status"
    log "response: $API_BODY"
    return 1
  fi
  # Cloudflare success flag
  if ! printf '%s' "$API_BODY" | jq -e '.success == true' >/dev/null 2>&1; then
    log "ERROR: Cloudflare success!=true"
    log "response: $API_BODY"
    log "errors: $(printf '%s' "$API_BODY" | jq -c '.errors' 2>/dev/null)"
    return 1
  fi
  return 0
}

dbg "looking up zone id for $ZONE"
api "$CF_API/zones?name=$ZONE" || { log "ERROR: zone lookup call failed"; exit 1; }
ZONE_ID="$(printf '%s' "$API_BODY" | jq -r '.result[0].id')"
if [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]]; then
  log "ERROR: zone '$ZONE' not found in account (check token has access to this zone)"
  log "response: $API_BODY"
  exit 1
fi
dbg "ZONE_ID=$ZONE_ID"

dbg "looking up A record $RECORD"
api "$CF_API/zones/$ZONE_ID/dns_records?type=A&name=$RECORD" || { log "ERROR: record lookup call failed"; exit 1; }
REC_ID="$(printf '%s' "$API_BODY" | jq -r '.result[0].id')"
CUR_IP="$(printf '%s' "$API_BODY" | jq -r '.result[0].content')"
dbg "REC_ID=$REC_ID CUR_IP=$CUR_IP"

PAYLOAD="$(jq -nc --arg n "$RECORD" --arg c "$IP" --argjson t "$RECORD_TTL" \
  --argjson p "$PROXIED" '{type:"A",name:$n,content:$c,ttl:$t,proxied:$p}')"
dbg "payload=$PAYLOAD"

if [[ "$REC_ID" == "null" || -z "$REC_ID" ]]; then
  log "Creating record $RECORD -> $IP"
  api -X POST "$CF_API/zones/$ZONE_ID/dns_records" --data "$PAYLOAD" \
    || { log "ERROR: create failed"; exit 1; }
  log "Created OK"
elif [[ "$CUR_IP" != "$IP" ]]; then
  log "Updating record $RECORD: $CUR_IP -> $IP"
  api -X PUT "$CF_API/zones/$ZONE_ID/dns_records/$REC_ID" --data "$PAYLOAD" \
    || { log "ERROR: update failed"; exit 1; }
  log "Updated OK"
else
  log "No change ($CUR_IP)"
fi
