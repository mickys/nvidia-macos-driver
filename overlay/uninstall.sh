#!/bin/bash
# Undo the mickys overlay: put back the Metal plugin binary and nvrm610.conf saved by install.sh, and remove
# libnvencvt.dylib if it was not there before.
#   sudo ./uninstall.sh [backup dir]      default: /Library/NullMoth/overlay-backup-latest
set -euo pipefail
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
BK=${1:-/Library/NullMoth/overlay-backup-latest}
[ -f "$BK/NVMTLDriver" ] && [ -f "$BK/nvrm610.conf" ] || die "no overlay backup in $BK"
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
NOW=$(cat /Library/NullMoth/driver-version 2>/dev/null || echo unknown); WAS=$(cat "$BK/driver-version" 2>/dev/null || echo unknown)
[ "$NOW" = "$WAS" ] || die "the driver changed since the backup ($WAS -> $NOW); NullMoth's installer already replaced the overlay"
install -o root -g wheel -m 755 "$BK/NVMTLDriver" "$X/NVMTLDriver"
if [ -f "$BK/libnvencvt.dylib" ]; then install -o root -g wheel -m 755 "$BK/libnvencvt.dylib" "$X/libnvencvt.dylib"
else rm -f "$X/libnvencvt.dylib"; fi
install -o root -g wheel -m 644 "$BK/nvrm610.conf" "$C"
codesign -f -s - --preserve-metadata=identifier "$B" 2>&1 | grep -v "replacing existing signature" || true
codesign -v "$B" || die "the bundle signature does not verify"
echo "Restored the plugin and nvrm610.conf from $BK. Log out and back in (or restart) to load it."
