#!/bin/bash
# Install the mickys overlay on top of NullMoth's NVIDIA driver: replaces the Metal plugin binary in
# /Library/GPUBundles/NVMTLDriver.bundle with the overlay's build and adds libnvencvt.dylib next to it.
#   sudo ./install.sh [--nvenc=<process list>|--nvenc=1|--nvenc=off]
#     --nvenc   which processes get the open-source H.264/HEVC encoder (RTX 40 only): a comma-separated list of process
#               names, 1 = every process, off = none. Default: parsecd,obs,ffmpeg,sunshine
# It installs only over a NullMoth driver version listed in COMPATIBLE-DRIVERS, and only when the kernel extensions
# on disk and the ones running are that version too (the plugin and the kernel driver share interfaces).
# Undo: sudo ./uninstall.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NVENC="parsecd,obs,ffmpeg,sunshine"
for a in "$@"; do case $a in
  --nvenc=*) NVENC=${a#--nvenc=} ;;
  *) echo "unknown option $a"; exit 2 ;;
esac; done
die() { echo "STOP: $*" >&2; exit 1; }
ok() { echo "   ok  $*"; }
[ "$(id -u)" = 0 ] || die "run with sudo"
case $NVENC in off|1) ;; *) [[ $NVENC =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "--nvenc: process names separated by commas, 1 or off" ;; esac

OV=$(cat "$HERE/VERSION")
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
echo "== mickys overlay $OV (for NullMoth driver $(paste -sd ' ' "$HERE/COMPATIBLE-DRIVERS"))"

echo "== 1. checks"
(cd "$HERE" && shasum -a 256 -c SHA256SUMS >/dev/null) || die "a file does not match SHA256SUMS (download again)"
ok "package files match SHA256SUMS"
[ "$(uname -m)" = x86_64 ] || die "this overlay is for Intel/AMD (x86_64) Macs"
MAC=$(sw_vers -productVersion); [ "${MAC%%.*}" -ge 15 ] 2>/dev/null || die "macOS $MAC: NullMoth's driver needs macOS 15 or later"
ok "macOS $MAC, x86_64"
PCI=$(ioreg -r -c IOPCIDevice -d 1 2>/dev/null || true)   # captured first: grep -q in a pipe would SIGPIPE ioreg under pipefail
grep -q '"vendor-id" = <de100000>' <<<"$PCI" || die "no NVIDIA GPU on PCI"
ok "NVIDIA GPU present"
compatible() { grep -qxF "$1" "$HERE/COMPATIBLE-DRIVERS"; }
HAVE=$(cat /Library/NullMoth/driver-version 2>/dev/null || true)
[ -n "$HAVE" ] || die "NullMoth's driver is not installed (/Library/NullMoth/driver-version missing); install a compatible version first"
compatible "$HAVE" || die "NullMoth driver $HAVE is installed; this overlay works only with $(paste -sd " " "$HERE/COMPATIBLE-DRIVERS") (install that version, or get an overlay built for $HAVE)"
[ -x "$X/NVMTLDriver" ] || die "NullMoth's Metal plugin is missing ($X/NVMTLDriver); reinstall NullMoth $HAVE"
[ -f "$C" ] || die "$C missing; reinstall NullMoth $HAVE"
for k in NVRM NVAccel NVRMFB; do
  v=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/Library/Extensions/$k.kext/Contents/Info.plist" 2>/dev/null || true)
  [ "$v" = "$HAVE" ] || die "/Library/Extensions/$k.kext is version '${v:-missing}', not $HAVE; reinstall NullMoth $HAVE"
done
ok "NullMoth driver $HAVE installed (NVRM, NVAccel, NVRMFB on disk: $HAVE)"
LOADED=$(kmutil showloaded --list-only 2>/dev/null | grep -E 'com\.nullmoth\.(NVRM|NVAccel|NVRMFB) ' || true)
for k in NVRM NVAccel NVRMFB; do
  v=$(sed -n "s/.*com\.nullmoth\.$k (\([^)]*\)).*/\1/p" <<<"$LOADED"); v=${v%%$'\n'*}
  [ -n "$v" ] || die "com.nullmoth.$k is not running (the driver did not start, or the Mac was not restarted after installing it)"
  [ "$v" = "$HAVE" ] || die "the running com.nullmoth.$k is version $v, the installed one $HAVE: restart the Mac first, then run this again"
done
ok "running kernel driver: $HAVE"

echo "== 2. back up what is there now"
L=/Library/NullMoth/overlay-backup-latest
if grep -q '^# mickys overlay' "$C" && [ -f "$L/NVMTLDriver" ] && [ "$(cat "$L/driver-version" 2>/dev/null)" = "$HAVE" ]; then
  BK=$(cd "$L" && pwd -P)
  ok "the overlay is already installed: keeping the backup of NullMoth's files in $BK"
else
  BK=/Library/NullMoth/overlay-backup-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BK"
  cp -p "$X/NVMTLDriver" "$BK/" && cp -p "$C" "$BK/" || die "backup to $BK failed"
  [ ! -f "$X/libnvencvt.dylib" ] || cp -p "$X/libnvencvt.dylib" "$BK/"
  echo "$HAVE" > "$BK/driver-version"
  ln -sfn "$BK" "$L"
  ok "backup in $BK"
fi

echo "== 3. install"
install -o root -g wheel -m 755 "$HERE/payload/NVMTLDriver" "$X/NVMTLDriver"
install -o root -g wheel -m 755 "$HERE/payload/libnvencvt.dylib" "$X/libnvencvt.dylib"
# a browser-downloaded package carries com.apple.quarantine onto the extracted files; system binaries should not have it
xattr -d com.apple.quarantine "$X/NVMTLDriver" "$X/libnvencvt.dylib" 2>/dev/null || true
codesign -f -s - "$X/libnvencvt.dylib" 2>&1 | grep -v "replacing existing signature" || true
codesign -f -s - --preserve-metadata=identifier "$B" 2>&1 | grep -v "replacing existing signature" || true
codesign -v "$B" || die "the bundle signature does not verify (undo: sudo ./uninstall.sh)"
ok "plugin and libnvencvt.dylib installed, bundle re-signed"

echo "== 4. settings (nvrm610.conf)"
grep -v -E '^NVMTL_NVENCVT=|^# mickys overlay' "$C" > "$C.new" || true
printf '# mickys overlay %s (uninstall.sh puts the original file back)\n' "$OV" >> "$C.new"
[ "$NVENC" = off ] || printf 'NVMTL_NVENCVT=%s\n' "$NVENC" >> "$C.new"
chown root:wheel "$C.new"; chmod 644 "$C.new"; mv "$C.new" "$C"
ok "NVMTL_NVENCVT=${NVENC/off/(not set)}"

echo
echo "Done. Log out and back in (or restart) so WindowServer and running apps load the new plugin."
echo "Undo: sudo $HERE/uninstall.sh   (backup: $BK)"
