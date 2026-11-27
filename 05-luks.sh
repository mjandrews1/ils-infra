#!/usr/bin/env bash
# The one destructive-capable script in the repo, so its safety posture is
# stricter: --check only verifies state; apply requires BOTH the normal
# apply mode AND full-disk emptiness proof, and prints the target + size for
# a typed YES before touching anything. Runs on the container HOST.
source "$(dirname "$0")/common.sh"; require_root
# Target is passed explicitly, never guessed: ./05-luks.sh --apply <partition>
PART="${2:-}"; MOUNT="/var/lib/ils/ydb"; MAP="ils-ydb"
[[ -n "$PART" ]] || { log "usage: $0 --check|--apply <partition>"; exit 2; }
# --- emptiness proof (the guard that makes this script allowed to exist) ---
is_empty_part() {
    blkid "$PART" >/dev/null 2>&1 && return 1   # any filesystem/sig = refuse
    lsblk -no MOUNTPOINTS "$PART" | grep -q . && return 1   # mounted = refuse
    # -v disables od's '*' repeat-compression, which otherwise reads as a
    # non-zero line and refuses a genuinely empty volume (bug found live, Nov 26 2026)
    dd if="$PART" bs=4096 count=1 2>/dev/null | od -An -tx1 -v | grep -qv 00 && return 1
    return 0   # first 4K all zeros
}
echo "--- target: $PART ($(lsblk -no SIZE "$PART")) ---"
if [[ "$MODE" == "check" ]]; then
    if findmnt -no SOURCE "$MOUNT" | grep -q "^/dev/mapper/$MAP"; then
        ok "$MOUNT mounted on /dev/mapper/$MAP"
        cryptsetup isLuks --type luks2 "$PART" && ok "LUKS2 header present" || drift "no LUKS2 on $PART"
        # luksDump indents keyslot lines; match optional leading whitespace
        # (bare ^[0-9] matched nothing -> false "keyslots < 2"; found live Nov 26 2026)
        [[ $(cryptsetup luksDump "$PART" | grep -cE '^\s*[0-9]+: luks2') -ge 2 ]] && ok "keyslots >= 2" || drift "keyslots < 2"
        clevis luks status "$PART" >/dev/null 2>&1 && ok "clevis bound" || drift "clevis not bound"
        grep -q "^$MAP" /etc/crypttab && ok "crypttab entry" || drift "no crypttab entry"
        grep -q "$MOUNT" /etc/fstab && ok "fstab entry" || drift "no fstab entry"
    else
        drift "$MOUNT not unlocked/mounted (expected BEFORE first apply -- see ritual)"
    fi
    finish; exit 0
fi
# --- apply mode = the manual ritual, scripted but gated ---
if findmnt "$MOUNT" >/dev/null; then
    log "already mounted; nothing to do"; exit 0; fi
is_empty_part || { log "REFUSED: $PART not provably empty (filesystem/mount/nonzero bytes). Manual review required."; exit 3; }
log "emptiness proof passed. This will LUKS-format $PART."
read -rp "Type YES to continue: " a; [[ "$a" == "YES" ]] || { log "aborted"; exit 4; }
# luksFormat prompts for the slot-0 passphrase interactively with its own
# Verify pass (that IS the double-entry). No piped stdin: cryptsetup refuses
# prompts on a pipe (bug found live Nov 26 2026).
cryptsetup luksFormat --type luks2 "$PART"
cryptsetup luksOpen "$PART" "$MAP"
mkfs.ext4 "/dev/mapper/$MAP"
mkdir -p "$MOUNT"
# Idempotent appends (belt-and-suspenders, Nov 27 2026: an interrupted apply
# re-run must not duplicate fstab/crypttab lines, which would turn a clean
# boot into a rescue shell on duplicate mount units):
file_contains /etc/crypttab "$MAP $PART" || echo "$MAP $PART none luks,discard" >> /etc/crypttab
file_contains /etc/fstab "/dev/mapper/$MAP $MOUNT" || echo "/dev/mapper/$MAP $MOUNT ext4 defaults 0 2" >> /etc/fstab
systemctl daemon-reload    # fstab changed: systemd must regenerate the mount unit
mount "$MOUNT"
# Second keyslot (out-of-band recovery), added interactively: it prompts for
# the existing passphrase, then the new household-recovery one, twice.
cryptsetup luksAddKey "$PART"
# Header backup - the one irreplacable artifact; goes OFF this machine:
cryptsetup luksHeaderBackup "$PART" --header-backup-file "/root/${MAP}-header-$(date -Is).img"
log "header backup written to /root - MOVE IT to storage/another machine and record it (do not leave a copy here)"
log "next: ./45-clevis.sh apply to bind to desktop's Tang"
# --- post-apply self-verification (belt-and-suspenders, Nov 27 2026:
# the ritual proves ITSELF before declaring success) ---
slots=$(cryptsetup luksDump "$PART" | grep -cE '^\s*[0-9]+: luks2')
if [[ $slots -lt 2 ]]; then log "post-apply FAILED: keyslots=$slots < 2"; exit 5; fi
ok "post-apply: keyslots >= 2 ($slots)"
findmnt -no SOURCE "$MOUNT" | grep -q "^/dev/mapper/$MAP$" && ok "post-apply: mounted" \
    || { log "post-apply FAILED: $MOUNT not on /dev/mapper/$MAP"; exit 5; }
finish
