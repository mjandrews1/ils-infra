#!/usr/bin/env bash
# The other half of 60-backup.sh: 60 runs on container; THIS prepares the
# target the sftp: URL names. Implements gap-audit item 3. The one manual
# step, like all secrets: container's SSH public key goes into
# /srv/ils-restic/.ssh/authorized_keys by hand (below, marked MANUAL).
source "$(dirname "$0")/common.sh"; require_root
TGT=/srv/ils-restic
# --- user: dedicated, no shell, no password login ever ---
do_ "ils user exists" id ils
[[ "$MODE" == "apply" ]] && { id ils >/dev/null 2>&1 || useradd -r -m -d "$TGT" -s /usr/sbin/nologin ils; }
do_ "restic installed" command -v restic
[[ "$MODE" == "apply" ]] && apt-get install -y restic
# --- target dir: owned by ils, mode 700 (backups are ciphertext; access still least-privilege) ---
do_ "target dir exists" test -d "$TGT"
[[ "$MODE" == "apply" ]] && { mkdir -p "$TGT/.ssh"; chown -R ils:ils "$TGT"; chmod 700 "$TGT" "$TGT/.ssh"; }
# --- key auth: MANUAL step (identity of the key is a secret-adjacent decision) ---
# on container: ssh-keygen -t ed25519 -f /etc/ils/storage_key -N ''
# then: cat /etc/ils/storage_key.pub | ssh root@storage "install -m 600 -o ils -g ils /dev/stdin $TGT/.ssh/authorized_keys"
do_ "authorized_keys present with mode 600" \
    bash -c 'test -f "$0"/.ssh/authorized_keys && stat -c "%a" "$0"/.ssh/authorized_keys | grep -qx 600' "$TGT"
# End-to-end sftp from container is verified ON container (60-backup.sh first
# run); this script cannot test it from storage itself.
log "MANUAL follow-up: verify end-to-end from container once the key is staged (sftp -o BatchMode=yes -i /etc/ils/storage_key ils@storage)"
# --- firewall: ssh only from the tailnet, never WAN (storage has no public face) ---
do_ "ufw active on storage" ufw status | grep -q "Status: active"
[[ "$MODE" == "apply" ]] && { ufw allow in on tailscale0 to any port 22 proto tcp comment 'restic/ssh from fleet only'; ufw --force enable; }
# --- restic repo init: deliberate non-action ---
# No repo init from the storage side; the repository is born on container
# (first 60-backup.sh run), since the password file (and ownership of the
# repo) lives there.
do_ "restic repo initialized (by container, not here)" test -d "$TGT/keys" || drift "repo not yet initialized (expected until first backup run from container)"
finish
