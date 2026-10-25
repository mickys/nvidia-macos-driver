#!/bin/bash
# Undo the mickys overlay: put back the Metal plugin binary, the shader translator and nvrm610.conf saved by install.sh, remove
# libnvencvt.dylib if it was not there before, and remove nvenc-run, the --cli-aliases hook and the --no-decoders line;
# after --resolution also NullMoth's NVRMFB (kernel collection rebuilt; restart), nvfb-edid and /Library/NullMoth/nvfb-small.
# EDID overrides in /Library/NullMoth/edid-override stay (NullMoth's framebuffer ignores them).
#   sudo ./uninstall.sh [backup dir]      default: /Library/NullMoth/overlay-backup-latest
set -euo pipefail
die() { echo "STOP: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"
# command-line part first: it is ours even when NullMoth's installer has already replaced the plugin
MARK='# mickys overlay --cli-aliases'; WMARK='# mickys overlay --cli-wrappers'
for f in /etc/zshenv /etc/zshrc /etc/bashrc; do   # the --cli-aliases / --cli-wrappers lines
  [ -f "$f" ] && grep -qF -e "$MARK" -e "$WMARK" "$f" || continue
  grep -vF -e "$MARK" -e "$WMARK" "$f" > "$f.mickys" || true; cat "$f.mickys" > "$f"; rm -f "$f.mickys"
  [ -s "$f" ] || [ "$f" != /etc/zshenv ] || rm -f "$f"   # macOS ships no /etc/zshenv: the overlay made it
done
rm -rf /usr/local/share/mickys-overlay
VC=/usr/local/etc/nvencvt.conf   # the --no-decoders line (other lines stay)
if grep -qsF '# mickys overlay --no-decoders' "$VC"; then
  awk -v m='# mickys overlay --no-decoders' 'skip { skip = 0; next } index($0, m) == 1 { skip = 1; next } { print }' "$VC" > "$VC.new" || true
  if [ -s "$VC.new" ]; then cat "$VC.new" > "$VC"; rm -f "$VC.new"; else rm -f "$VC.new" "$VC"; fi
fi
! grep -qs '^# nvenc-run (mickys overlay)' /usr/local/bin/nvenc-run || rm -f /usr/local/bin/nvenc-run
! grep -qs 'nvfb-edid list' /usr/local/bin/nvfb-edid || rm -f /usr/local/bin/nvfb-edid
rm -f /Library/NullMoth/nvfb-small
BK=${1:-/Library/NullMoth/overlay-backup-latest}
[ -f "$BK/NVMTLDriver" ] && [ -f "$BK/nvrm610.conf" ] || die "no overlay backup in $BK"
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
NOW=$(cat /Library/NullMoth/driver-version 2>/dev/null || echo unknown); WAS=$(cat "$BK/driver-version" 2>/dev/null || echo unknown)
[ "$NOW" = "$WAS" ] || die "the driver changed since the backup ($WAS -> $NOW); NullMoth's installer already replaced the overlay"
install -o root -g wheel -m 755 "$BK/NVMTLDriver" "$X/NVMTLDriver"
[ ! -f "$BK/libnvmtl_translate.dylib" ] || install -o root -g wheel -m 755 "$BK/libnvmtl_translate.dylib" "$X/libnvmtl_translate.dylib"
if [ -f "$BK/libnvencvt.dylib" ]; then install -o root -g wheel -m 755 "$BK/libnvencvt.dylib" "$X/libnvencvt.dylib"
else rm -f "$X/libnvencvt.dylib"; fi
install -o root -g wheel -m 644 "$BK/nvrm610.conf" "$C"
if [ -f "$BK/CodeResources" ]; then   # the bundle exactly as it was, signature included
  install -o root -g wheel -m 644 "$BK/CodeResources" "$B/Contents/_CodeSignature/CodeResources"
else                                  # backup from an older overlay: re-sign instead
  codesign -f -s - --preserve-metadata=identifier "$B" 2>&1 | grep -v "replacing existing signature" || true
fi
codesign -v "$B" || die "the bundle signature does not verify"
FB=/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB; AC=/Library/Extensions/NVAccel.kext/Contents/MacOS/NVAccel; RESTART=0
FBX=0; ACX=0
{ [ -f "$BK/NVRMFB" ] && ! cmp -s "$BK/NVRMFB" "$FB"; } && FBX=1    # --resolution was installed: NullMoth's framebuffer back
{ [ -f "$BK/NVAccel" ] && ! cmp -s "$BK/NVAccel" "$AC"; } && ACX=1  # --desktop with NVAccel: NullMoth's accelerator back
if [ $FBX = 1 ] || [ $ACX = 1 ]; then
  [ $FBX = 0 ] || install -o root -g wheel -m 755 "$BK/NVRMFB" "$FB"
  [ $ACX = 0 ] || install -o root -g wheel -m 755 "$BK/NVAccel" "$AC"
  KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc; K=/System/Library/Kernels/kernel; KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
  echo "rebuilding the Auxiliary Kernel Collection with NullMoth's kernel extensions (about a minute)"
  rm -f "$KC.mickys-new"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$KC.mickys-new" -z >/tmp/mickys-kmutil.log 2>&1 \
    || { tail -20 /tmp/mickys-kmutil.log; die "kmutil failed; NullMoth's NVRMFB / NVAccel are on disk but not in the kernel collection (run NullMoth's install.sh again)"; }
  INS=$(kmutil inspect -a x86_64 -A "$KC.mickys-new" 2>/dev/null || true)
  for k in NVRM NVAccel NVRMFB; do
    grep -oE 'com\.nullmoth\.[A-Za-z0-9]+' <<<"$INS" | grep -Fxq "com.nullmoth.$k" || { rm -f "$KC.mickys-new"; die "com.nullmoth.$k missing from the new kernel collection (run NullMoth's install.sh again)"; }
  done
  mv -f "$KC.mickys-new" "$KC"; RESTART=1
fi
if [ $RESTART = 1 ]; then echo "Restored the plugin, NVRMFB / NVAccel and nvrm610.conf from $BK, removed nvenc-run and nvfb-edid. Restart the Mac to load them."
else echo "Restored the plugin and nvrm610.conf from $BK, removed nvenc-run. Log out and back in (or restart) to load it."; fi
