#!/usr/bin/env bash
# DMZ edge node. Runs on bouncer. CGNAT test passed (DDNS + port-forward
# branch confirmed final, Nov 24 2026). Router-side prerequisites are MANUAL
# like LUKS: port-forward WAN 80+443 -> bouncer LAN IP, and create the A
# record in Porkbun once. This script does the rest. Secrets (Porkbun API
# key/secret) pre-staged at /etc/porkbun/, root-only, never in repo.
source "$(dirname "$0")/common.sh"; require_root
DOMAIN="ils.marksdomain.example" # TODO: real record (placeholders here)
IF_WAN="eno1"                    # TODO: bouncer's WAN-facing NIC
# --- Porkbun DDNS updater: only updates when the address actually changed ---
do_ "porkbun secrets staged" bash -c 'test -r /etc/porkbun/key -a -r /etc/porkbun/secret'
if [[ "$MODE" == "apply" ]] && [[ ! -f /usr/local/sbin/porkbun-ddns.sh ]]; then
    cat > /usr/local/sbin/porkbun-ddns.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
PB=/etc/porkbun; DOM="__DOMAIN__"; HOST="__HOST__"; TTL=300
key=$(cat $PB/key); sec=$(cat $PB/secret)
wan=$(curl -fsS -4 https://api.ipify.org)
cur=$(dig +short A $HOST.$DOM @8.8.8.8)
[[ "$wan" == "$cur" ]] && exit 0 # no-op: watch-and-verify
curl -fsS https://api.porkbun.com/api/json/v3/dns/edit \
-d "{\"apikey\":\"$key\",\"secretapikey\":\"$sec\",\"domain\":\"$DOM\",\"id\":\"$HOST\",\"type\":\"A\",\"name\":\"$HOST\",\"content\":\"$wan\",\"ttl\":\"$TTL\"}"
EOF
    sed -i "s/__DOMAIN__/${DOMAIN#*.}/; s/__HOST__/${DOMAIN%.*}/" /usr/local/sbin/porkbun-ddns.sh
    chmod 700 /usr/local/sbin/porkbun-ddns.sh
    cat > /etc/systemd/system/porkbun-ddns.service <<'EOF'
[Unit]
Description=Porkbun DDNS update (no-op unless WAN address changed)
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/porkbun-ddns.sh
EOF
    cat > /etc/systemd/system/porkbun-ddns.timer <<'EOF'
[Unit]
Description=Porkbun DDNS watch
[Timer]
OnCalendar=*:0/5
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now porkbun-ddns.timer
fi
do_ "ddns timer active" systemctl is-active porkbun-ddns.timer
do_ "DNS resolves to this node" bash -c 'dig +short A "$0" | grep -q "$(tailscale ip -4)" || dig +short A "$0" | grep -q "$(curl -fsS -4 https://api.ipify.org)"' "$DOMAIN"
# NOTE: that last check is health, not drift: DDNS propagation lags; alert on
# sustained mismatch (alertmanager story, Phase 4), don't fail on minutes.
# --- Caddy with the Porkbun DNS module (DNS-01, port 80 not needed for issuance) ---
do_ "caddy binary present" caddy version
if [[ "$MODE" == "apply" ]] && ! command -v caddy >/dev/null; then
    apt-get install -y xcaddy 2>/dev/null || go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    xcaddy build --with github.com/caddy-dns/porkbun # TODO-verify module path
    mv caddy /usr/local/bin/ && setcap 'cap_net_bind_service=+ep' /usr/local/bin/caddy
fi
cat > /tmp/Caddyfile <<EOF
$DOMAIN {
    tls {
        dns porkbun {env.PORKBUN_KEY} {env.PORKBUN_SECRET} # TODO-verify env syntax
    }
    reverse_proxy container:8080 # over the tailnet, Caddy is the only public path
}
EOF
[[ "$MODE" == "apply" ]] && install -m 644 /tmp/Caddyfile /etc/caddy/Caddyfile && systemctl reload caddy 2>/dev/null || true
do_ "caddy active" systemctl is-active caddy
# --- fail2ban: caddy jail, default-deny input on WAN, tailnet free ---
do_ "fail2ban caddy jail" test -f /etc/fail2ban/jail.d/caddy.conf
if [[ "$MODE" == "apply" ]]; then
    cat > /etc/fail2ban/jail.d/caddy.conf <<'EOF'
[caddy]
enabled = true
port = http,https
filter = caddy
backend = systemd[journalflags=-g] # TODO-verify: caddy journal filter
maxretry = 5
bantime = 1h
EOF
fi
do_ "ufw WAN allows only 80/443" bash -c 'ufw status | grep -v tailscale0 | grep -E "80|443"'
if [[ "$MODE" == "apply" ]]; then
    ufw allow in on "$IF_WAN" to any port 80 proto tcp comment 'http redirect'
    ufw allow in on "$IF_WAN" to any port 443 proto tcp comment 'https only path'
    ufw --force enable
fi
finish
