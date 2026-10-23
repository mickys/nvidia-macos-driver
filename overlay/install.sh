#!/bin/bash
# Install the mickys overlay on top of NullMoth's NVIDIA driver: adds the open-source encoder libnvencvt.dylib next to
# NullMoth's Metal plugin in /Library/GPUBundles/NVMTLDriver.bundle, which loads it by itself since 2.3.7
# (NVMTL_NVENCVT in nvrm610.conf). NullMoth's files stay as they are.
#   sudo ./install.sh [--desktop] [--resolution] [--event-wait] [--nvenc=<process list>|--nvenc=1|--nvenc=off] [--no-accel] [--cli-wrappers] [--cli-aliases] [--no-decoders]
#     --desktop      also replace the plugin binary with this fork's build (CPU-drawn windows uploaded by the GPU), and the
#                    accelerator kext's binary (NVAccel) with this fork's build: a page-off waits for the GPU without the
#                    accelerator lock, which lets two-plane capture surfaces share video memory (NVMTL_SURF_MULTIPLANE=1); restart
#     --no-accel     with --desktop: keep NullMoth's NVAccel (and capture surfaces in private copies)
#     --event-wait   apps wait for GPU work with an event instead of polling (NVRM_EVENT_WAIT=1 in nvrm610.conf): less CPU,
#                    slightly more latency in synchronous work; WindowServer already waits this way
#     --resolution   also replace the framebuffer kext's binary (NVRMFB) with this fork's build: desktop sizes below the
#                    boot screen's (/Library/NullMoth/nvfb-small) and EDID overrides for more modes (nvfb-edid); restart
# Each run installs exactly the parts asked for: running it again without --desktop or --resolution puts NullMoth's own
# plugin or framebuffer back.
#     --nvenc        which processes get the open-source H.264/HEVC encoder (RTX 40 only): 1 = every app (default), a
#                    comma-separated list of process names to limit it to those, off = none
#     --cli-wrappers also make ffmpeg, ffprobe, ffplay, HandBrakeCLI and avconvert run through nvenc-run in every zsh (scripts
#                    and ssh commands too) and interactive bash login shells: wrappers first in PATH (/etc/zshenv, /etc/zshrc, /etc/bashrc)
#     --cli-aliases  also make ffmpeg, HandBrakeCLI and avconvert run through nvenc-run in interactive zsh/bash shells
#     --no-decoders  the library's hardware decoders off (encoders only): NVENCVT_NO_DEC=1 in /usr/local/etc/nvencvt.conf
# Unless --nvenc=off, it also installs /usr/local/bin/nvenc-run, which gives command-line tools the encoder.
# It installs only over a NullMoth driver version listed in COMPATIBLE-DRIVERS, and only when the kernel extensions
# on disk and the ones running are that version too (the plugin and the kernel driver share interfaces).
# Undo: sudo ./uninstall.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NVENC=1; ALIASES=0; WRAPS=0; ENCONLY=1; NODEC=0; RES=0; EVW=0; ACCEL=-1
for a in "$@"; do case $a in
  --desktop) ENCONLY=0 ;;
  --resolution) RES=1 ;;
  --no-accel) ACCEL=0 ;;
  --event-wait) EVW=1 ;;
  --encoder-only) ENCONLY=1 ;;   # the default since 2.3.7-2; kept so older instructions still work
  --nvenc=*) NVENC=${a#--nvenc=} ;;
  --cli-aliases) ALIASES=1 ;;
  --cli-wrappers) WRAPS=1 ;;
  --no-decoders) NODEC=1 ;;
  *) echo "unknown option $a"; exit 2 ;;
esac; done
die() { echo "STOP: $*" >&2; exit 1; }
[ $ACCEL = 0 ] || ACCEL=$(( ENCONLY == 0 ))   # with --desktop unless --no-accel
ok() { echo "   ok  $*"; }
[ "$(id -u)" = 0 ] || die "run with sudo"
case $NVENC in off|1) ;; *) [[ $NVENC =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "--nvenc: process names separated by commas, 1 or off" ;; esac
[ "$NVENC" != off ] || [ $ALIASES = 0 ] || die "--cli-aliases needs the encoder (not --nvenc=off)"
[ "$NVENC" != off ] || [ $WRAPS = 0 ] || die "--cli-wrappers needs the encoder (not --nvenc=off)"
[ "$NVENC" != off ] || [ $ENCONLY = 0 ] || [ $RES = 1 ] || [ $EVW = 1 ] || die "--nvenc=off without --desktop, --resolution or --event-wait would install nothing"

OV=$(cat "$HERE/VERSION")
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
CR=$B/Contents/_CodeSignature/CodeResources
FB=/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB; AC=/Library/Extensions/NVAccel.kext/Contents/MacOS/NVAccel; AMARK='# mickys overlay --desktop accel'; SMALL=/Library/NullMoth/nvfb-small; EDT=/usr/local/bin/nvfb-edid
RUN=/usr/local/bin/nvenc-run; SH=/usr/local/share/mickys-overlay; VC=/usr/local/etc/nvencvt.conf; VMARK='# mickys overlay --no-decoders'; RC="/etc/zshrc /etc/bashrc"; MARK='# mickys overlay --cli-aliases'
WRC="/etc/zshenv /etc/zshrc /etc/bashrc"; WMARK='# mickys overlay --cli-wrappers'; WBIN=/usr/local/share/mickys-overlay/bin
WTOOLS="ffmpeg ffprobe ffplay HandBrakeCLI avconvert"
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
[ ! -e "$RUN" ] || grep -q '^# nvenc-run (mickys overlay)' "$RUN" || die "$RUN exists and is not the overlay's; move it away first"
[ ! -e "$EDT" ] || grep -q 'nvfb-edid list' "$EDT" || die "$EDT exists and is not the overlay's; move it away first"
[ -f "$FB" ] || die "$FB missing; reinstall NullMoth $HAVE"

echo "== 2. back up what is there now"
L=/Library/NullMoth/overlay-backup-latest
if grep -q '^# mickys overlay' "$C" && [ -f "$L/NVMTLDriver" ] && [ "$(cat "$L/driver-version" 2>/dev/null)" = "$HAVE" ]; then
  BK=$(cd "$L" && pwd -P)
  ok "the overlay is already installed: keeping the backup of NullMoth's files in $BK"
else
  BK=/Library/NullMoth/overlay-backup-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BK"
  cp -p "$X/NVMTLDriver" "$BK/" && cp -p "$C" "$BK/" || die "backup to $BK failed"
  [ ! -f "$CR" ] || cp -p "$CR" "$BK/CodeResources" || die "backup to $BK failed"   # lets uninstall.sh put the bundle back without re-signing
  [ ! -f "$X/libnvencvt.dylib" ] || cp -p "$X/libnvencvt.dylib" "$BK/"
  echo "$HAVE" > "$BK/driver-version"
  ln -sfn "$BK" "$L"
  ok "backup in $BK"
fi
# NullMoth's framebuffer binary (a backup made by an overlay before 2.4.3-mickys.5 has none; the one on disk is NullMoth's
# unless it is this package's)
if [ ! -f "$BK/NVRMFB" ]; then
  cmp -s "$FB" "$HERE/payload/NVRMFB" && die "$FB is this overlay's build but the backup has no NullMoth NVRMFB; reinstall NullMoth $HAVE"
  cp -p "$FB" "$BK/NVRMFB" || die "backup to $BK failed"
  ok "NullMoth's NVRMFB added to the backup"
fi
# and NullMoth's accelerator binary (backups made before 2.5.3-mickys.8 have none; the one on disk is NullMoth's unless it is this
# package's)
if [ ! -f "$BK/NVAccel" ]; then
  cmp -s "$AC" "$HERE/payload/NVAccel" && die "$AC is this overlay's build but the backup has no NullMoth NVAccel; reinstall NullMoth $HAVE"
  cp -p "$AC" "$BK/NVAccel" || die "backup to $BK failed"
  ok "NullMoth's NVAccel added to the backup"
fi

echo "== 3. install"
if [ $ENCONLY = 1 ]; then
  # NullMoth's own plugin, as the backup holds it (puts it back after a full install of the overlay)
  install -o root -g wheel -m 755 "$BK/NVMTLDriver" "$X/NVMTLDriver"
  [ ! -f "$BK/CodeResources" ] || install -o root -g wheel -m 644 "$BK/CodeResources" "$CR"
  install -o root -g wheel -m 755 "$HERE/payload/libnvencvt.dylib" "$X/libnvencvt.dylib"
  xattr -d com.apple.quarantine "$X/libnvencvt.dylib" 2>/dev/null || true
  # NullMoth's plugin refuses the library unless it and its directory are root-owned and not group/world-writable
  rootonly() { [ "$(stat -f %u "$1")" = 0 ] && [ -z "$(find "$1" -maxdepth 0 -perm +022)" ]; }
  rootonly "$X/libnvencvt.dylib" && rootonly "$X" || die "$X or libnvencvt.dylib is writable by others; NullMoth's plugin would refuse it"
  ok "libnvencvt.dylib installed next to NullMoth's plugin (plugin and its signature unchanged)"
else
  install -o root -g wheel -m 755 "$HERE/payload/NVMTLDriver" "$X/NVMTLDriver"
  install -o root -g wheel -m 755 "$HERE/payload/libnvencvt.dylib" "$X/libnvencvt.dylib"
  # a browser-downloaded package carries com.apple.quarantine onto the extracted files; system binaries should not have it
  xattr -d com.apple.quarantine "$X/NVMTLDriver" "$X/libnvencvt.dylib" 2>/dev/null || true
  codesign -f -s - "$X/libnvencvt.dylib" 2>&1 | grep -v "replacing existing signature" || true
  codesign -f -s - --preserve-metadata=identifier "$B" 2>&1 | grep -v "replacing existing signature" || true
  codesign -v "$B" || die "the bundle signature does not verify (undo: sudo ./uninstall.sh)"
  ok "plugin and libnvencvt.dylib installed, bundle re-signed"
fi

# the Auxiliary Kernel Collection with the framebuffer binary on disk, built the way NullMoth's installer builds it; every
# com.nullmoth kext must be in the new collection, else the old one stays
auxkc() {
  local KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc K=/System/Library/Kernels/kernel NEW KARG=(--allow-missing-kdk)
  [ -f "$K" ] && KARG+=(--kernel "$K"); NEW="$KC.mickys-new"; rm -f "$NEW"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z >/tmp/mickys-kmutil.log 2>&1 \
    || { tail -20 /tmp/mickys-kmutil.log; return 1; }
  local INS; INS=$(kmutil inspect -a x86_64 -A "$NEW" 2>/dev/null || true)
  for k in NVRM NVAccel NVRMFB; do
    grep -oE 'com\.nullmoth\.[A-Za-z0-9]+' <<<"$INS" | grep -Fxq "com.nullmoth.$k" || { rm -f "$NEW"; echo "com.nullmoth.$k missing from the new collection"; return 1; }
  done
  mv -f "$NEW" "$KC"
}
FBWAS=$(shasum -a 256 "$FB" | cut -d' ' -f1); ACWAS=$(shasum -a 256 "$AC" | cut -d' ' -f1)
if [ $RES = 1 ]; then
  install -o root -g wheel -m 755 "$HERE/payload/NVRMFB" "$FB"
  : > "$SMALL"; chown root:wheel "$SMALL"; chmod 644 "$SMALL"
  install -d -o root -g wheel -m 755 /usr/local/bin
  install -o root -g wheel -m 755 "$HERE/payload/nvfb-edid" "$EDT"
  xattr -d com.apple.quarantine "$FB" "$EDT" 2>/dev/null || true
else
  install -o root -g wheel -m 755 "$BK/NVRMFB" "$FB"
  rm -f "$SMALL"; [ ! -e "$EDT" ] || rm -f "$EDT"
fi
if [ $ACCEL = 1 ]; then install -o root -g wheel -m 755 "$HERE/payload/NVAccel" "$AC"; xattr -d com.apple.quarantine "$AC" 2>/dev/null || true
else install -o root -g wheel -m 755 "$BK/NVAccel" "$AC"; fi
FBCHANGED=0
if [ "$(shasum -a 256 "$FB" | cut -d' ' -f1)" != "$FBWAS" ] || [ "$(shasum -a 256 "$AC" | cut -d' ' -f1)" != "$ACWAS" ]; then
  echo "   ..  rebuilding the Auxiliary Kernel Collection (about a minute)"
  auxkc || { install -o root -g wheel -m 755 "$BK/NVRMFB" "$FB"; install -o root -g wheel -m 755 "$BK/NVAccel" "$AC"; rm -f "$SMALL" "$EDT"
             die "kmutil could not build the kernel collection; NullMoth's NVRMFB and NVAccel put back"; }
  FBCHANGED=1
fi
if [ $RES = 1 ]; then ok "NVRMFB from this fork (smaller desktop sizes; EDID overrides: nvfb-edid list / sudo nvfb-edid add 1920x1080@144)$([ $FBCHANGED = 1 ] && echo ", kernel collection rebuilt")"
else ok "NullMoth's NVRMFB$([ $FBCHANGED = 1 ] && echo " put back, kernel collection rebuilt")"; fi
if [ $ACCEL = 1 ]; then ok "NVAccel from this fork (a page-off waits for the GPU without the accelerator lock; sysctl debug.nvaccel_pageoff_unlocked_wait)"
else ok "NullMoth's NVAccel"; fi

echo "== 4. settings (nvrm610.conf)"
EMARK='# mickys overlay --event-wait'
awk -v m="$EMARK" -v a="$AMARK" 'skip { skip = 0; next } index($0, m) == 1 || index($0, a) == 1 { skip = 1; next } { print }' "$C" | grep -v -E '^NVMTL_NVENCVT=|^# mickys overlay' > "$C.new" || true
PARTS=encoder; [ "$NVENC" != off ] || PARTS=; [ $ENCONLY = 1 ] || PARTS="$PARTS desktop"; [ $ACCEL = 0 ] || PARTS="$PARTS accel"; [ $RES = 0 ] || PARTS="$PARTS resolution"; [ $EVW = 0 ] || PARTS="$PARTS event-wait"
printf '# mickys overlay %s: %s (uninstall.sh puts the original file back)\n' "$OV" "${PARTS# }" >> "$C.new"
[ "$NVENC" = off ] || printf 'NVMTL_NVENCVT=%s\n' "$NVENC" >> "$C.new"
[ $EVW = 0 ] || printf '%s (uninstall.sh removes this line and the next)\nNVRM_EVENT_WAIT=1\n' "$EMARK" >> "$C.new"
# with this fork's NVAccel, two-plane (NV12) capture surfaces share video memory: a reader's lock waits for the GPU in the kernel
[ $ACCEL = 0 ] || printf '%s (uninstall.sh removes this line and the next)\nNVMTL_SURF_MULTIPLANE=1\n' "$AMARK" >> "$C.new"
chown root:wheel "$C.new"; chmod 644 "$C.new"; mv "$C.new" "$C"
ok "NVMTL_NVENCVT=${NVENC/off/(not set)}$([ $EVW = 1 ] && echo ", NVRM_EVENT_WAIT=1 (--event-wait)")$([ $ACCEL = 1 ] && echo ", NVMTL_SURF_MULTIPLANE=1 (--desktop with NVAccel)")"

echo "== 5. command-line tools"
for f in $RC $WRC; do   # drop earlier --cli-aliases / --cli-wrappers hooks; rewrite in place to keep the file's owner and mode
  [ -f "$f" ] && grep -qF -e "$MARK" -e "$WMARK" "$f" || continue
  grep -vF -e "$MARK" -e "$WMARK" "$f" > "$f.mickys" || true; cat "$f.mickys" > "$f"; rm -f "$f.mickys"
  [ -s "$f" ] || [ "$f" != /etc/zshenv ] || rm -f "$f"   # macOS ships no /etc/zshenv: the overlay made it
done
rm -rf "$SH"
if [ "$NVENC" = off ]; then
  rm -f "$RUN"; ok "no nvenc-run (--nvenc=off)"
else
  install -d -o root -g wheel -m 755 /usr/local/bin
  install -o root -g wheel -m 755 "$HERE/payload/nvenc-run" "$RUN"
  xattr -d com.apple.quarantine "$RUN" 2>/dev/null || true
  ok "$RUN (example: nvenc-run ffmpeg -i in.mov -c:v hevc_videotoolbox out.mp4)"
  if [ $ALIASES = 1 ]; then
    install -d -o root -g wheel -m 755 "$SH"
    install -o root -g wheel -m 644 "$HERE/payload/nvenc-cli-aliases.sh" "$SH/nvenc-cli-aliases.sh"
    xattr -d com.apple.quarantine "$SH/nvenc-cli-aliases.sh" 2>/dev/null || true
    for f in $RC; do
      [ -f "$f" ] || continue
      printf '[ -r %s/nvenc-cli-aliases.sh ] && . %s/nvenc-cli-aliases.sh  %s\n' "$SH" "$SH" "$MARK" >> "$f"
      ok "$f: ffmpeg, HandBrakeCLI, avconvert run through nvenc-run (new shells)"
    done
  fi
  if [ $WRAPS = 1 ]; then
    # wrappers named like the tools, first in PATH: zshenv for every zsh (scripts, ssh commands), zshrc / bashrc again after
    # /etc/zprofile's / /etc/profile's path_helper, which moves the system's paths in front for login shells
    install -d -o root -g wheel -m 755 "$SH" "$WBIN"
    for t in $WTOOLS; do install -o root -g wheel -m 755 "$HERE/payload/nvenc-cli-wrap" "$WBIN/$t"; xattr -d com.apple.quarantine "$WBIN/$t" 2>/dev/null || true; done
    for f in $WRC; do
      [ -f "$f" ] || [ "$f" = /etc/zshenv ] || continue
      [ -f "$f" ] || install -o root -g wheel -m 644 /dev/null "$f"
      echo '[ ! -d /usr/local/share/mickys-overlay/bin ] || { PATH=/usr/local/share/mickys-overlay/bin:${PATH//\/usr\/local\/share\/mickys-overlay\/bin:/}; export PATH; }  '"$WMARK" >> "$f"
    done
    ok "$WBIN first in PATH ($WRC): $WTOOLS run through nvenc-run in new shells, scripts and ssh commands (NVENC_WRAP=0 bypasses)"
  fi
fi

echo "== 6. decoders"
# libnvencvt reads NVENCVT_* settings from $VC (root-owned, not writable by others): the overlay's setting is the line
# after its marker comment; other lines in the file are left alone
if [ -f "$VC" ]; then awk -v m="$VMARK" 'skip { skip = 0; next } index($0, m) == 1 { skip = 1; next } { print }' "$VC" > "$VC.new"; else : > "$VC.new"; fi
if [ $NODEC = 1 ] && [ "$NVENC" != off ]; then printf '%s (uninstall.sh removes this line and the next)\nNVENCVT_NO_DEC=1\n' "$VMARK" >> "$VC.new"; fi
if [ -s "$VC.new" ]; then install -d -o root -g wheel -m 755 /usr/local/etc; chown root:wheel "$VC.new"; chmod 644 "$VC.new"; mv "$VC.new" "$VC"
else rm -f "$VC.new" "$VC"; fi
if [ "$NVENC" = off ]; then ok "no encoder, no decoders (--nvenc=off)"
elif [ $NODEC = 1 ]; then ok "hardware decoders off ($VC: NVENCVT_NO_DEC=1)"
else ok "hardware decoders on (H.264, HEVC, VP9, AV1, MPEG-1/2, MPEG-4 Part 2; --no-decoders turns them off)"; fi

echo
WHAT="the encoders and decoders"; [ $NODEC = 0 ] || WHAT="the encoders"
if [ $FBCHANGED = 1 ]; then echo "Done. Restart the Mac to load the new kernel extensions$([ $RES = 1 ] && echo " (then pick a size in System Settings > Displays)")."
elif [ $ENCONLY = 1 ]; then echo "Done. Apps you open from now on get $WHAT (quit and reopen running ones)."
else echo "Done. Log out and back in (or restart) so WindowServer and running apps load the new plugin."; fi
[ "$NVENC" = off ] || [ $WRAPS = 1 ] || echo "Command-line tools (ffmpeg, HandBrakeCLI, avconvert) see the encoders, and the decoders from the first frame, only through nvenc-run:   nvenc-run ffmpeg ...   (sudo ./install.sh --cli-wrappers does that for you)"
echo "Undo: sudo $HERE/uninstall.sh   (backup: $BK)"
