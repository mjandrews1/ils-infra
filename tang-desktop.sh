#!/usr/bin/env bash
# RUNS ON desktop - the one script in this set whose target is NOT container.
# Design placement: Tang on the observability node (always-on obligation, no
# WAN exposure, tailnet-only). Tang stores no keys; desktop compromise does
# not leak unlock material by itself.
source "$(dirname "$0")/common.sh"; require_root
TANG_PORT="8060" # NOT 80/443: never on bouncer's public surface
do_ "tang installed" dpkg -s tang >/dev/null
[[ "$MODE" == "apply" ]] && apt-get install -y tang || true
do_ "tang port bound to tailscale only" bash -c 'systemctl cat tangd.socket 2>/dev/null | grep -q "$0"' "$TANG_PORT"
if [[ "$MODE" == "apply" ]]; then
    # Bind tangd to port 8060 on the tailscale interface ONLY (TODO-verify
    # socket-override syntax; ufw also gates: allow in on tailscale0 to tangd)
    systemctl edit tangd.socket --force <<EOF
[Socket]
ListenStream=
ListenStream=$(tailscale ip -4):$TANG_PORT
EOF
    systemctl enable --now tangd.socket
fi
do_ "ufw allows tangd only from container" bash -c 'ufw status | grep -q "8060.*ALLOW.*tailscale0"'
[[ "$MODE" == "apply" ]] && ufw allow in on tailscale0 to any port "$TANG_PORT" proto tcp comment 'tang for container' || true
do_ "tangd answering" curl -sf "http://$(tailscale ip -4):$TANG_PORT/adv" >/dev/null
finish
