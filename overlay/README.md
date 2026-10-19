# mickys overlay for NullMoth's NVIDIA driver

An **unofficial** add-on for [NullMoth's driver](https://github.com/nullmoth/nvidia-macos-driver): an open-source hardware
video encoder for RTX 40 cards, and optionally a test build of the Metal plugin from
[mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver) (branch `dev`). It is not made, reviewed or
supported by NullMoth. Report problems with it at
[mickys/nvidia-macos-driver issues](https://github.com/mickys/nvidia-macos-driver/issues), not upstream.

By default it replaces nothing: NullMoth's plugin loads `libnvencvt.dylib` by itself since 2.3.7, so the overlay adds the
library next to it, one line in `nvrm610.conf` and `/usr/local/bin/nvenc-run`. With `--desktop` it also replaces the Metal
plugin binary (`NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver`) with this fork's build. The kernel extensions, firmware
and everything else always stay NullMoth's.

## What it changes

**Hardware H.264 and HEVC encoding on RTX 40 (Ada).** NullMoth's driver registers its NVENC encoders only on Blackwell
(RTX 50), so on older cards VideoToolbox encodes in software. The overlay adds an open-source encoder for Ada NVENC
([mickys/nvenc](https://github.com/mickys/nvenc), `libnvencvt.dylib`). Since 2.3.7 NullMoth's plugin has a hook for exactly
this: with `NVMTL_NVENCVT` set in `nvrm610.conf` it loads `libnvencvt.dylib` from its own bundle (never into WindowServer,
and only if the library and its folder are owned by root and not writable by group or others), and VideoToolbox picks
it over NullMoth's encoders by rating (1100). The encoder is available to every app that uses
VideoToolbox (Parsec, OBS, AVFoundation apps, ...), and to command-line tools through `nvenc-run` (see below). Parsec at 4K: about 5 ms per frame with either codec; HEVC needs about 40 % less bitrate for the
same quality. It checks the GPU first and stays off on cards without Ada NVENC (RTX 20/30 and GTX 16 keep Apple's
encoder). HEVC Main 10 (10-bit) too: Parsec's "prefer 10-bit color" at 4K takes about 7 ms per frame. H.264 uses High profile with
CABAC by default (much better quality at the same bitrate; apps that ask for Baseline get Main with CAVLC). Full-range
input is signalled as full range. Profiles: H.264 Baseline/Main/High, HEVC Main and Main 10, 4:2:0; no B-frames.

**Optional, `--desktop`: faster desktop with large CPU-drawn windows.** When WindowServer composites a window that an
app drew with the CPU (every WebKit view, including Safari and Mail, and CoreGraphics apps), NullMoth's plugin copies
the window's pages into video memory with the CPU, and the pages are faulted in again for every frame. This fork's
plugin lets the GPU copy them, and WindowServer keeps the surfaces it uploads mapped. Measured on an RTX 4090 with
NullMoth 2.3.7 (macOS 26.7.1, in a VM), Safari playing a CSS animation:

| window | plugin | per upload | screen updates/s | WindowServer CPU (user + system) | Safari's painting process |
|---|---|---|---|---|---|
| 3840x2110 (full screen, 4K) | NullMoth 2.3.7 | 19.7 ms | 21 | 73 % of a core | 470 % |
| 3840x2110 (full screen, 4K) | `--desktop` | 7.8 ms | 34 | 55 % | 265 % |
| 3200x1800 | NullMoth 2.3.7 | ~7 ms | 38.6 | 59 % | 220 % |
| 3200x1800 | `--desktop` | ~6.4 ms | 41.1 | 55 % | 200 % |

Worth it on a 4K (or larger) display with big Safari, Mail or other WebKit windows; with smaller windows the difference
is small since 2.3.7. It replaces NullMoth's plugin binary, so a problem in it affects the whole desktop: try it, and go
back with `sudo ./install.sh` (without `--desktop`) or `sudo ./uninstall.sh`. Its two parts can be turned off with
`NVMTL_SURFIN_UPLOAD=cpu` (GPU copy) and `NVMTL_SURFIN_KEEP=0` (keep mapped) in `/Library/GPUBundles/nvmtl/nvrm610.conf`,
then log out and in.

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

## Requirements

- NullMoth's driver **2.3.7** installed and running. The installer refuses anything else: it checks NullMoth's version
  record, the version of the NVRM, NVAccel and NVRMFB kernel extensions on disk, and the version of the ones running
  (after a NullMoth update, restart before installing the overlay). The plugin and the kernel driver share interfaces,
  so an overlay is built for one NullMoth version (`COMPATIBLE-DRIVERS` in the package).
- An x86_64 Mac (Intel or AMD hackintosh) running macOS 15 or 26, as NullMoth's driver requires. Tested only on
  macOS 26.7.1 with an RTX 4090 so far.
- The encoder part needs an RTX 40 card. The desktop part works on every card the driver supports.

## Install

```bash
tar -xzf mickys-overlay-<version>.tar.gz && cd mickys-overlay-<version>
sudo ./install.sh                      # encoder for every app; NullMoth's plugin stays exactly as it is
sudo ./install.sh --nvenc=parsecd,obs  # encoder only for these processes
sudo ./install.sh --cli-aliases        # and ffmpeg/HandBrakeCLI/avconvert through nvenc-run in Terminal
sudo ./install.sh --desktop            # also this fork's plugin build (see "What it changes")
sudo ./install.sh --desktop --nvenc=off  # the plugin build only, no encoder
```

Apps you open afterwards get the encoder; with `--desktop`, log out and back in (or restart) so WindowServer loads the
plugin. The installer checks every file against `SHA256SUMS`, backs up the current plugin, its signature and
`nvrm610.conf` to `/Library/NullMoth/overlay-backup-<date>`, installs, re-signs the bundle (only with `--desktop`) and sets
`NVMTL_NVENCVT` in `nvrm610.conf`, and installs `/usr/local/bin/nvenc-run` (unless `--nvenc=off`).

## Undo

```bash
sudo ./uninstall.sh
```

It puts the plugin, its signature and `nvrm610.conf` back exactly as they were, and removes `libnvencvt.dylib`,
`nvenc-run` and the `--cli-aliases` lines. Then log out and back in. Updating NullMoth's driver also replaces the overlay (its installer writes the whole bundle).

## Check that it is active

- `codesign -dv /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver` and compare the hash with
  `SHA256SUMS`, or `shasum -a 256` the file.
- Encoder: apps list it as "NVENC - H.264 - (NVIDIA <your card>) - mickys/nvenc - <version>" /
  `org.nvenc.videoencoder.avc` and "NVENC - HEVC - (NVIDIA <your card>) - mickys/nvenc - <version>" /
  `org.nvenc.videoencoder.hevc` (for example "NVENC - H.264 - (NVIDIA RTX 4090) - mickys/nvenc - 0.7.0");
  Parsec's host log (`~/.parsec/log.txt`) says `encoder = Hardware`.
- Command line: `nvenc-run ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 5 -c:v hevc_videotoolbox -b:v 20M /tmp/t.mp4`
  writes a 5-second HEVC file (about 1.3 s on an RTX 4090); without `nvenc-run` the same command fails with
  `Cannot create compression session: -12908`.

## Source

- Plugin: `plugin/` of [mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver) at the tag named in
  `SOURCE` (NullMoth 2.3.7 plus the overlay's commits), built as a release (`NVMTL_RELEASE=1`, macOS 15.0 minimum).
- Encoder: [mickys/nvenc](https://github.com/mickys/nvenc) at the commit named in `SOURCE`.
- The plugin source is under the PolyForm Noncommercial License 1.0.0 (`LICENSE`), like NullMoth's. The encoder is MIT
  (`LICENSE-nvenc`).
