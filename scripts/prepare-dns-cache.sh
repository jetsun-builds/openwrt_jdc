#!/usr/bin/env bash
# Keep DNS cache lifetimes faithful to upstream TTLs, including short DDNS TTLs.
set -euo pipefail

BUILDER_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_DIR=${1:?Usage: prepare-dns-cache.sh SOURCE_DIR}
defaults="$SOURCE_DIR/package/network/services/dnsmasq/files/dhcp.conf"

test -f "$defaults"
# Fix the packaged defaults for fresh installs and factory resets. Do not impose
# a global TTL cap or change the cache size, DHCP settings or DNS servers.
sed -i -E '/^[[:space:]]*option[[:space:]]+(min_cache_ttl|mini_ttl|use_stale_cache)[[:space:]]/d' "$defaults"

# A sysupgrade can restore the previous /etc/config/dhcp over these defaults.
install -D -m 0755 "$BUILDER_ROOT/scripts/uci-defaults/99-dns-cache-ttl" \
  "$SOURCE_DIR/files/etc/uci-defaults/99-dns-cache-ttl"

if grep -Eq '^[[:space:]]*option[[:space:]]+(min_cache_ttl|mini_ttl|use_stale_cache)[[:space:]]' "$defaults"; then
  echo 'Unexpected DNS TTL extension remains in the packaged defaults.' >&2
  exit 1
fi
