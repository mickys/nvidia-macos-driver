#!/bin/bash
# Undo the mickys overlay: put back the Metal plugin binary and nvrm610.conf saved by install.sh, remove
# libnvencvt.dylib if it was not there before, and remove nvenc-run and the --cli-aliases hook.
#   sudo ./uninstall.sh [backup dir]      default: /Library/NullMoth/overlay-backup-latest
set -euo pipefail
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
# command-line part first: it is ours even when NullMoth's installer has already replaced the plugin
MARK='# mickys overlay --cli-aliases'
for f in /etc/zshrc /etc/bashrc; do
  [ -f "$f" ] && grep -qF "$MARK" "$f" || continue
  grep -vF "$MARK" "$f" > "$f.mickys" || true; cat "$f.mickys" > "$f"; rm -f "$f.mickys"
done
rm -rf /usr/local/share/mickys-overlay
! grep -qs '^# nvenc-run (mickys overlay)' /usr/local/bin/nvenc-run || rm -f /usr/local/bin/nvenc-run
BK=${1:-/Library/NullMoth/overlay-backup-latest}
[ -f "$BK/NVMTLDriver" ] && [ -f "$BK/nvrm610.conf" ] || die "no overlay backup in $BK"
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
NOW=$(cat /Library/NullMoth/driver-version 2>/dev/null || echo unknown); WAS=$(cat "$BK/driver-version" 2>/dev/null || echo unknown)
[ "$NOW" = "$WAS" ] || die "the driver changed since the backup ($WAS -> $NOW); NullMoth's installer already replaced the overlay"
install -o root -g wheel -m 755 "$BK/NVMTLDriver" "$X/NVMTLDriver"
if [ -f "$BK/libnvencvt.dylib" ]; then install -o root -g wheel -m 755 "$BK/libnvencvt.dylib" "$X/libnvencvt.dylib"
else rm -f "$X/libnvencvt.dylib"; fi
install -o root -g wheel -m 644 "$BK/nvrm610.conf" "$C"
if [ -f "$BK/CodeResources" ]; then   # the bundle exactly as it was, signature included
  install -o root -g wheel -m 644 "$BK/CodeResources" "$B/Contents/_CodeSignature/CodeResources"
else                                  # backup from an older overlay: re-sign instead
  codesign -f -s - --preserve-metadata=identifier "$B" 2>&1 | grep -v "replacing existing signature" || true
fi
codesign -v "$B" || die "the bundle signature does not verify"
echo "Restored the plugin and nvrm610.conf from $BK, removed nvenc-run. Log out and back in (or restart) to load it."
