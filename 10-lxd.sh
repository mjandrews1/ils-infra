#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
do_ "lxd initialized" lxc storage list
do_ "profile 'ils' exists" lxc profile show "$ILS_CT"
if [[ "$MODE" == "apply" ]] && ! lxc profile show "$ILS_CT" >/dev/null 2>&1; then
    lxc profile create "$ILS_CT"
    cat << 'EOF' | lxc profile edit "$ILS_CT"
name: ils
description: meshgraph ils (yotta + tarantool co-located, FFI path)
config:
  limits.mem: 28GB  # leave 4GB for host/m1-build
  limits.mem.lock: "true"  # mlock for yotta db + tarantool memtx
  security.nesting: "true"  # required for LUKS-less overlay + ufw inside
  raw.lxc: |
    lxc.prlimit.nofile=1048576
devices:
  ydbdisk:
    type: disk
    path: /var/lib/yottadb
    source: /var/lib/ils/ydb  # dedicated fs (put this on LUKS at disk setup)
EOF
    log "profile created; see 00-preflight note re LUKS for /var/lib/ils/ydb"
fi
do_ "container '$ILS_CT' running" bash -c 'lxc list --format csv -c n s | grep -q "^ils,RUNNING"'
if [[ "$MODE" == "apply" ]] && ! lxc list -c n | grep -qw "$ILS_CT"; then
    lxc launch ubuntu:26.04 "$ILS_CT" --profile default --profile "$ILS_CT"
fi
# Boot-decryption ordering: if the LUKS data device is slow/unavailable at boot
# (clevis stall, Tang down, typo'd passphrase), the node must NOT start a
# half-alive ils container against a missing ydbdisk. Order lxd after the mount.
D=/etc/systemd/system/lxd.service.d
do_ "lxd mounts-after-ydb drop-in" test -f "$D/ils-ydb-order.conf"
# LAYERING (explicit): LUKS + clevis live on the HOST block device
# (/dev/mapper/... -> host /var/lib/ils/ydb). The guest's /var/lib/yottadb is
# this host path via disk passthrough - the guest NEVER sees cryptsetup/LUKS.
# All LUKS/clevis checks in this repo therefore run host-side (no lxc exec);
# guest-side checks (lxc exec ...) are for software and services only.
if [[ "$MODE" == "apply" ]] && [[ ! -f "$D/ils-ydb-order.conf" ]]; then
    mkdir -p "$D"
    cat > "$D/ils-ydb-order.conf" <<'EOF'
[Unit]
# ydb mount unit name: systemd escaping of /var/lib/ils/ydb
After=var-lib-ils-ydb.mount
Requires=var-lib-ils-ydb.mount
EOF
    systemctl daemon-reload
fi
finish
