# mickys overlay for NullMoth's NVIDIA driver

An **unofficial** add-on for [NullMoth's driver](https://github.com/nullmoth/nvidia-macos-driver): open-source hardware
video encoders and decoders for RTX 40 cards and the GTX 1650, and optionally a test build of the Metal plugin from
[mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver) (branch `dev`). It is not made, reviewed or
supported by NullMoth. Report problems with it at
[mickys/nvidia-macos-driver issues](https://github.com/mickys/nvidia-macos-driver/issues), not upstream.

By default it replaces nothing: NullMoth's plugin loads `libnvencvt.dylib` by itself since 2.3.7, so the overlay adds the
library next to it, one line in `nvrm610.conf` and `/usr/local/bin/nvenc-run`. With `--desktop` it also replaces the Metal
plugin binary (`NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver`) with this fork's build, and with `--resolution` the
framebuffer kernel extension's binary (`NVRMFB.kext/Contents/MacOS/NVRMFB`). Either, both or neither; NVRM, NVAccel,
the firmware and everything else always stay NullMoth's.

## What it changes

**Hardware video encoding and decoding on RTX 40 (Ada) and the GTX 1650 (TU117).** NullMoth's driver has no NVENC encoder
for Ada or for the GTX 1650's older NVENC (it ships them for RTX 20, 30 and 50), so on those cards VideoToolbox encodes in
software. The overlay adds open-source encoders and
decoders for these cards' NVENC and NVDEC ([mickys/nvenc](https://github.com/mickys/nvenc), `libnvencvt.dylib`). Since 2.3.7
NullMoth's plugin has a hook for exactly this: with `NVMTL_NVENCVT` set in `nvrm610.conf` it loads `libnvencvt.dylib` from
its own bundle (never into WindowServer, and only if the library and its folder are owned by root and not writable by
group or others), and VideoToolbox picks it over the other codecs by rating (1100). It is available to every app that
uses VideoToolbox (Parsec, OBS, QuickTime and other AVFoundation apps), and to command-line tools through `nvenc-run`
(see below). It checks the GPU first and stays off on other cards (RTX 20 / 30 / 50 keep NullMoth's encoders).

On the GTX 1650 (TU117) the hardware has no AV1 and no HEVC B pictures, so the overlay offers H.264 (with B pictures) and
HEVC (P only) encoders and every decoder but AV1; VP9 from 65x65 up.

- **Encoders:** H.264 (Baseline / Main / High with CABAC, 4:4:4), HEVC (Main, Main 10, 4:4:4) and AV1 (8 / 10-bit, up to 8K).
  Two B pictures between anchors when the app allows frame reordering and is not real time (recordings and exports;
  Parsec and other streaming stays P-only, about 2 ms per 1080p and 5-6 ms per 4K frame), NVIDIA's quality settings where
  the frame rate allows, CBR and capped VBR on target, colour description and HDR10 metadata. Quality at the same bitrate
  (VMAF, 1080p and 4K test clips): AV1 above x265 medium, HEVC level with x265, H.264 at or above x264 medium, at 3-10x
  their speed. [Benchmarks](https://github.com/mickys/nvenc/blob/main/docs/benchmarks.md).
- **Decoders:** H.264, HEVC (8-12 bit), VP9, AV1, MPEG-1/2 and MPEG-4 Part 2, bit-exact against ffmpeg on the conformance
  streams. 4K: H.264 about 210 fps (NullMoth's decoder: 40, Apple's software decoder: 24), HEVC about 350, VP9 340, AV1
  380 (the only hardware VP9 and AV1 decoding on an Intel Mac). `--no-decoders` keeps only the encoders.

**Optional, `--desktop`: faster desktop with large CPU-drawn windows.** When WindowServer composites a window that an
app drew with the CPU (every WebKit view, including Safari and Mail, and CoreGraphics apps), NullMoth's plugin copies
the window's pages into video memory with the CPU. WindowServer lets go of the surface after each frame, so the pages
are faulted in again for every upload, and for a large window most of the copy is page faults. This fork's plugin
imports the locked pages as host memory and lets the GPU copy them (falling back to the CPU copy when they cannot be
imported); that change is 48 lines on top of NullMoth's plugin, the same one proposed to NullMoth. Measured on an RTX 4090
with NullMoth 2.4.3 (macOS 26.7.1, in a VM), Safari playing a CSS animation, 2 x 3 x 20 s each (stock and patched passes
alternating; 2.3.7 gave the same):

| window | plugin | screen updates/s (avg) | WindowServer CPU (user + system) | Safari's painting process |
|---|---|---|---|---|
| 3840x2110 (full screen, 4K) | NullMoth 2.4.3 | 20.6 | 73 % of a core | 459 % |
| 3840x2110 (full screen, 4K) | `--desktop` | 34.6 (+67 %) | 55 % | 255 % |
| 3200x1800 | NullMoth 2.4.3 | 40.3 | 58 % | 215 % |
| 3200x1800 | `--desktop` | 42.9 (+6 %) | 55 % | 198 % |

Since 2.4.3-mickys.6 the `--desktop` build also carries three fixes for screen capture and compositing (Parsec, OBS
display capture, screen recording, and the desktop itself):

- **NV12 capture surfaces stay in step:** WindowServer draws captured frames into two-plane (NV12) surfaces. NullMoth's
  plugin copied each plane out with a lock that moved the whole surface's seed, so the other plane looked stale and was
  uploaded again from the CPU before every frame, one plane at a time. The plugin now remembers the seed moves of its own
  copy-outs. This removes the per-frame uploads and the horizontal tearing they caused in the streamed picture.
- **One VRAM import per surface:** CoreAnimation wraps the same window surfaces in a new texture for every frame, and each
  wrap imported the surface's VRAM again (four kernel calls, ~0.6 ms in WindowServer). The import is now shared and kept
  briefly (`NVMTL_SURF_IMPORT_CACHE=0` turns it off).
- **Texture pool:** CoreAnimation's per-frame intermediate textures (blur, vibrancy) reuse recently released ones of the
  same size and format instead of a new VRAM allocation each (`NVMTL_TEX_POOL=0` turns it off).

Measured on a GTX 1650 (NullMoth 2.4.3, macOS 26.7.1), 1920x1080 at 144 Hz:

| test | NullMoth 2.4.3 | with the three fixes |
|---|---|---|
| Parsec streaming a full-screen GPU animation | 46-47 fps, encode latency 3.6 ms, tearing | **71-72 fps (+53 %)**, 3.0 ms, no tearing |
| the same animation, no streaming | 118-132 fps | 139-142 fps (the 144 Hz limit) |

Desktop benchmark (Safari animation, updates/s): full-screen 1080p 66.0 -> 71.8 (Safari's own painting limit); full-screen 4K
HiDPI 15.3 -> 19.9 (2.4.3-mickys.5 `--desktop`: 19.4), WindowServer CPU 73 -> 60 % of a core.

Per upload of the full-screen window (diagnostic build on 2.3.7): 19.7 ms with the CPU copy, 7.7 ms from the imported pages. Worth it on a 4K (or
larger) display with big Safari, Mail or other WebKit windows; with smaller windows NullMoth's plugin is as fast. It
replaces NullMoth's plugin binary, so a problem in it affects the whole desktop: try it, and go back with
`sudo ./install.sh` (without `--desktop`) or `sudo ./uninstall.sh`. `NVMTL_SURFIN_UPLOAD=cpu` in
`/Library/GPUBundles/nvmtl/nvrm610.conf` turns the GPU copy off (log out and in afterwards).

## Command-line tools

ffmpeg, HandBrakeCLI, `avconvert` and other command-line tools don't see the encoder by themselves: VideoToolbox lists
it only in processes that load `libnvencvt.dylib`, and the Metal plugin loads it only when a process first uses Metal,
which these tools never do (they get `-12908`, no hardware encoder, or fall back to software). The installer adds
`/usr/local/bin/nvenc-run`, which runs a tool with the encoder loaded:

```bash
nvenc-run ffmpeg -i in.mov -c:v hevc_videotoolbox -b:v 20M out.mp4     # or h264_videotoolbox; -profile:v main10 for 10-bit
nvenc-run HandBrakeCLI -i in.mkv -o out.mp4 -e vt_h265
nvenc-run avconvert --preset PresetHEVCHighestQuality --source in.mov --output out.mov
```

`sudo ./install.sh --cli-aliases` also makes `ffmpeg`, `HandBrakeCLI` and `avconvert` go through `nvenc-run` in new
Terminal windows (zsh, and bash login shells: a line in `/etc/zshrc` and `/etc/bashrc`; `command ffmpeg ...` bypasses
it once).
Nothing else is loaded into other programs: the overlay never sets `DYLD_INSERT_LIBRARIES` globally.

Why a wrapper: macOS has no way for a third party to register a video encoder for every process. VideoToolbox only
loads encoder plug-in bundles signed by Apple, and MediaExtension (macOS 15+) has extension points for decoders but not
for encoders. `nvenc-run` sets `DYLD_INSERT_LIBRARIES` for the one tool. That works for unsigned tools (ffmpeg builds
from evermeet.cx or Homebrew) and, with the boot settings NullMoth's driver needs (relaxed SIP, `amfi_get_out_of_my_way`),
also for hardened and Apple binaries such as `/usr/bin/avconvert`; on a stock Mac those would drop the variable.

**Optional, `--resolution`: more desktop sizes and refresh rates.** NullMoth's framebuffer offers only display timings at
least as large as the boot screen, and leaves smaller desktops to macOS's scaled modes. Where those cannot be shown (NVKMS
refuses scaled modes on some rasters, for example the 4K-only boot raster of an HDMI dummy plug), the desktop cannot go
below the boot size. This fork's framebuffer build also offers the smaller timings the display lists and NVKMS validates
(turned on by `/Library/NullMoth/nvfb-small`; a boot-arg `nvfbsmall=0` / `=1` overrides the file). It also reads EDID
overrides: `/Library/NullMoth/edid-override/<vendor>-<product>.bin`, the display's own EDID plus extra detailed timings,
handed to NVKMS with every display query, so NVKMS validates them against the link and macOS lists them. The
`nvfb-edid` tool writes them:

```bash
nvfb-edid list                                    # connected displays, their timings, override state
sudo nvfb-edid add 1920x1080@144 2560x1440@120    # up to 6 extra timings (CVT reduced blanking v2); restart
sudo nvfb-edid remove                             # the display's own EDID again; restart
```

Measured on a GTX 1650 with a 4K HDMI dummy plug (NullMoth 2.4.3, macOS 26.7.1): NullMoth's framebuffer lists 9 timings,
all 4K (smaller desktops only as scaled modes, which NVKMS refuses on that raster); with `--resolution` 35 (1080p, 1440p,
720p and the other sizes in the plug's EDID), and 41 with an override adding 1080p at 120 / 144 / 165 / 240 Hz and 1440p at
120 / 144 Hz; 1080p at 144 Hz set and shown.

Add only timings the display can show: a real monitor may stay black on one it does not support (remove the file over
SSH or from safe mode to recover). Overrides are refused unless root-owned and not writable by others, valid, and for the
same vendor and product as the display. Changing the framebuffer rebuilds the Auxiliary Kernel Collection (as NullMoth's
installer does) and needs a restart.

## Requirements

- NullMoth's driver **2.4.3** installed and running. The installer refuses anything else: it checks NullMoth's version
  record, the version of the NVRM, NVAccel and NVRMFB kernel extensions on disk, and the version of the ones running
  (after a NullMoth update, restart before installing the overlay). The plugin and the kernel driver share interfaces,
  so an overlay is built for one NullMoth version (`COMPATIBLE-DRIVERS` in the package).
- An x86_64 Mac (Intel or AMD hackintosh) running macOS 15 or 26, as NullMoth's driver requires. Tested only on
  macOS 26.7.1 with an RTX 4090 and a GTX 1650 so far.
- The encoder part needs an RTX 40 card or a GTX 1650 (TU117: GTX 1650, T400 / T600 / T1000). The desktop and resolution parts work on every card the driver supports.

## Install

```bash
tar -xzf mickys-overlay-<version>.tar.gz && cd mickys-overlay-<version>
sudo ./install.sh                      # encoder for every app; NullMoth's plugin stays exactly as it is
sudo ./install.sh --nvenc=parsecd,obs  # encoder only for these processes
sudo ./install.sh --cli-aliases        # and ffmpeg/HandBrakeCLI/avconvert through nvenc-run in Terminal
sudo ./install.sh --no-decoders        # the encoders only (NVENCVT_NO_DEC=1 in /usr/local/etc/nvencvt.conf)
sudo ./install.sh --desktop            # also this fork's plugin build (see "What it changes")
sudo ./install.sh --desktop --nvenc=off  # the plugin build only, no encoder
sudo ./install.sh --resolution         # also this fork's framebuffer build: smaller desktops, EDID overrides (restart)
sudo ./install.sh --desktop --resolution  # both
```

Each run installs exactly the parts named: running `sudo ./install.sh` again without `--desktop` or `--resolution` puts
NullMoth's plugin or framebuffer back (the backup stays the one from the first install).

Apps you open afterwards get the encoder; with `--desktop`, log out and back in (or restart) so WindowServer loads the
plugin. The installer checks every file against `SHA256SUMS`, backs up the current plugin, its signature and
`nvrm610.conf` to `/Library/NullMoth/overlay-backup-<date>`, installs, re-signs the bundle (only with `--desktop`) and sets
`NVMTL_NVENCVT` in `nvrm610.conf`, and installs `/usr/local/bin/nvenc-run` (unless `--nvenc=off`). With `--resolution`
it also backs up NullMoth's NVRMFB binary, installs this fork's, rebuilds the Auxiliary Kernel Collection (about a minute;
it keeps the old collection unless all of NullMoth's kernel extensions made it into the new one) and installs
`/usr/local/bin/nvfb-edid`; restart afterwards.

## Undo

```bash
sudo ./uninstall.sh
```

It puts the plugin, its signature and `nvrm610.conf` back exactly as they were, and removes `libnvencvt.dylib`,
`nvenc-run`, the `--cli-aliases` lines and the `--no-decoders` setting; after `--resolution` it also puts NullMoth's
NVRMFB back (kernel collection rebuilt) and removes `nvfb-edid` and `/Library/NullMoth/nvfb-small` (EDID override files
stay: NullMoth's framebuffer ignores them). Then log out and back in, or restart after `--resolution`. Updating NullMoth's driver also replaces the overlay (its installer writes the whole bundle).

## Check that it is active

- `codesign -dv /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver` and compare the hash with
  `SHA256SUMS`, or `shasum -a 256` the file.
- Encoder: apps list it as "NVENC - H.264 - (NVIDIA <your card>) - mickys/nvenc - <version>" /
  `org.nvenc.videoencoder.avc` and "NVENC - HEVC - (NVIDIA <your card>) - mickys/nvenc - <version>" /
  `org.nvenc.videoencoder.hevc`, and AV1 (for example "NVENC - H.264 - (NVIDIA RTX 4090) - mickys/nvenc - 0.9.2");
  Parsec's host log (`~/.parsec/log.txt`) says `encoder = Hardware`.
- Command line: `nvenc-run ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 5 -c:v hevc_videotoolbox -b:v 20M /tmp/t.mp4`
  writes a 5-second HEVC file (about 1.3 s on an RTX 4090); without `nvenc-run` the same command fails with
  `Cannot create compression session: -12908`.

## Source

- Framebuffer (`--resolution`): `kexts/NVRMFB` at the same tag (NullMoth 2.4.3 plus three commits), built with
  `build/fb_build.sh`; `nvfb-edid` from `tools/nvfb-edid.c`.
- Plugin (`--desktop` only): `plugin/` of [mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver) at the tag named in
  `SOURCE` (NullMoth 2.4.3 plus the overlay's commits), built as a release (`NVMTL_RELEASE=1`, macOS 15.0 minimum).
- Encoder: [mickys/nvenc](https://github.com/mickys/nvenc) at the commit named in `SOURCE`.
- The plugin source is under the PolyForm Noncommercial License 1.0.0 (`LICENSE`), like NullMoth's. The encoder is MIT
  (`LICENSE-nvenc`).
