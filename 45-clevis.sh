#!/usr/bin/env bash
# Clevis client half on container (Tang server lives on desktop - see
# tang-desktop.sh). The BIND itself is part of the manual disk-setup ritual
# (passphrase + bind + header backup together); this script installs the
# tooling and verifies the binding stays healthy.
source "$(dirname "$0")/common.sh"; require_root
YDB_DEV=$(findmnt -no SOURCE /var/lib/ils/ydb 2>/dev/null || true)
do_ "clevis-luks installed" dpkg -s clevis-luks >/dev/null
[[ "$MODE" == "apply" ]] && apt-get install -y clevis-luks clevis-systemd 2>/dev/null || true # TODO-verify package split on 26.04
if [[ -n "$YDB_DEV" ]]; then
    do_ "clevis binding on ydb device" clevis luks status "$YDB_DEV" >/dev/null
    # End-to-end health: ask clevis to recover WITHOUT unlocking (dry run of the
    # Tang round-trip). If desktop is down this drifts - that's the signal you
    # want before any reboot, not after.
    do_ "tang round-trip reachable" clevis luks unlock -d "$YDB_DEV" -o /dev/null
    do_ "crypttab uses clevis (no plaintext keyfile)" grep -q "none" /etc/crypttab
else
    drift "ydb device not mounted; run disk setup first"
fi
finish
