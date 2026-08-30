set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := true

services := "caddy nextcloud uptime-kuma memos vikunja immich glance"

default:
    @just --list --unsorted

# start one or more services (default: all)
up +svcs=services:
    #!/usr/bin/env bash
    set -euo pipefail
    for s in {{svcs}}; do
      echo "==> $s"
      (cd "$s" && docker compose up -d)
    done

# stop services
down +svcs:
    #!/usr/bin/env bash
    set -euo pipefail
    for s in {{svcs}}; do
      echo "==> $s"
      (cd "$s" && docker compose down)
    done

# restart services
restart +svcs:
    #!/usr/bin/env bash
    set -euo pipefail
    for s in {{svcs}}; do (cd "$s" && docker compose restart); done

logs svc *args="--tail=100 -f":
    cd {{svc}} && docker compose logs {{args}}

# fully-rendered compose (catches missing .env vars)
config svc:
    cd {{svc}} && docker compose config

# pull + recreate
update +svcs=services:
    #!/usr/bin/env bash
    set -euo pipefail
    for s in {{svcs}}; do
      echo "==> $s"
      (cd "$s" && docker compose pull && docker compose up -d)
    done

caddy-validate:
    cd caddy && docker compose exec -w /etc/caddy caddy caddy validate --config Caddyfile

caddy-reload: caddy-validate
    cd caddy && docker compose exec -w /etc/caddy caddy caddy reload --config Caddyfile

# expiry dates for every cert Caddy is serving on the tailnet
certs:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${DOMAIN:?set DOMAIN in ~/homelab/.env}"
    : "${TAILSCALE_IP:?set TAILSCALE_IP in ~/homelab/.env}"
    for sub in nextcloud status memos vikunja photos; do
      printf '%-12s ' "$sub"
      echo | openssl s_client -connect "$TAILSCALE_IP:443" -servername "$sub.$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -enddate
    done

backup:
    sudo systemctl start homelab-backup.service

backup-status:
    systemctl status homelab-backup.service --no-pager || true
    systemctl list-timers homelab-backup.timer --no-pager

backup-log lines="100":
    sudo journalctl -u homelab-backup.service -n {{lines}} --no-pager

disk:
    df -h / /srv /srv/backup

mem:
    free -h
    @echo
    vmstat 1 5

# check for any out of memory events
oom:
    @sudo journalctl -k --since "7 days ago" | grep -iE "out of memory|oom-kill" || echo "no OOM events in the last 7 days"

top:
    docker stats --no-stream

env-backup:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -name '.env' -not -path './.git/*' -print0 \
      | tar --null -czf - -T - \
      | gpg --symmetric --cipher-algo AES256 -o env-backup.tar.gz.gpg
    echo "wrote env-backup.tar.gz.gpg"

env-restore:
    gpg -d env-backup.tar.gz.gpg | tar -xzvf -
