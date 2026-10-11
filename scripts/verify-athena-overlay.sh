#!/usr/bin/env bash
# Check the shipped rootfs and run its ARM64 mkfs tools on disposable images.
set -euo pipefail

source_path=${1:?Usage: verify-athena-overlay.sh SOURCE_PATH DIAGNOSTICS_DIR}
diagnostics_dir=${2:?Usage: verify-athena-overlay.sh SOURCE_PATH DIAGNOSTICS_DIR}
image_dir="$source_path/bin/targets/qualcommax/ipq60xx"
images=("$image_dir"/*jdcloud_re-cs-02-squashfs-factory.bin)
test "${#images[@]}" -eq 1
test -f "${images[0]}"
test_dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/athena-overlay-check.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
root_dir="$test_dir/rootfs"
mkdir -p "$diagnostics_dir"

# Device/jdcloud_re-cs-02 pads the kernel to 6144 KiB before SquashFS.
unsquashfs -no-progress -d "$root_dir" -o $((6144 * 1024)) "${images[0]}"
test -x "$root_dir/usr/sbin/mkfs.f2fs"
test -x "$root_dir/usr/sbin/fsck.f2fs"
test -x "$root_dir/usr/sbin/mkfs.ext4"
test -x "$root_dir/usr/bin/sgdisk"
test -n "$(find "$root_dir/lib/modules" -name 'f2fs.ko*' -print -quit)"
grep -RFxq f2fs "$root_dir/etc/modules-boot.d"

# Use the actual target binaries and libraries, not the runner's mkfs tools.
truncate -s 8G "$test_dir/expanded-overlay.img"
qemu-aarch64-static -L "$root_dir" "$root_dir/usr/sbin/mkfs.f2fs" \
  -q -f -l rootfs_data "$test_dir/expanded-overlay.img" \
  2>&1 | tee "$diagnostics_dir/overlay-f2fs-mkfs.log"
qemu-aarch64-static -L "$root_dir" "$root_dir/usr/sbin/fsck.f2fs" \
  -f "$test_dir/expanded-overlay.img" </dev/null \
  2>&1 | tee "$diagnostics_dir/overlay-f2fs-fsck.log"
truncate -s 60M "$test_dir/stock-overlay.img"
qemu-aarch64-static -L "$root_dir" "$root_dir/usr/sbin/mkfs.ext4" \
  -q -F -L rootfs_data "$test_dir/stock-overlay.img" \
  2>&1 | tee "$diagnostics_dir/overlay-ext4-mkfs.log"

echo 'Verified image-installed mkfs/fsck, F2FS module early loading, 8 GiB F2FS and 60 MiB ext4 formatting.'
echo 'Router boot and configuration persistence still require hardware validation.'
