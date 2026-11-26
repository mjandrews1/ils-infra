#!/usr/bin/env bash
# Canonical time for the whole fleet: UTC everywhere, same NTP sources
# everywhere, and a self-published offset metric that makes skew VISIBLE.
# Runs on all 5 minis (and container additionally fixes its LXD guest).
# Same upstream sources on every node = intra-fleet skew bounded by
# construction; no LAN stratum server (a SPOF that buys nothing at n=5).
source "$(dirname "$0")/common.sh"; require_root
# --- timezone: UTC is a binding design requirement (as-of $H math) ---
do_ "TZ is UTC" bash -c '[[ "$(timedatectl show -p Timezone --value)" == "Etc/UTC" || "$(timedatectl show -p Timezone --value)" == "UTC" ]]'
[[ "$MODE" == "apply" ]] && timedatectl set-timezone UTC
# --- chrony: same sources on every node ---
do_ "chrony installed" dpkg -s chrony >/dev/null
[[ "$MODE" == "apply" ]] && apt-get install -y chrony
SRC=/etc/chrony/sources.d/meshgraph.sources # TODO-verify sources.d support on 26.04 chrony
do_ "meshgraph NTP sources present" test -f "$SRC"
if [[ "$MODE" == "apply" ]] && [[ ! -f "$SRC" ]]; then
    mkdir -p /etc/chrony/sources.d /etc/chrony/conf.d
    cat > "$SRC" <<'EOF'
# meshgraph fleet time: identical set on every node (do NOT diverge per node)
pool 2.ubuntu.pool.ntp.org iburst maxsources 4
pool 3.ubuntu.pool.ntp.org iburst maxsources 4
server time.cloudflare.com iburst
EOF
    chmod 644 "$SRC"
    printf '%s\n' "makestep 1.0 3" "rtcsync" > /etc/chrony/conf.d/meshgraph.conf
    systemctl restart chrony
fi
do_ "chrony active" systemctl is-active chrony
sleep 2
do_ "at least one synced source" chronyc -N tracking | grep -q "Stratum"
do_ "synchronized (not init)" bash -c '! chronyc tracking | grep -qi "Not synchronised"'
# --- container special case: fix the guest too (its $H feeds the ILS) ---
if hostname | grep -qx container; then
    do_ "guest TZ is UTC" lxc exec ils -- bash -c 'timedatectl show -p Timezone --value | grep -qx "Etc/UTC"'
    [[ "$MODE" == "apply" ]] && lxc exec ils -- timedatectl set-timezone UTC || true
    do_ "guest chrony active" lxc exec ils -- systemctl is-active chrony
fi
# --- skew monitoring: publish offset as a metric via the textfile dir ---
TEXTFILE=/var/lib/prometheus-node-exporter/textfile
do_ "skew probe timer active" systemctl is-active meshgraph-skew.timer
if [[ "$MODE" == "apply" ]] && ! systemctl is-active meshgraph-skew.timer >/dev/null 2>&1; then
    mkdir -p "$TEXTFILE" /usr/local/sbin
    cat > /usr/local/sbin/meshgraph-skew.sh << 'EOF'
#!/usr/bin/env bash
# Emits chrony offset so a drifting node is caught by data, not by a user.
off=$(chronyc tracking | awk '/System time/ {print ($4=="slow" ? -1 : 1)*$3}') # ms
sync=$(chronyc tracking | grep -qi "Not synchronised" && echo 0 || echo 1)
printf 'meshgraph_ntp_offset_ms %s\nmeshgraph_ntp_synced %s\n' "${off:-0}" "$sync" \
> /var/lib/prometheus-node-exporter/textfile/meshgraph_skew.prom
EOF
    chmod +x /usr/local/sbin/meshgraph-skew.sh
    cat > /etc/systemd/system/meshgraph-skew.service <<'EOF'
[Unit]
Description=publish chrony offset for node_exporter
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/meshgraph-skew.sh
EOF
    cat > /etc/systemd/system/meshgraph-skew.timer <<'EOF'
[Unit]
Description=skew probe every minute
[Timer]
OnCalendar=*:0/1
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload && systemctl enable --now meshgraph-skew.timer
fi
# ALERT RULE (Phase 4, on desktop's Prometheus, stated here so it
# isn't reinvented): abs(meshgraph_ntp_offset_ms) > 50 for 5m, or
# meshgraph_ntp_synced == 0 for 5m -> page. 50ms is far tighter than
# any real need ($H is 1s precision); the threshold at 50ms means you
# hear about drift LONG before as-of math could mislead anyone.
finish
