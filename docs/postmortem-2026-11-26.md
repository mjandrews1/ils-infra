# Postmortem: container from-scratch rebuild — 2026-11-26

## Summary

During the lv_ydb disk-carving operation (shrink root, then new p3, then LVM),
the resize produced filesystem bitmap read errors in the same regions. dmesg
showed ZERO I/O errors, so the drive was exonerated and the failure judged
software-side (geometry/metadata mess from the resize; exact cause academic).
Decision: scratch the host and rebuild from scratch, eliminating the shrink
surgery entirely — the fresh install carves p1/p2/p3 correctly at install time.

## Timeline (UTC)

- Nov 25 09:43 — m1-build exported to storage vault
  (m1-build-2026-11-25-0943.tar.gz, 2.86G, mark-readable 664 in
  /srv/ils-restic). This export is why the day ended well.
- Nov 26 — shrink surgery abandoned on bitmap read errors; dmesg count = 0.
- Nov 26 — fresh Ubuntu Server 26.04 install: p1 EFI 512M, p2 XFS root 174G,
  p3 free (~290G).
- LXD initialized (lxd init --auto, dir pool "default"). LVM: vg_ils on p3,
  lv_ydb 250G, 40G vinyl-grow headroom. blkdiscard.
- m1-build restored: scp straight from the vault (no sudo — exports are
  mark-owned), lxc import, RUNNING.
- 05-luks.sh apply on lv_ydb: LUKS2, ext4, /var/lib/ils/ydb mounted, dual
  keyslots, crypttab + fstab. Header backup verified LUKS2 magic
  byte-for-byte, stored on desktop in recovery_codes, zero copies on
  container.

## What the incident proved

1. Export-before-surgery discipline paid in full. The backup executed hours
   before anything went wrong is the only reason the rebuild was an
   inconvenience instead of a disaster.
2. The vault export is mark-readable (664) — the canonical restore path is a
   single scp, no sudo, no tty problems. The sudo-cat staging dance was never
   needed for reading.
3. Scripts that live only in a PDF are not infrastructure. The founding
   commit of this repo is the fix.

## Script bugs found by first real execution (all fixed in this repo)

1. 05-luks.sh emptiness probe: od -An -tx1 compresses repeated zero lines to
   a single "*", which "grep -qv 00" read as data — false REFUSED on an empty
   volume. Fix: od -An -tx1 -v.
2. 05-luks.sh piped a passphrase into "cryptsetup luksAddKey"; cryptsetup
   refuses prompts on a pipe ("Nothing to read on input"). Fix: luksFormat's
   own interactive double-entry sets slot 0; slot 1 is added interactively.
3. Keyslot count grep "^[0-9]*: luks2" matched nothing because luksDump
   indents slot lines — false "keyslots < 2". Fix: match optional leading
   whitespace, in both 05-luks.sh and 00-preflight.sh.
4. Assorted OCR/fragment artifacts from the PDF draft cleaned up. Operator
   detour: a root password was set during a "su -" confusion mid-incident;
   re-locked with "sudo passwd -l root" afterward.

## Operational stumbles (all caught by errors, none by silent damage)

- lxc import attempted on storage (wrong machine; snap LXD half-installed
  there, then removed).
- lxc import attempted on container before lxd init ("No root disk device").
- sudo over ssh without a tty (twice) — resolved by discovering the vault is
  mark-readable.
- Header backup briefly existed nowhere (source copies deleted before the
  destination copy was verified) — retaken from the healthy live header.
  Lesson: verify the destination copy exists before deleting the source.

## Open items

- Restore drill (import as m1-build-restore-test from the same tarball) still
  to be run.
- 45-clevis.sh + desktop Tang: the "clevis not bound" drift in 05-luks --check
  is expected until then.
- 10-lxd.sh onward through the run order.
- Repo visibility: public today (no secrets by contract); flip to private if
  topology exposure becomes a concern.
