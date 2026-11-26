#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
log "preflight checks run in both modes (no writes regardless)"
[[ "$(lsb_release -rs)" == "26.04" ]] && ok "Ubuntu 26.04" || drift "need Ubuntu 26.04 (resolute)"
# TZ: $H-based as-of timestamps are LOCAL time - fleet pins UTC everywhere
[[ "$(timedatectl show -p Timezone --value)" == "Etc/UTC" || "$(timedatectl show -p Timezone --value)" == "UTC" ]] \
&& ok "host TZ is UTC" || {
    drift "host TZ not UTC - as-of math will skew"; [[ "$MODE" == "apply" ]] && timedatectl set-timezone UTC; }
do_ "guest TZ is UTC" lxc exec "ils" -- bash -c 'timedatectl show -p Timezone --value 2>/dev/null | grep -qx "Etc/UTC"'
ram_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
[[ $ram_kb -ge 31000000 ]] && ok "RAM >= 32GB" || drift "RAM ${ram_kb}KB below 32GB"
free_disk_gb=$(df -BG --output=avail /var | tail -1 | tr -dc '0-9')
[[ $free_disk_gb -ge 200 ]] && ok "free disk >= 200GB" || drift "free disk ${free_disk_gb}GB"
# LUKS is a pre-provisioning, MANUAL, filesystem-setup-time step: cannot be
# applied by script after data exists. Check the ydb target specifically:
YDB_SRC="/var/lib/ils/ydb"
ydb_dev=$(findmnt -no SOURCE "$YDB_SRC" 2>/dev/null || true)
if [[ "$ydb_dev" == /dev/mapper/* ]] \
&& cryptsetup isLuks --type luks2 "$ydb_dev" 2>/dev/null; then
    ok "ydb path $YDB_SRC on LUKS2 ($ydb_dev)"
else
    drift "ydb path not on LUKS2 - create BEFORE data (manual disk-setup step)"
fi
# Key hygiene: >=2 keyslots (passphrase + second), clevis binding present.
if [[ -n "$ydb_dev" ]]; then
    slots=$(cryptsetup luksDump "$ydb_dev" 2>/dev/null | grep -cE '^\s*[0-9]+: luks2')
    [[ $slots -ge 2 ]] && ok "keyslots >= 2 (${slots})" || drift "keyslots ${slots} < 2 (add second passphrase)"
    if clevis luks status "$ydb_dev" >/dev/null 2>&1; then ok "clevis binding present (Tang unlock)"
    else drift "no clevis binding - manual 'clevis-luks bind' at disk setup (or intentional)"; fi
fi
finish
