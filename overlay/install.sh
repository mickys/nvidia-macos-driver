#!/bin/bash
# Install the mickys overlay on top of NullMoth's NVIDIA driver: adds the open-source encoder libnvencvt.dylib next to
# NullMoth's Metal plugin in /Library/GPUBundles/NVMTLDriver.bundle, which loads it by itself since 2.3.7
# (NVMTL_NVENCVT in nvrm610.conf). NullMoth's files stay as they are.
#   sudo ./install.sh [--desktop] [--nvenc=<process list>|--nvenc=1|--nvenc=off] [--cli-aliases] [--no-decoders]
#     --desktop      also replace the plugin binary with this fork's build (CPU-drawn windows uploaded by the GPU)
#     --nvenc        which processes get the open-source H.264/HEVC encoder (RTX 40 only): 1 = every app (default), a
#                    comma-separated list of process names to limit it to those, off = none
#     --cli-aliases  also make ffmpeg, HandBrakeCLI and avconvert run through nvenc-run in interactive zsh/bash shells
#     --no-decoders  the library's hardware decoders off (encoders only): NVENCVT_NO_DEC=1 in /usr/local/etc/nvencvt.conf
# Unless --nvenc=off, it also installs /usr/local/bin/nvenc-run, which gives command-line tools the encoder.
# It installs only over a NullMoth driver version listed in COMPATIBLE-DRIVERS, and only when the kernel extensions
# on disk and the ones running are that version too (the plugin and the kernel driver share interfaces).
# Undo: sudo ./uninstall.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NVENC=1; ALIASES=0; ENCONLY=1; NODEC=0
for a in "$@"; do case $a in
  --desktop) ENCONLY=0 ;;
  --encoder-only) ENCONLY=1 ;;   # the default since 2.3.7-2; kept so older instructions still work
  --nvenc=*) NVENC=${a#--nvenc=} ;;
  --cli-aliases) ALIASES=1 ;;
  --no-decoders) NODEC=1 ;;
  *) echo "unknown option $a"; exit 2 ;;
esac; done
die() { echo "STOP: $*" >&2; exit 1; }
ok() { echo "   ok  $*"; }
[ "$(id -u)" = 0 ] || die "run with sudo"
case $NVENC in off|1) ;; *) [[ $NVENC =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "--nvenc: process names separated by commas, 1 or off" ;; esac
[ "$NVENC" != off ] || [ $ALIASES = 0 ] || die "--cli-aliases needs the encoder (not --nvenc=off)"
[ "$NVENC" != off ] || [ $ENCONLY = 0 ] || die "--nvenc=off without --desktop would install nothing"

OV=$(cat "$HERE/VERSION")
B=/Library/GPUBundles/NVMTLDriver.bundle; X=$B/Contents/MacOS; C=/Library/GPUBundles/nvmtl/nvrm610.conf
CR=$B/Contents/_CodeSignature/CodeResources
RUN=/usr/local/bin/nvenc-run; SH=/usr/local/share/mickys-overlay; VC=/usr/local/etc/nvencvt.conf; VMARK='# mickys overlay --no-decoders'; RC="/etc/zshrc /etc/bashrc"; MARK='# mickys overlay --cli-aliases'
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

echo "== 4. settings (nvrm610.conf)"
grep -v -E '^NVMTL_NVENCVT=|^# mickys overlay' "$C" > "$C.new" || true
printf '# mickys overlay %s (uninstall.sh puts the original file back)\n' "$OV" >> "$C.new"
[ "$NVENC" = off ] || printf 'NVMTL_NVENCVT=%s\n' "$NVENC" >> "$C.new"
chown root:wheel "$C.new"; chmod 644 "$C.new"; mv "$C.new" "$C"
ok "NVMTL_NVENCVT=${NVENC/off/(not set)}"

echo "== 5. command-line tools"
for f in $RC; do   # drop an earlier --cli-aliases hook; rewrite in place to keep the file's owner and mode
  [ -f "$f" ] && grep -qF "$MARK" "$f" || continue
  grep -vF "$MARK" "$f" > "$f.mickys" || true; cat "$f.mickys" > "$f"; rm -f "$f.mickys"
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
if [ $ENCONLY = 1 ]; then echo "Done. Apps you open from now on get $WHAT (quit and reopen running ones)."
else echo "Done. Log out and back in (or restart) so WindowServer and running apps load the new plugin."; fi
[ "$NVENC" = off ] || echo "Command-line tools (ffmpeg, HandBrakeCLI, avconvert) see the encoder only through nvenc-run:   nvenc-run ffmpeg ...$([ $ALIASES = 1 ] || echo "   (sudo ./install.sh --cli-aliases does that for you in zsh/bash)")"
echo "Undo: sudo $HERE/uninstall.sh   (backup: $BK)"
