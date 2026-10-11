#!/bin/sh
# Collect non-secret ath11k, regulatory, route, and packet-path diagnostics.
set -u

MASK_FILE=/sys/module/ath11k/parameters/debug_mask
SAVED_MASK=/tmp/athena-debug-mask.original

usage() {
	cat <<'EOF'
Usage:
  athena-debug-capture enable-reg   Enable ath11k regulatory debug logging
  athena-debug-capture disable-reg  Restore the previous logging mask
  athena-debug-capture capture      Save a diagnostic archive under /tmp
EOF
}

record() {
	name=$1
	shift
	{
		printf '$'
		printf ' %s' "$@"
		printf '\n'
		"$@" 2>&1 || true
	} > "$work/$name"
}

case "${1:-}" in
enable-reg)
	if [ ! -r "$MASK_FILE" ] || [ ! -w "$MASK_FILE" ]; then
		echo "ath11k debug_mask is unavailable; confirm this is the diagnostic firmware." >&2
		exit 1
	fi
	if [ ! -f "$SAVED_MASK" ]; then
		cat "$MASK_FILE" > "$SAVED_MASK"
	fi
	# ATH11K_DBG_REG is 0x0200 in this firmware's pinned backports 7.2 source.
	printf '0x0200\n' > "$MASK_FILE"
	echo "Regulatory diagnostics enabled. Reproduce the outage, then run: athena-debug-capture capture"
	;;
disable-reg)
	if [ -f "$SAVED_MASK" ] && [ -w "$MASK_FILE" ]; then
		cat "$SAVED_MASK" > "$MASK_FILE"
		rm -f "$SAVED_MASK"
		echo "Restored the previous ath11k debug mask."
	else
		echo "No saved ath11k debug mask was found."
	fi
	;;
capture)
	stamp=$(date +%Y%m%d-%H%M%S)
	work="/tmp/athena-debug-$stamp"
	archive="$work.tar.gz"
	umask 077
	mkdir -p "$work"
	trap 'rm -rf "$work"' EXIT HUP INT TERM
	if ! grep -qs ' /sys/kernel/debug debugfs ' /proc/mounts; then
		mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
	fi

	{
		date -R
		ubus call system board
		uname -a
		cat /proc/cmdline
	} > "$work/system.txt" 2>&1
	record iw-dev.txt iw dev
	record regulatory.txt iw reg get
	record phy2-info.txt iw phy phy2 info
	record phy2-link.txt iw dev phy2-sta0 link
	record phy2-station.txt iw dev phy2-sta0 station dump
	record ip-addresses.txt ip -4 address show
	record ip-routes.txt ip -4 route show table all
	record ip-rules.txt ip -4 rule show
	record ip-neighbors.txt ip -4 neigh show
	record wwan-status.txt ubus call network.interface.wwan status
	record ath11k-debug-mask.txt cat "$MASK_FILE"
	{
		if [ -r /sys/kernel/debug/tracing/available_events ]; then
			grep -E '^(ath11k|mac80211|cfg80211):' /sys/kernel/debug/tracing/available_events || true
		fi
	} > "$work/wireless-trace-events.txt"
	record logread.txt logread
	record dmesg.txt dmesg
	record firewall.txt nft list ruleset

	{
		for dir in /sys/kernel/debug/ieee80211/phy*/ath11k; do
			[ -d "$dir" ] || continue
			printf '\n### %s\n' "$dir"
			ls -la "$dir" 2>&1
			for stat in fw_stats htt_stats; do
				[ -r "$dir/$stat" ] || continue
				printf '\n### %s/%s\n' "$dir" "$stat"
				cat "$dir/$stat" 2>&1
			done
		done
	} > "$work/ath11k-debugfs.txt"
	tar -czf "$archive" -C /tmp "athena-debug-$stamp"
	echo "Diagnostic archive created: $archive"
	echo "It includes interface names, MAC/IP addresses, firewall rules, and system logs; review it before sharing."
	;;
*)
	usage >&2
	exit 2
	;;
esac
