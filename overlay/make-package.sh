#!/bin/bash
# Assemble the overlay package from built binaries. Run anywhere with tar and shasum or sha256sum.
#   overlay/make-package.sh <NVMTLDriver> <libnvencvt.dylib> <NVRMFB> <nvfb-edid> <NVAccel> <nvenc LICENSE> <overlay version> <plugin tag> <nvenc commit> <out dir>
# NVMTLDriver: the release build of this repository's plugin/ at <plugin tag> (NVMTL_RELEASE=1, minimum macOS 15.0);
# NVRMFB: build/fb_build.sh at <plugin tag>; nvfb-edid: tools/nvfb-edid.c at <plugin tag> (minimum macOS 15.0);
# libnvencvt.dylib: mickys/nvenc at <nvenc commit>. Writes <out dir>/mickys-overlay-<version>.tar.gz and its .sha256.
set -euo pipefail
[ $# = 10 ] || { sed -n '2,6p' "$0"; exit 2; }
DRV=$1; LIB=$2; FBB=$3; EDT=$4; ACB=$5; NVLIC=$6; V=$7; TAG=$8; NV=$9; OUT=${10}
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
sha() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
N=mickys-overlay-$V; T=$(mktemp -d); P=$T/$N
mkdir -p "$P/payload" "$OUT"
cp "$DRV" "$P/payload/NVMTLDriver"; cp "$LIB" "$P/payload/libnvencvt.dylib"; cp "$FBB" "$P/payload/NVRMFB"; cp "$EDT" "$P/payload/nvfb-edid"; cp "$ACB" "$P/payload/NVAccel"
chmod 755 "$P/payload/NVRMFB" "$P/payload/nvfb-edid" "$P/payload/NVAccel"
cp "$HERE/nvenc-run" "$HERE/nvenc-cli-aliases.sh" "$HERE/nvenc-cli-wrap" "$P/payload/"; chmod 755 "$P/payload/nvenc-run" "$P/payload/nvenc-cli-wrap"; chmod 644 "$P/payload/nvenc-cli-aliases.sh"
cp "$HERE/install.sh" "$HERE/uninstall.sh" "$HERE/README.md" "$HERE/PERFORMANCE.md" "$P/"; chmod 755 "$P/install.sh" "$P/uninstall.sh"
cp "$ROOT/LICENSE" "$P/LICENSE"; cp "$NVLIC" "$P/LICENSE-nvenc"
printf '2.5.2\n2.5.3\n' > "$P/COMPATIBLE-DRIVERS"   # NullMoth versions whose kernel interfaces this plugin build matches
printf '%s\n' "$V" > "$P/VERSION"
printf 'overlay %s\nplugin: mickys/nvidia-macos-driver %s\nencoder: mickys/nvenc %s\nfor: NullMoth driver %s (COMPATIBLE-DRIVERS)\n' "$V" "$TAG" "$NV" "$(paste -sd ' ' "$P/COMPATIBLE-DRIVERS")" > "$P/SOURCE"
(cd "$P" && sha payload/NVMTLDriver payload/libnvencvt.dylib payload/NVRMFB payload/nvfb-edid payload/NVAccel payload/nvenc-run payload/nvenc-cli-aliases.sh payload/nvenc-cli-wrap install.sh uninstall.sh README.md PERFORMANCE.md LICENSE LICENSE-nvenc COMPATIBLE-DRIVERS VERSION SOURCE > SHA256SUMS)
tar -C "$T" --owner=0 --group=0 -czf "$OUT/$N.tar.gz" "$N" 2>/dev/null || tar -C "$T" -czf "$OUT/$N.tar.gz" "$N"
(cd "$OUT" && sha "$N.tar.gz" > "$N.tar.gz.sha256")
rm -rf "$T"
echo "$OUT/$N.tar.gz"; cat "$OUT/$N.tar.gz.sha256"
