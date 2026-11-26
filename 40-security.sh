#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
# --- ufw: default-deny in, allow tailscale0, allow lo, that's all on this node ---
do_ "ufw active" bash -c 'lxc exec ils -- ufw status | grep -q "Status: active"'
if [[ "$MODE" == "apply" ]]; then
    lxc exec "$ILS_CT" -- ufw default deny incoming
    lxc exec "$ILS_CT" -- ufw default allow outgoing
    lxc exec "$ILS_CT" -- ufw allow in on tailscale0 comment 'tailnet'
    lxc exec "$ILS_CT" -- ufw allow out on tailscale0
    lxc exec "$ILS_CT" -- ufw --force enable
fi
# --- chrony: as-of timestamps are binding design elements ---
do_ "chrony active" lxc exec "$ILS_CT" -- systemctl is-active chrony
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- bash -c 'apt-get install -y chrony && systemctl enable --now chrony'
# --- memlock limits for both engines ---
LIMITS="/etc/security/limits.conf"
do_ "memlock unlimited for ils+ydb users" \
    bash -c 'lxc exec ils -- grep -q "memlock unlimited" /etc/security/limits.conf'
if [[ "$MODE" == "apply" ]]; then
    for u in ils ils-ydb; do
        printf '%s soft memlock unlimited\n%s hard memlock unlimited\n' "$u" "$u" \
            | lxc exec "$ILS_CT" -- tee -a "$LIMITS" >/dev/null
    done
fi
# --- unattended-upgrades + auditd on the ydb dir ---
do_ "unattended-upgrades active" lxc exec "$ILS_CT" -- systemctl is-active unattended-upgrades
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- bash -c 'apt-get install -y unattended-upgrades auditd'
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- bash -c 'auditctl -w /var/lib/yottadb -p r -k ils_ydb_access || true' # TODO-verify persistence rule file
do_ "auditd rule on ydb dir" lxc exec "$ILS_CT" -- ausearch -k ils_ydb_access >/dev/null 2>&1
finish
