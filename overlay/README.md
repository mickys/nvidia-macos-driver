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

**Optional, `--desktop`: this fork's Metal plugin.** It is NullMoth 2.5.2's plugin with this fork's changes added one by
one, each behind its own line in `/Library/GPUBundles/nvmtl/nvrm610.conf`. The ones listed as on by default below are on;
the others are off, so apart from those the plugin behaves exactly like NullMoth's. Every change was measured on its own against NullMoth's
plugin, on a GTX 1650 (NullMoth 2.5.0) and again on an RTX 4090 (NullMoth 2.5.2; macOS 26.7.1, zero-copy scan-out), with a
full-screen Metal animation while the screen was captured: by Parsec (a client connected, 20 s runs; GTX 1650) and by a
screen recording, at 1080p 165 Hz and at 4K HiDPI.

On by default, because they made capture faster or correct and added no stalls:

- **NV12 plane seed** (`NVMTL_PLANE_SEED`). WindowServer draws captured frames into two-plane (NV12) surfaces. NullMoth's
  plugin copies each plane out with a lock that moves the whole surface's seed, so the other plane looks stale and is
  uploaded again from the CPU before the next frame. The plugin remembers the seed moves of its own copy-outs instead.
- **Import cache** (`NVMTL_SURF_IMPORT_CACHE`, `NVMTL_SURF_IMPORT_CACHE_MAX_MB`). CoreAnimation wraps the same window
  surfaces in a new texture every frame, and each wrap imported the surface's video memory again (four kernel calls). The
  import is now shared by the wraps and kept briefly. The size limit per surface follows the card since 2.5.3-mickys.4:
  64 MB with 8 GB of video memory or more (4K windows and composites, ~33 MB, are cached too), 16 MB below (uncapped, the
  cache added up to 67 stalls of ~100 ms per 15 s at 4K HiDPI on a 4 GB GTX 1650; 1080p and 1440p surfaces, 8-15 MB, are
  cached there). The cache holds 128 surfaces (32 before 2.5.3-mickys.4: while the screen was captured it filled up with
  textures in use, and the same menu-bar surfaces were imported again every frame).

- **No upload of capture frames that were only read** (`NVMTL_SURFIN_READER_SKIP`, since 2.5.3-mickys.2). ScreenCaptureKit
  (Parsec, recorders) locks every captured frame read-write to read it, which moves the surface's seed as a CPU write would,
  so before drawing the next frame into that surface the plugin uploaded its system memory back to video memory (33 MB
  per frame for a 4K 10-bit capture, about 1 s of every 8 s of WindowServer's time). A surface whose seed moved by exactly
  one since the plugin's own last write, four times in a row, is taken as read, and the upload is skipped (two-plane
  surfaces likewise, after the plugin's own per-plane seed moves). RTX 4090, Parsec, same session with the skip off / on:
  4K 10-bit 30.0 / 36.9 fps, 1080p 10-bit 55.7 / 65.3, 1080p 8-bit 54.2 / 56.4; frames in order, late frames nearly gone.
- **Captured frames copied out by the GPU** (`NVMTL_GPU_COPYOUT`, since 2.5.3-mickys.3). With captured frames kept in
  order (below), WindowServer waits on every captured frame until its NV12 frame is in the surface's memory; that copy-out
  was a readback plus a CPU copy after the GPU finished (~2 ms per 1080p frame). The GPU now copies the frame into the
  surface's memory at the end of the same command buffer. RTX 4090, same session off / on, frames in order in both: Parsec
  1080p 165 Hz 8-bit 57.6 / 65.3 fps, 4K HiDPI 8-bit 30.3 / 41.1; screen recording with Screen Sharing 98-108 / 129-154.
- **Descriptor masks that count only the stage's own bindings** (`NVMTL_DESC_MASK`, since 2.5.3-mickys.4). Each draw gets a
  descriptor set holding the textures, samplers and buffers its shaders use; the plugin learns which from the shaders. A
  shader that reads the colour attachment (framebuffer fetch, a separate set) voided that list, so every draw of such a
  pipeline wrote all ~180 descriptors, almost all placeholders: WindowServer wrote 2.2 million descriptors a second while a
  window animated. That set is now left out like the texture heap: about 6 writes per draw, 35 thousand a second.
- **CPU-drawn windows uploaded without waiting** (`NVMTL_SURFIN_PAGE_CACHE`, `NVMTL_SURFIN_ASYNC`, `NVMTL_SURFIN_ORDERED`,
  since 2.5.3-mickys.4). A window drawn on the CPU (Safari and WebKit, most AppKit apps) is copied to video memory by the
  GPU straight from the surface's own pages. The pages were imported (wired and mapped by the kernel: ~8100 pages for a 4K
  window) and released for every upload, and WindowServer waited for each copy. The import is now kept per surface (up to
  64 surfaces, at most 512 MB wired, released 2 s after their last upload) and the copy is not waited for: the GPU runs it
  before the command buffer that draws the window, and the plugin finishes it before the window's texture is read back,
  uploaded again or freed. The copy now also waits for earlier GPU reads of the texture (`NVMTL_SURFIN_ORDERED`).

| RTX 4090, full-screen Safari animation (drawn on the CPU), 2.5.3-mickys.3 / this release | 1080p 165 Hz | 4K HiDPI 60 Hz |
|---|---|---|
| local display, screen updates/s | 67-68 / **131-135** | 48.5-50 / **60** (the refresh rate) |
| WindowServer CPU (user + system, of one core) | 46+28 % / 66-67+13 % | 34+28 % / 43+7 % |
| Parsec, fps sent (frames in order in both) | 29.2 / **46.7-46.9** | 15.1-16.1 / 16.8-17.6 |

A full-screen Metal app is level (153-162 / 155-165 fps without capture; through Parsec 63.7-64.8 / 65.9-68.7 fps). Every
recorded frame of eight screen recordings was decoded: none out of order, garbled or torn.

- **Captured frames in order** (`NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=3`). WindowServer draws each captured frame into a
  two-plane (NV12) surface, which the plugin writes through a private image and copies out when the GPU has finished. The
  recorder or streamer (ScreenCaptureKit, Parsec) reads the surface as soon as WindowServer's command buffer is scheduled,
  about 1 ms after the commit, so it sometimes got the previous frame: a stream that jumps back a frame now and then. Such a
  command buffer now reports "scheduled" after its copy-out. It costs nothing without capture; while capturing, the captured
  app runs ~15 % slower (still faster than with NullMoth's plugin, which has the jumps too):

| RTX 4090, 1080p 165 Hz, Metal animation recorded with Screen Sharing connected | app fps | frames out of order per 20 s |
|---|---|---|
| NullMoth 2.5.2 | 81-93 | 142-183 |
| plane seed + import cache | 107-128 | 12-55 |
| `--desktop` (default: also captured frames in order) | 90-103 | 0 |
| without capture: plane seed + import cache / default | 136-152 / 133-150 | |

RTX 4090, NullMoth 2.5.2, macOS 26.7.1, 1080p 165 Hz, a full-screen Metal animation while the screen is recorded (one boot,
20 s runs):

| | NullMoth 2.5.2 | plane seed only | plane seed + import cache (without the frame-order fix) |
|---|---|---|---|
| app fps | 95-107 | 103-131 | 137-159 |
| ~100 ms stalls per 20 s | 0 | 0 | 0 |

At 4K HiDPI (60 Hz) every configuration holds 58-60 fps while recording; with macOS Screen Sharing connected too, 0-2 stalls
per 20 s with the cache off, on or capped alike.

Earlier, on a GTX 1650 with NullMoth 2.5.0 (the import cache uncapped and opt-in then):

| with a full-screen animation running | NullMoth 2.5.0 | plane seed only | plane seed + import cache (uncapped) |
|---|---|---|---|
| 1080p 165 Hz, Parsec: app fps / ~100 ms stalls per 20 s | 50 / 1 | 50 / 0 | **60-62 / 0** |
| 1080p 165 Hz, screen recording: app fps | 105-110 | 118-131 | 157-161 |
| 4K HiDPI, screen recording with Screen Sharing: app fps / stalls per 15 s | 22-28 / 0 | 25 / 1 | 14-37 / **2-67** |
| Safari animation in a 1600x900 window (1080p), screen updates/s | 65.5 | | 78.6 |

Off by default (put the line into `nvrm610.conf`, then log out and in):

| line | what it does | why it is off |
|---|---|---|
| `NVMTL_GPU_COPYOUT=0` | turns the GPU copy-out of captured frames off | (on by default) |
| `NVMTL_DESC_MASK=0` | descriptor sets of framebuffer-fetch pipelines written in full again | (on by default) |
| `NVMTL_SURFIN_ASYNC=0` | WindowServer waits for each CPU-drawn window's upload again | (on by default) |
| `NVMTL_SURFIN_PAGE_CACHE=0` | a CPU-drawn window's pages are imported and released for every upload again (also turns `NVMTL_SURFIN_ASYNC` off) | (on by default) |
| `NVMTL_SURFIN_ORDERED=0` | the upload no longer waits for earlier GPU reads of the window's texture | (on by default) |
| `NVMTL_SURFIN_READER_SKIP=0` | turns the capture-frame upload skip off | (on by default) |
| `NVMTL_PLANE_SEED=0` | turns the plane seed off | (on by default) |
| `NVMTL_SURF_IMPORT_CACHE=0` | turns the import cache off | (on by default) |
| `NVMTL_SURF_IMPORT_CACHE_MAX_MB=N` | the cache's size limit per surface (default 64 with 8 GB of video memory or more, else 16; `0` = no limit) | without a limit, up to 67 stalls per 15 s at 4K HiDPI on a GTX 1650 |
| `NVMTL_SURF_IMPORT_CACHE_IDLE_MS=N` | how long an import stays after its last wrap goes (default 2000) | 100 ms: no difference at 4K |
| `NVMTL_SURFIN_UPLOAD=cpu` | turns off the GPU upload of CPU-drawn windows (WebKit, CoreGraphics apps) from their own pages; NullMoth took it from this fork in 2.5.1 and has it on by default | (on by default in NullMoth's plugin and in this one; level with it off on an RTX 4090 at 1080p 165 Hz) |
| `NVMTL_TEX_POOL=1` | CoreAnimation's per-frame intermediate textures (blur, vibrancy) reuse released ones instead of new allocations | no measurable change |
| `NVMTL_ASYNC_SURFIN=2` | upstream PR #96: a CPU surface upload does not wait for its GPU copy before the next one starts | **under Parsec: 36 stalls of ~100 ms per 20 s, 41 instead of 50 fps, frames jumping back** |
| `NVMTL_SURF_MULTIPLANE=1` | two-plane (NV12) surfaces share their video memory with other processes, so a reader's CPU lock waits in the kernel | **12 stalls of ~100 ms per 20 s of screen recording**: the reader's page-off waits for the GPU with the accelerator lock held |
| `NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=0` | turns the frame-order fix off (on by default, `=3`; see below) | (on by default) |
| `NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=2` / `=1` | the frame-order fix for every surface written through a private image / every surface write | `=2` orders capture as well as `=3` at the same cost; `=1` slows every app |
| `NVMTL_WS_MARK_CONN=1` | WindowServer's completion marks go to the kernel on a connection of their own | fixed ~117 ms freezes on 2.4.3; none on 2.5.0 without it |
| `NVMTL_DIRTY_MARK_CONN=1` | the same for video-memory dirty marks | no change on 2.5.0 |
| `NVMTL_SURF_USE_COUNT=1` (every surface) / `=2` (only surfaces written) | IOSurfaces count as in use while GPU work uses them, as on Apple's drivers | with `1`, every app waited a display refresh longer for its next drawable: a full-screen Metal app ran at 72 fps at 144 Hz (NullMoth: 102-136) |

The plugin replaces NullMoth's plugin binary, so a problem in it affects the whole desktop: try it, and go back with
`sudo ./install.sh` (without `--desktop`) or `sudo ./uninstall.sh`.

## Performance

Against NullMoth's driver on its own (details, release by release and per card: [PERFORMANCE.md](PERFORMANCE.md)):

- **RTX 4090:** hardware encoding for every VideoToolbox app (NullMoth has no encoder for Ada); H.264 decode 666 / 190 fps
  at 1080p / 4K against 160 / 38, VP9 and AV1 decode (none in NullMoth's); a screen recording with Screen Sharing
  connected at 1080p 165 Hz 129-154 fps with every frame in order against 81-93 fps with 142-183 frames out of order per
  20 s; Parsec (1080p 165 Hz, 8-bit) 56-65 fps with frames in order, against 4-8 fps with NullMoth's driver alone (software
  encoding) and 49-50 fps with 342-353 frames out of order per 30 s with only the overlay's encoder; at 4K 37-41 fps
  against 3 / 31; the desktop without capture level.
- **GTX 1650:** hardware encoding (NullMoth's encoders do not register on TU117); H.264 decode 447 / 121 fps against
  154 / 36, VP9 decode; Parsec 60-62 against 50 fps at 1080p (NullMoth 2.5.0).

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
120 / 144 Hz; 1080p at 144 Hz set and shown. On NullMoth 2.5.0 the same: the desktop at 1080p 165 Hz from the override. NullMoth 2.5.2 adds scaled and HiDPI modes through the display engine's scaler (its #273), and the overlay's framebuffer has them too: on an RTX 4090 with a 1080p 165 Hz dummy plug, NullMoth 2.5.2 lists 119 modes (all 60 Hz, the plug's EDID), with `--resolution` 164 (up to 165 Hz); every distinct mode of each list (80 and 120) was switched to and shown.

Add only timings the display can show: a real monitor may stay black on one it does not support (remove the file over
SSH or from safe mode to recover). Overrides are refused unless root-owned and not writable by others, valid, and for the
same vendor and product as the display. Changing the framebuffer rebuilds the Auxiliary Kernel Collection (as NullMoth's
installer does) and needs a restart.

**Not part of the overlay, but worth more than any of it: boot without `-nvrmnoflip`.** With that boot-arg (the copy-path
scan-out; some guides and this VM's own setup used it because screen capture read black with zero-copy on driver 2.3.3) the
kernel copies every display frame to the panel from the composite's system memory, so it first pages the whole 8 MB
composite off VRAM, ~2 ms with the accelerator lock held, ~100 times a second. Since the kernel's page-off waits for the GPU
(2.3.7+), capture works with zero-copy scan-out. Measured on a GTX 1650 at 1080p/165 Hz (2.4.3, 2026-10-21): a full-screen
GPU app 140-150 -> 157-164 fps, Parsec 55-60 -> 60-66 fps, screencapture recordings correct. Check: `sysctl
debug.nvaccel_iop_flip` is 1; try it live with `sudo sysctl -w debug.nvaccel_iop_flip=1`.

**Optional, `--event-wait`: less CPU while apps wait for the GPU.** NullMoth's plugin lets ordinary apps poll for GPU
completion (WindowServer already waits for an event). `--event-wait` writes `NVRM_EVENT_WAIT=1` into `nvrm610.conf`, a
setting NullMoth's driver has (its `docs/EVENT-WAIT.md`), so apps sleep until the GPU signals. Measured on a GTX 1650: a
full-screen Metal animation keeps its frame rate with 15 % less CPU; NullMoth's probe uses 79 % less CPU in a compute loop
and 29 % less in a Core Image blur, while the synchronous elapsed time grows by 2-4 %. Apps opened afterwards use it;
`sudo ./install.sh` without it (or `uninstall.sh`) removes the line again.

## Requirements

- NullMoth's driver **2.5.3** (or 2.5.2) installed and running. The installer refuses anything else: it checks NullMoth's
  version record, the version of the NVRM, NVAccel and NVRMFB kernel extensions on disk, and the version of the ones
  running (after a NullMoth update, restart before installing the overlay). The plugin and the kernel driver share
  interfaces, so an overlay lists the NullMoth versions it was built for (`COMPATIBLE-DRIVERS` in the package). 2.5.3
  changes only NVRM's handling of `nvregdwords=`; its NVAccel, NVRMFB and Metal plugin are byte for byte 2.5.2's.
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
sudo ./install.sh --event-wait         # apps wait for the GPU with an event instead of polling (any combination)
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

- Framebuffer (`--resolution`): `kexts/NVRMFB` at the same tag (NullMoth 2.5.2 plus three commits), built with
  `build/fb_build.sh` against NVIDIA's open-gpu-kernel-modules 615.78.08 headers (NullMoth 2.5.2's RM version; the same
  script builds NullMoth's own 2.5.2 NVRMFB byte for byte); `nvfb-edid` from `tools/nvfb-edid.c`.
- Plugin (`--desktop` only): `plugin/` of [mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver) at the tag named in
  `SOURCE` (NullMoth 2.5.2 plus the overlay's commits, each behind a config line), built as a release (`NVMTL_RELEASE=1`, macOS 15.0 minimum).
- Encoder: [mickys/nvenc](https://github.com/mickys/nvenc) at the commit named in `SOURCE`.
- The plugin source is under the PolyForm Noncommercial License 1.0.0 (`LICENSE`), like NullMoth's. The encoder is MIT
  (`LICENSE-nvenc`).
