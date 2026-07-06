#!/bin/bash
set -euo pipefail

# oznu-compatible env vars
: "${API_KEY:?need API_KEY (Cloudflare API token)}"
: "${ZONE:?need ZONE (e.g. astrobunny.net)}"
SUBDOMAIN="${SUBDOMAIN:-}"
IFACE="${INTERFACE:-eth1}"
RECORD_TTL="${RECORD_TTL:-120}"
PROXIED="${PROXIED:-false}"
# Space-separated list of public-IP echo services (tried in order)
IP_SERVICES="${IP_SERVICES:-${IP_SERVICE:-https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com https://ipv4.icanhazip.com https://checkip.amazonaws.com}}"
CF_API="${CF_API:-https://api.cloudflare.com/client/v4}"

# Build FQDN: azusa + astrobunny.net -> azusa.astrobunny.net (empty sub -> apex)
if [[ -n "$SUBDOMAIN" ]]; then
  RECORD="${SUBDOMAIN}.${ZONE}"
else
  RECORD="$ZONE"
fi

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# Public IP as seen when egressing $IFACE. Try reflectors in order until one works.
IP=""
for svc in $IP_SERVICES; do
  RESP="$(curl -fsS --max-time 10 --interface "$IFACE" "$svc" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$RESP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IP="$RESP"
    log "Public IP via $IFACE: $IP  (from $svc, record: $RECORD)"
    break
  fi
  log "reflector failed/invalid: $svc"
done
if [[ -z "$IP" ]]; then
  log "ERROR: all reflectors failed via $IFACE"
  exit 1
fi

api() {
  curl -fsS -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" "$@"
}

ZONE_ID="$(api "$CF_API/zones?name=$ZONE" \
  | jq -r '.result[0].id')"
[[ "$ZONE_ID" != "null" && -n "$ZONE_ID" ]] || { log "ERROR: zone not found"; exit 1; }

REC_JSON="$(api "$CF_API/zones/$ZONE_ID/dns_records?type=A&name=$RECORD")"
REC_ID="$(echo "$REC_JSON" | jq -r '.result[0].id')"
CUR_IP="$(echo "$REC_JSON" | jq -r '.result[0].content')"

PAYLOAD="$(jq -nc --arg n "$RECORD" --arg c "$IP" --argjson t "$RECORD_TTL" \
  --argjson p "$PROXIED" '{type:"A",name:$n,content:$c,ttl:$t,proxied:$p}')"

if [[ "$REC_ID" == "null" || -z "$REC_ID" ]]; then
  log "Creating record $RECORD -> $IP"
  api -X POST "$CF_API/zones/$ZONE_ID/dns_records" \
    --data "$PAYLOAD" >/dev/null
elif [[ "$CUR_IP" != "$IP" ]]; then
  log "Updating record $RECORD: $CUR_IP -> $IP"
  api -X PUT "$CF_API/zones/$ZONE_ID/dns_records/$REC_ID" \
    --data "$PAYLOAD" >/dev/null
else
  log "No change ($CUR_IP)"
fi
