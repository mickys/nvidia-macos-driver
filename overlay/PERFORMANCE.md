# Performance of the mickys overlay

What the overlay changes in speed, compared with NullMoth's driver on its own ("stock") and release by release, on the two
cards it has been tested on. Every number comes from a test run during that release's development; nothing is estimated.
Where a comparison was not measured, the table says so.

**Test machine:** macOS 26.7.1 in a KVM virtual machine with the GPU passed through (AMD Ryzen 9 3950X host), a dummy
HDMI plug showing 1080p at 165 Hz (with `--resolution`; 60 Hz without), zero-copy scan-out. Cards: **RTX 4090** (Ada,
Gigabyte) and **GTX 1650** (Turing TU117, ASUS). One machine: absolute numbers on a Mac Pro or a Hackintosh will differ;
the differences between configurations are the point.

**How it is measured:** a full-screen Metal animation (frames per second it draws, with a frame counter drawn into every
frame); a full-screen Safari page animating a gradient and a frame counter strip, drawn on the CPU like most windows (screen
updates per second); Parsec with a client connected (frames per second Parsec sends; the encoder reads the frame counter back
to check that frames arrive in order); macOS screen recording, also with macOS Screen Sharing connected (frames recorded and
their order); the encoders and decoders through VideoToolbox. **Local display** = nothing captures the screen; **capture** =
Parsec or a screen recording runs, which makes WindowServer composite every window a second time. Comparisons inside one release were run in the same boot or the
same client session, back to back, at least twice.

## Overall: the overlay vs NullMoth's driver

### RTX 4090 (Ada)

| | NullMoth's driver | with the overlay (latest) | since |
|---|---|---|---|
| Hardware video encoding (VideoToolbox, every app) | none on Ada | H.264, HEVC (8 / 10-bit, 4:4:4), AV1; real time 1080p 1.2 ms per frame, 4K 4.3 ms | 2.3.6-mickys.2 |
| H.264 decode, 1080p / 4K | 160 / 38 fps | **666 / 190 fps** | 2.4.3-mickys.1 |
| HEVC decode, 1080p / 4K | 833 / 305 fps | 933 / 310 fps | 2.4.3-mickys.1 |
| VP9 / AV1 decode, 4K | none / none | 306 / 295 fps | 2.4.3-mickys.1 |
| Decoding in ffmpeg (`-hwaccel videotoolbox` through `nvenc-run`), 4K AV1 / HEVC / VP9 | AV1 / VP9: none; HEVC not measured | **125 / 115 / 158 fps** (2.5.3-mickys.5: 40 / 35 / 39) | 2.5.3-mickys.6 |
| Screen recording with Screen Sharing connected, 1080p 165 Hz: app fps, frames out of order per 20 s | 81-93 fps, 142-183 out of order (NullMoth 2.5.2) | **129-154 fps, 0 out of order** | 2.5.3-mickys.3 |
| Parsec, 1080p 165 Hz, 8-bit (fps sent; frames out of order per 30 s) | **4.1-7.6 fps**, software encoding, 126-199 ms per frame (no hardware encoder on Ada); with the overlay's encoder but NullMoth's plugin: 48.9-50.3 fps, **342-353 out of order** | **55.8-61.2 fps, 0-1 out of order** (62-65 in other sessions; 2.5.3-mickys.4: 67.0-69.6 against 2.5.3-mickys.3's 63.7-64.8 the same morning); 10-bit 63-65 (measured with 2.5.3-mickys.2) | 2.5.3-mickys.3 |
| Parsec, 4K HiDPI 60 Hz, 8-bit | **2.8 fps** or none, software encoding (332 ms per frame); with the overlay's encoder but NullMoth's plugin: 30.6-31.2 fps, 70-98 out of order | **37.3-41.1 fps, 0 out of order**; 10-bit 37 (measured with 2.5.3-mickys.2) | 2.5.3-mickys.3 |
| Desktop without capture (window animation, 144 Hz full-screen app) | 79.2-79.5 transactions/s; 118-128 fps | level: 79.1-80.5; 117-131 fps | 2.5.2-mickys.1 |
| Local display: full-screen Safari animation (drawn on the CPU), 1080p 165 Hz / 4K HiDPI 60 Hz, screen updates/s | not measured (2.5.3-mickys.3: 67-68 / 48.5-50) | **127.8-129.3 / 60** (the refresh rate; WindowServer at 40+7 % of a core at 4K, 2.5.3-mickys.3 34+28 %) | 2.5.3-mickys.5 |
| Parsec with a full-screen Safari animation, 1080p 165 Hz / 4K HiDPI, fps sent | not measured (2.5.3-mickys.3: 29.2 / 15.1-16.1) | **36.7-37.2 / 16.9-17.7**, 0 out of order | 2.5.3-mickys.5 |
| Display modes (1080p 165 Hz dummy plug) | 119 modes, all 60 Hz (NullMoth 2.5.2) | 164 modes, up to 165 Hz | 2.4.3-mickys.5 |

The Parsec rows were measured in one sitting (2026-10-23, NullMoth 2.5.3, macOS 26.7.1, a full-screen Metal animation, the same client, 2 x 30 s per setup): NullMoth's driver alone, NullMoth's driver with only the overlay's encoder (`install.sh` without `--desktop`), and the full overlay (`--desktop`). The frame-order check runs in the overlay's encoder, so the stock row has fps only.

The GPU upload of CPU-drawn windows (a full-screen 4K Safari window: 21 -> 34 screen updates per second, 2.3.7-mickys.2)
started in this fork and has been part of NullMoth's driver since 2.5.1, so it no longer shows against stock.

### GTX 1650 (Turing, TU117)

| | NullMoth's driver | with the overlay | since |
|---|---|---|---|
| Hardware video encoding | none (NullMoth's encoders do not register on TU117) | H.264 (B pictures), HEVC (8 / 10-bit, P only); real time 1080p 4.1 ms, 4K 15.4 ms | 2.4.3-mickys.2 |
| H.264 decode, 1080p / 4K | 154 / 36 fps | **447 / 121 fps** | 2.4.3-mickys.2 |
| HEVC decode, 1080p / 4K | 574 / 192 fps | 609 / 183 fps (the card is the limit) | 2.4.3-mickys.2 |
| VP9 decode, 1080p / 4K | none | 580 / 180 fps | 2.4.3-mickys.2 |
| Parsec, 1080p | 50 fps (NullMoth 2.5.0) | 60-62 fps (NullMoth 2.5.0, plane seed + import cache) | 2.5.0 build (not published) |
| Display modes | 60 Hz | up to 240 Hz at 1080p (EDID override) | 2.4.3-mickys.5 |

The GTX 1650 was last measured on NullMoth 2.5.0; the releases after 2.5.2 were tested on the RTX 4090 only.

## Release by release

Each row: what the release changed for speed, and what it measured against the release before (or against NullMoth's
plugin where stated), on the local display (nothing capturing; and the codecs) and while capturing. "Features" rows changed
what works, not how fast.

| Release | Date | NullMoth | Card | Change | Local display / codecs | Capture (Parsec, screen recording) |
|---|---|---|---|---|---|---|
| 2.3.6-mickys.2 | 2026-10-18 | 2.3.6 | RTX 4090 | first overlay: hardware H.264 / HEVC encoding for Ada through VideoToolbox | features (NullMoth has no Ada encoder) | - |
| 2.3.6-mickys.3 | 2026-10-18 | 2.3.6 | RTX 4090 | HEVC with 3 reference pictures | features | - |
| 2.3.6-mickys.4 | 2026-10-18 | 2.3.6 | RTX 4090 | encoder for every app; GPU check by PCI id | encoder start per process 12-20 -> 1.5 ms | - |
| 2.3.6-mickys.5 / .6 | 2026-10-18 | 2.3.6 | RTX 4090 | HEVC Main 10 (Parsec's 10-bit mode) | 4K 10-bit encode 7.0-7.3 ms per frame | - |
| 2.3.6-mickys.7 | 2026-10-18 | 2.3.6 | RTX 4090 | H.264 High profile / CABAC by default | features | - |
| 2.3.6-mickys.8 / .9 | 2026-10-18/19 | 2.3.6 | RTX 4090 | encoder names; `nvenc-run` for command-line tools | features | - |
| 2.3.7-mickys.1-.3 | 2026-10-19 | 2.3.7 | RTX 4090 | `--desktop`: GPU upload of CPU-drawn windows | full-screen 4K Safari window 21 -> 34 screen updates/s (vs NullMoth's plugin) | - |
| 2.4.3-mickys.1 | 2026-10-20 | 2.4.3 | RTX 4090 | encoders with B pictures; decoders H.264, HEVC, VP9, AV1, MPEG-1/2/4 | H.264 decode 4-5x NullMoth's; VP9 / AV1 decode new | - |
| 2.4.3-mickys.2 / .3 | 2026-10-21 | 2.4.3 | GTX 1650 | GTX 1650 support; decode time stamps | encoding and VP9 decoding on TU117 (NullMoth: none) | - |
| 2.4.3-mickys.4 | 2026-10-21 | 2.4.3 | GTX 1650 | real-time H.264 with NVIDIA's own encoder controls | +3.2 / +3.7 VMAF at 1080p, 4K 13 % faster | - |
| 2.4.3-mickys.5 | 2026-10-21 | 2.4.3 | GTX 1650 | `--resolution`: smaller rasters as real modes, EDID overrides | 1080p at 120-240 Hz instead of 60 | - |
| 2.4.3-mickys.6 | 2026-10-21 | 2.4.3 | GTX 1650 | capture: NV12 plane seed, import cache, texture pool | desktop benchmark 1080p 66.0 -> 71.8, 4K 15.3 -> 19.9; WindowServer CPU 73 -> 60 % | Parsec 1080p 144 Hz 46-47 -> **71-72 fps**, no tearing |
| 2.4.3-mickys.7 | 2026-10-21 | 2.4.3 | GTX 1650 | WindowServer's completion marks on their own connection | - | ~117 ms capture freezes gone; Parsec 1080p 165 Hz 52-54 -> **80-81 fps** |
| 2.4.3-mickys.8 | 2026-10-21 | 2.4.3 | GTX 1650 | captured frames current and in order | - | 0 one-frame swaps (was 1-6 per 30 s); Parsec 50-58 fps of current frames (`.7`'s 80 were mostly one frame old) |
| 2.5.2-mickys.1 | 2026-10-22 | 2.5.2 | RTX 4090 | rebuilt on NullMoth 2.5.2; only measured changes on by default; nvenc 0.9.4 | 144 Hz: level with NullMoth's (the GTX 1650's half-rate problem gone); real-time H.264 +2.7-3.1 VMAF | screen recording + Screen Sharing 1080p 165 Hz: NullMoth's plugin 81-93 fps with 142-183 frames out of order -> 90-103 fps, **0 out of order**; without Screen Sharing NullMoth's 95-107 -> 137-159 fps (before the frame-order fix) |
| 2.5.3-mickys.2 | 2026-10-23 | 2.5.3 | RTX 4090 | no upload of capture frames that were only read | - | Parsec 4K 10-bit 30 -> **37 fps**, 1080p 10-bit 55 -> 63-65, 1080p 8-bit 54 -> 56-57; late frames nearly gone |
| 2.5.3-mickys.3 | 2026-10-23 | 2.5.3 | RTX 4090 | captured frames copied out by the GPU | - | Parsec 1080p 8-bit 58 -> **62-65 fps**, 4K 8-bit 31 -> **38-41**; screen recording + Screen Sharing 98-108 -> **129-154 fps**; frames in order |
| 2.5.3-mickys.4 | 2026-10-23 | 2.5.3 | RTX 4090 | descriptor masks fixed (WindowServer wrote ~180 descriptors per draw, 2.2 million a second), VRAM import table 32 -> 128 entries with its per-surface cap following the card's VRAM, CPU-drawn window uploads ordered; page cache + async upload as an option (`NVMTL_SURFIN_PAGE_CACHE=1`: ~1 s stalls now and then) | full-screen Safari animation 1080p 165 Hz 67-68 -> **72.8-74.0 screen updates/s**, 4K HiDPI 48.5-50 -> **57.7-58.0**; with the option 131-135 / 60; full-screen Metal app level (153-162 / 157-165 fps) | Parsec with Safari animating 1080p 29.2 -> **33.5-33.7 fps** (with the option up to ~47 in a diagnostic build), 4K level (15.1-16.1 / 15.4-15.8); with the Metal app 63.7-64.8 -> **67.0-69.6**; frames in order |
| 2.5.3-mickys.5 | 2026-10-23 | 2.5.3 | RTX 4090 | CPU-drawn window uploads from kept page imports, not waited for (the ~1 s stall that kept them off in .4 fixed: late-collected deferred uploads waited out a 1 s completion check and leaked their pools) | full-screen Safari animation 1080p 165 Hz 72.8-74.0 -> **127.8-129.3 screen updates/s**, 4K HiDPI 57.7-58.0 -> **60** with system CPU 28 -> 7 %; full-screen Metal app level (157-165 / 157-164 fps) | Parsec with Safari animating 1080p 33.5-33.7 -> **36.7-37.2 fps**, 4K 15.4-15.8 -> **16.9-17.7**; with the Metal app 67.0-69.6 / 64.1-67.9 (level); no stall in 10 Metal-app runs; frames in order |
| 2.5.3-mickys.6 | 2026-10-23 | 2.5.3 | RTX 4090 | mickys/nvenc 0.9.5: the decoders hand ffmpeg-style clients their own buffers instead of VideoToolbox copying every frame (PR #1, with a guard for clients asking for another format or size); AV1 frames with missing references dropped; AV1 / VP9 decoding on RTX 30; `--cli-wrappers` (opt-in) | ffmpeg decoding 4K AV1 40 -> **125 fps**, HEVC 35 -> **115**, VP9 39 -> **158**; 1080p H.264 level (88-90 / 85-88); plugin unchanged | - (plugin unchanged) |

Not in a release but part of the measured setup: zero-copy scan-out (an OpenCore setting of this test machine, not of the
overlay) took a full-screen app from 140-150 to 157-164 fps at 165 Hz and Parsec from 55-60 to 65-66 fps (GTX 1650, NullMoth 2.4.3).

## Trade-offs that stay switchable

- Frame order: keeping captured frames in order costs speed while capturing. `NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=0` gives
  Parsec ~70 instead of 62-65 fps at 1080p 8-bit (RTX 4090), with about two one-frame jumps back per second.
- Every change above has its own line in `nvrm610.conf` (README, "Every config line").

## Adding a release

Add a row to "Release by release" with the card and NullMoth version it was measured on, and update "Overall" when a
number there changes. Measure against the previous release (or NullMoth's plugin) in the same boot or client session, at
least twice, and say "not measured" rather than carrying a number over from another setup.
