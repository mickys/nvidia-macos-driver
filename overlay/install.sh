#!/bin/bash
# Install the mickys overlay on top of NullMoth's NVIDIA driver: replaces the Metal plugin binary in
# /Library/GPUBundles/NVMTLDriver.bundle with the overlay's build and adds libnvencvt.dylib next to it.
#   sudo ./install.sh [--nvenc=<process list>|--nvenc=1|--nvenc=off] [--force]
#     --nvenc   which processes get the open-source H.264 encoder (RTX 40 only): a comma-separated list of process
#               names, 1 = every process, off = none. Default: parsecd,obs,ffmpeg,sunshine
#     --force   install over a driver version other than the one the overlay was built for
# Undo: sudo ./uninstall.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NVENC="parsecd,obs,ffmpeg,sunshine"; FORCE=0
for a in "$@"; do case $a in
  --nvenc=*) NVENC=${a#--nvenc=} ;;
  --force) FORCE=1 ;;
  *) echo "unknown option $a"; exit 2 ;;
esac; done
die() { echo "STOP: $*" >&2; exit 1; }
ok() { echo "   ok  $*"; }
[ "$(id -u)" = 0 ] || die "run with sudo"
[ "$(uname -m)" = x86_64 ] || die "this overlay is for Intel/AMD (x86_64) Macs"
case $NVENC in off|1) ;; *) [[ $NVENC =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "--nvenc: process names separated by commas, 1 or off" ;; esac

WANT=$(cat "$HERE/DRIVER-VERSION"); OV=$(cat "$HERE/VERSION")
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
echo "== mickys overlay $OV for NullMoth driver $WANT"

echo "== 1. checks"
(cd "$HERE" && shasum -a 256 -c SHA256SUMS >/dev/null) || die "a file does not match SHA256SUMS (download again)"
ok "package files match SHA256SUMS"
[ -x "$X/NVMTLDriver" ] || die "NullMoth's driver is not installed ($X/NVMTLDriver missing); install NullMoth $WANT first"
HAVE=$(cat /Library/NullMoth/driver-version 2>/dev/null || echo unknown)
if [ "$HAVE" != "$WANT" ]; then
  [ $FORCE = 1 ] || die "installed NullMoth driver is $HAVE, this overlay is built for $WANT (install $WANT, or --force)"
  echo "   NOTE: installing over NullMoth $HAVE (--force)"
else ok "NullMoth driver $HAVE installed"; fi
[ -f "$C" ] || die "$C missing"

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
