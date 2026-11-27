# Disk surgery checklist (historical — from the Gen-1 PDF)

Imported verbatim from the provisioning-scripts PDF, drafted Nov 2026. At the
time, shrink-in-place was chosen to preserve m1-build mid-study; the from-
scratch rebuild of Nov 26 (see postmortem-2026-11-26.md) superseded the
surgery itself, but the RITUAL below is generation-independent and remains
the pattern for any future destructive disk operation.

## Before surgery

1. Guest hygiene: git status/push clean; then full guest export — captures
   toolchains, deploy keys, everything guest-local in one artifact:
   ```
   lxc stop <guest>
   lxc export <guest> - | ssh ils@storage "cat > /srv/ils-restic/<guest>-$(date -Is).tar.xz"
   # older LXD: export to /tmp, rsync to storage, delete local copy
   ```
2. TEST-READ the export before touching the disk:
   ```
   ssh ils@storage "tar -tjf <file> | head"
   ```
3. (Learned Nov 26, added:) vault exports are mark-owned (mode 664) — the
   canonical restore path is a single scp from the vault, no sudo, no tty.

## The surgery itself (as originally drafted)

Live USB, then: e2fsck -f on root; resize2fs shrink FIRST; parted resizepart +
mkpart; answer "fix" to the GPT backup-header prompt. Then pvcreate/vgcreate/
lvcreate; blkdiscard the fresh LV (it exposes stale bytes).

## After surgery (the ritual that always applies)

1. lxc import the export; lxc start; toolchain spot-check (prove it is the
   same machine, not just a booted shell).
2. One restore drill: import the SAME tarball as <guest>-restore-test, start,
   verify, stop, delete. The loop closes with proof, not hope.

## The lesson the checklist earned

The Nov 25 export, executed hours before anything went wrong, was the only
reason the Nov 26 bitmap-read failure ended as an inconvenience instead of a
disaster. The backup you hope is worthless is the one that works.
