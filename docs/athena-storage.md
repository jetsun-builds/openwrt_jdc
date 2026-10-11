# Athena RE-CS-02: enlarged rootfs and GPT diagnosis

## Persistent overlay on an enlarged rootfs

The factory image does not contain a GPT or cap the rootfs partition at its
original 60 MiB size. `fstools` reads the root device capacity and creates a loop
device after the SquashFS image, aligned to 64 KiB. On the pinned release it
chooses F2FS for an unformatted tail larger than 100 MiB, unless the kernel
command line explicitly requests ext4.

The old build omitted `mkf2fs`, `f2fsck` and `kmod-fs-f2fs`. On the owner's
expanded device p18 was 16777216 sectors (8 GiB) and loop0 was 16743808 sectors.
Startup reported `mkfs.f2fs: not found` and fell back to `overlayfs:/tmp/root`.
That temporary RAM overlay loses configuration at reboot. The corrected build
installs the tools and early-loadable driver in the image, retaining ext4 for
small partitions. It also checks the actual factory image and runs its ARM64
formatting tools under QEMU on disposable images. This is not a hardware boot
or sysupgrade persistence test.

After flashing, check:

```sh
grep -E ' / | /overlay ' /proc/mounts
df -h /overlay
logread | grep -Ei 'mkfs|f2fs|overlay'
```

Expected: `/dev/loop0` mounted at `/overlay` as F2FS and the root overlay using
`/overlay/upper`, not `/tmp/root/upper`. The formatted overlay is slightly smaller
than 8 GiB because SquashFS and filesystem metadata use some space.

## Read-only GPT checks

No additional kernel driver is required: the running kernel already reads this
eMMC and GPT. Install the userspace `sgdisk` package (built in to the corrected
image):

```sh
apk update
apk add sgdisk
```

On a RAM overlay this installation is temporary and disappears at reboot.
Run these commands against the whole eMMC disk, not p18:

```sh
sgdisk --verify /dev/mmcblk0
sgdisk --print /dev/mmcblk0
sgdisk --info=18 /dev/mmcblk0
sgdisk --info=27 /dev/mmcblk0
dmesg | grep -Ei 'GPT|mmc|I/O error|timeout|crc'
```

`--verify`, `--print` and `--info` do not write the partition table. The checks
report primary/backup header validity, partition-entry-array CRCs, overlap and
range errors. They can locate the inconsistent copy; they cannot identify which
earlier flashing operation wrote it. A CRC mismatch may be caused by an array
updated without its CRC, an incomplete write, stale primary/backup contents,
or storage read errors. Disk/driver failure requires separate I/O evidence.

Compare the start/end LBAs and GUIDs with the JDBox expansion backup: p1-p17
should remain unchanged, p18 keeps its start and expands, p19-p26 move back
without changing size/GUID, and p27 moves its start back with its end unchanged.
Do not assume that either GPT copy is correct merely because it passes CRC.

If raw evidence is needed before repair, these reads save the first and last
1 MiB to RAM (transfer them to the computer before reboot):

```sh
dd if=/dev/mmcblk0 of=/tmp/gpt-first-1MiB.bin bs=512 count=2048
sectors=$(cat /sys/class/block/mmcblk0/size)
test "$sectors" -gt 2048 && dd if=/dev/mmcblk0 of=/tmp/gpt-last-1MiB.bin bs=512 skip=$((sectors - 2048)) count=2048
```

They do not write to eMMC. This raw capture preserves damaged headers/arrays;
`sgdisk --backup` instead saves its interpreted in-memory GPT and is not a raw
forensic capture.

Do not repair yet with `sgdisk -e`, `gdisk`'s write command or Parted's `Fix`:
first identify the correct expanded layout and preserve both copies. `-e` moves
the backup GPT to the disk end; it is not a generic cure for an incorrect array.
Never run mkfs or resize2fs against the whole p18: it contains SquashFS plus the
tail overlay. Changing p18's GPT capacity and initializing its tail filesystem
are separate operations.
