# Athena wireless diagnostic firmware

The temporary diagnostic build keeps the same ImmortalWrt 25.12.2 release,
Linux 6.12.103, NSS donor, Wi-Fi backports, firmware, and Athena board support.
It enables ath11k debug logging and tracepoints, mac80211 debugfs, dynamic
debug, kernel symbols, and `tcpdump-mini`. The normal image does not enable
ath11k debug logging, tracing, or `tcpdump-mini`.

## Capture a failure

Run these commands while the JET5 station is associated but the router cannot
reach the upstream network:

```sh
athena-debug-capture enable-reg
tcpdump -ni phy2-sta0 -nn -tttt 'arp or icmp or port 53'
```

To stream ath11k trace events in another session, first select the available
event names listed in `wireless-trace-events.txt` and enable only those events
under `/sys/kernel/debug/tracing/events/ath11k/`. For example, if the driver
provides a `ath11k:ath11k_log_warn` event:

```sh
echo 1 > /sys/kernel/debug/tracing/events/ath11k/ath11k_log_warn/enable
cat /sys/kernel/debug/tracing/trace_pipe
```

In another session, reproduce the failure (for example, ping the gateway and
query DNS). Stop tcpdump with Ctrl-C, then collect the driver and system state:

```sh
athena-debug-capture capture
athena-debug-capture disable-reg
```

The capture command prints the archive path under `/tmp`. Download that archive
before rebooting; `/tmp` is volatile. The debug mask enables only ath11k's
regulatory category (`ATH11K_DBG_REG`, `0x0200`) and can be restored with the
disable command. A reboot also clears this runtime mask.

The archive omits `/etc/config/wireless` so it does not collect the Wi-Fi
password. It contains interface names, BSSIDs, IP addresses, firewall rules,
and logs. Review it before sharing. A packet capture may contain DNS names, so
only save or share it when needed.

The release's `athena-debug-symbols.tar.zst` contains the matching unstripped
kernel and wireless modules for offline symbolization. Do not install those
symbol files on the router.
