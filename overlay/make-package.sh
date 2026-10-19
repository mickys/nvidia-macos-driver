#!/bin/bash
# Assemble the overlay package from built binaries. Run anywhere with tar and shasum or sha256sum.
#   overlay/make-package.sh <NVMTLDriver> <libnvencvt.dylib> <nvenc LICENSE> <overlay version> <plugin tag> <nvenc commit> <out dir>
# NVMTLDriver: the release build of this repository's plugin/ at <plugin tag> (NVMTL_RELEASE=1, minimum macOS 15.0);
# libnvencvt.dylib: mickys/nvenc at <nvenc commit>. Writes <out dir>/mickys-overlay-<version>.tar.gz and its .sha256.
set -euo pipefail
[ $# = 7 ] || { sed -n '2,5p' "$0"; exit 2; }
DRV=$1; LIB=$2; NVLIC=$3; V=$4; TAG=$5; NV=$6; OUT=$7
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/.." && pwd)
sha() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
N=mickys-overlay-$V; T=$(mktemp -d); P=$T/$N
mkdir -p "$P/payload" "$OUT"
cp "$DRV" "$P/payload/NVMTLDriver"; cp "$LIB" "$P/payload/libnvencvt.dylib"
cp "$HERE/nvenc-run" "$HERE/nvenc-cli-aliases.sh" "$P/payload/"; chmod 755 "$P/payload/nvenc-run"; chmod 644 "$P/payload/nvenc-cli-aliases.sh"
cp "$HERE/install.sh" "$HERE/uninstall.sh" "$HERE/README.md" "$P/"; chmod 755 "$P/install.sh" "$P/uninstall.sh"
cp "$ROOT/LICENSE" "$P/LICENSE"; cp "$NVLIC" "$P/LICENSE-nvenc"
printf '2.3.6\n' > "$P/COMPATIBLE-DRIVERS"   # NullMoth versions whose kernel interfaces this plugin build matches
printf '%s\n' "$V" > "$P/VERSION"
printf 'overlay %s\nplugin: mickys/nvidia-macos-driver %s\nencoder: mickys/nvenc %s\nfor: NullMoth driver 2.3.6 (COMPATIBLE-DRIVERS)\n' "$V" "$TAG" "$NV" > "$P/SOURCE"
(cd "$P" && sha payload/NVMTLDriver payload/libnvencvt.dylib payload/nvenc-run payload/nvenc-cli-aliases.sh install.sh uninstall.sh README.md LICENSE LICENSE-nvenc COMPATIBLE-DRIVERS VERSION SOURCE > SHA256SUMS)
tar -C "$T" --owner=0 --group=0 -czf "$OUT/$N.tar.gz" "$N" 2>/dev/null || tar -C "$T" -czf "$OUT/$N.tar.gz" "$N"
(cd "$OUT" && sha "$N.tar.gz" > "$N.tar.gz.sha256")
rm -rf "$T"
echo "$OUT/$N.tar.gz"; cat "$OUT/$N.tar.gz.sha256"
