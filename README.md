# cf-ddns

Cloudflare DDNS updater that reports the **public IP of a specific network interface**.

Unlike oznu/cloudflare-ddns, it uses `curl --interface` so multi-homed hosts can pin
which interface's egress public IP gets published.

## How it works

1. `curl --interface $INTERFACE https://api.ipify.org` → public IP for that interface's path
2. Look up zone + A record via Cloudflare API
3. `PUT` (or create) the record only when the IP changed
4. Repeat on `$CRON` schedule (busybox crond)

## Requirements

- `network_mode: host` — needed so `--interface` sees the real host interfaces
- Cloudflare **API token** with `Zone:DNS:Edit` + `Zone:Read` on the target zone

## Environment variables

| Var          | Required | Default                              | Notes                              |
|--------------|----------|--------------------------------------|------------------------------------|
| `API_KEY`    | yes      | —                                    | Cloudflare API token (Bearer)      |
| `ZONE`       | yes      | —                                    | e.g. `arrakis.net`                 |
| `SUBDOMAIN`  | no       | *(empty = apex)*                     | e.g. `muaddib` → `muaddib.arrakis.net` |
| `INTERFACE`  | no       | `eth1`                               | interface to read public IP from   |
| `CF_API`     | no       | `https://api.cloudflare.com/client/v4` | API base URL                     |
| `CRON`       | no       | `*/5 * * * *`                        | update schedule                    |
| `PROXIED`    | no       | `false`                              | Cloudflare orange-cloud            |
| `RECORD_TTL` | no       | `120`                                | 60–86400, or `1` for auto          |
| `IP_SERVICES`| no       | ipify, ifconfig.me, icanhazip, aws   | space-separated reflectors, tried in order |
| `IP_SERVICE` | no       | —                                    | single reflector (legacy; overrides list)  |

## Usage

```bash
# edit env in docker-compose.yml first
docker compose up -d --build
docker compose logs -f
```
