# Plugin changes in mickys/nvidia-macos-driver that may be worth taking upstream

Nine changes to `plugin/` (NVMTLDriver) carried in the fork's `dev` branch on top of v2.5.3, plus one framebuffer feature.
Each is behind its own switch, so it can be compared with the stock behaviour in the same build. Each group is also on its
own branch based on v2.5.3 (see **Branches**), ready to merge or to open as a pull request.

## Background

- All plugin changes are behind a switch (a line in `nvrm610.conf` or an environment variable). The fork turns them on by
  default; the default upstream is your choice.
- **Surface-in / upload:** CPU-drawn IOSurfaces (WebKit, CoreGraphics windows) are copied into VRAM before the GPU uses them,
  on the GPU from the surface's own pages since 2.5.1.
- **Capture:** with Parsec, OBS or a screen recording running, WindowServer composites every frame a second time into a
  two-plane NV12 IOSurface that a reader locks and reads on the CPU. The plugin keeps a private Vulkan image per surface and
  moves data between it and the surface's pages (surface-in, page-off / copy-out), using IOSurface seeds to decide when.
- **Test machine:** macOS 26.7.1 in a KVM virtual machine with the GPU passed through (AMD Ryzen 9 3950X host), RTX 4090
  (and a GTX 1650 for older measurements), a 1080p 165 Hz HDMI dummy plug, NullMoth 2.5.3 unless stated. Workloads: a
  full-screen Safari page animating a gradient and a frame-counter strip (drawn on the CPU), a full-screen Metal animation,
  Parsec with a client connected (frames sent per second; frame order checked by reading the counter back in the encoder),
  macOS screen recording with Screen Sharing connected (every recorded frame's counter decoded). Every comparison was run in
  the same boot or client session, at least twice. Absolute numbers on other machines will differ; the differences are the
  point.

## Branches

Branches of [github.com/mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver), based on v2.5.3 (75e2e28) or on
the branch an item needs. Each holds only its items: switches read with `getenv` and on by default, no diagnostic files or
statistics, nothing from the fork's other experiments. Each builds on its own (release build, macOS 15.0 minimum), and all
leaves merge together without conflicts.

```
v2.5.3
├── upstream/fixes            items 1-3
│   └── upstream/page-cache   item 9 (needs 2 and 3)
├── upstream/capture-order    items 4-5
├── upstream/plane-seed       item 6
│   ├── upstream/reader-skip  item 7 (needs 6)
│   └── upstream/import-cache item 8 (needs 6)
└── upstream/nvrmfb-modes     NVRMFB (outside the plugin)
```

| Branch | Based on | Items | Commits |
|---|---|---|---|
| [`upstream/fixes`](https://github.com/mickys/nvidia-macos-driver/compare/75e2e28...upstream/fixes) | v2.5.3 | 1, 2, 3 | 18c9cdd, 3901503, 21ab072 |
| [`upstream/page-cache`](https://github.com/mickys/nvidia-macos-driver/compare/upstream/fixes...upstream/page-cache) | `upstream/fixes` | 9 | aed2036, 97f1db1 |
| [`upstream/capture-order`](https://github.com/mickys/nvidia-macos-driver/compare/75e2e28...upstream/capture-order) | v2.5.3 | 4, 5 | c77ee56, bfaaf26 |
| [`upstream/plane-seed`](https://github.com/mickys/nvidia-macos-driver/compare/75e2e28...upstream/plane-seed) | v2.5.3 | 6 | 0c98c3e |
| [`upstream/reader-skip`](https://github.com/mickys/nvidia-macos-driver/compare/upstream/plane-seed...upstream/reader-skip) | `upstream/plane-seed` | 7 | 1e7d414 |
| [`upstream/import-cache`](https://github.com/mickys/nvidia-macos-driver/compare/upstream/plane-seed...upstream/import-cache) | `upstream/plane-seed` | 8 | 6d20e60 |
| [`upstream/nvrmfb-modes`](https://github.com/mickys/nvidia-macos-driver/compare/75e2e28...upstream/nvrmfb-modes) | v2.5.3 | NVRMFB | 9c023cd |
| [`upstream/all`](https://github.com/mickys/nvidia-macos-driver/compare/75e2e28...upstream/all) | v2.5.3 | every leaf merged (a test integration, not for merging) | f789975 |

`upstream/all` (as of 8a2e674, before the timer fix below was added to item 9), installed on the test machine (RTX 4090, macOS 26.7.1), passed the fork's release checks: NV12 round trips at
1080p and 4K (0 mismatches), CPU-drawn surface uploads at four sizes on the GPU and CPU paths (8 of 8 runs, 0 wrong), and a
15 s screen recording with macOS Screen Sharing connected (923 frames, app 122-138 fps, 0 frames out of order, 0 swap timeouts),
the same as the fork's released plugin.

Differences from the fork's `dev` code: the deferred upload of item 9 keeps only the parts of PR #96's design it needs (the
pending list and the image's upload guard, no staging-buffer path); item 8 uses the existing `nvmtl_vk_vram_bytes()`; the
multi-plane VRAM sharing hooks (an experiment not offered here) are left out of items 5 and 7.

## Performance at a glance

"Before" is the same build with only that change switched off, unless the row says otherwise.

| # | Change | Workload | Before | After |
|---|---|---|---|---|
| 1 | Descriptor masks | Safari animation, local display 1080p 165 Hz (screen updates/s) | 67.6-69.2 | 73.7-74.0 |
| 1 | | Parsec 1080p, Safari animation (fps) | 27.9 | 29.5-29.7 |
| 1 | | WindowServer descriptor writes per second | 2.2 million | 35,000 |
| 2 | Witness lap check | (correctness; prevents 1 s stalls and the loss of command-pool reuse) | - | - |
| 3 | Ordered upload | upload time per surface-in (ms) | 3.98 | 3.92 (no cost) |
| 4 | Captured frames in order | screen recording + Screen Sharing 1080p: frames out of order per 20 s | 142-183 | 0 |
| 4 | | Parsec 1080p: frames out of order per 30 s | 342-353 | 0-1 |
| 4 | | Parsec 1080p, Metal animation (fps; the cost of ordering) | ~70 | 62-65 |
| 5 | GPU copy-out | Parsec 1080p 8-bit (fps) | 58 | 62-65 |
| 5 | | Parsec 4K 8-bit (fps) | 31 | 38-41 |
| 5 | | screen recording + Screen Sharing 1080p (app fps) | 98-108 | 129-154 |
| 6 | Plane seed | Parsec 1080p 144 Hz, GTX 1650, NullMoth 2.4.3, together with item 8 and a texture pool (fps) | 46-47 | 71-72 |
| 7 | Reader skip | Parsec 4K 10-bit (fps) | 30 | 37 |
| 7 | | Parsec 1080p 10-bit / 8-bit (fps) | 55 / 54 | 63-65 / 56-57 |
| 8 | VRAM import cache | screen recording 1080p 165 Hz (app fps) | 103-123 | 138-157 |
| 9 | Page cache + async upload | Safari animation, local display 1080p 165 Hz / 4K HiDPI 60 Hz (screen updates/s) | 73 / 58 | 128 / 60 |
| 9 | | WindowServer system CPU at 4K | 28 % | 7 % |
| 9 | | Parsec 1080p / 4K, Safari animation (fps) | 34 / 15.6 | 37 / 17.3 |

---

## Group A: fixes (items 1-3)

### 1. Descriptor masks (`NVMTL_DESC_MASK`)

- **Problem:** `nvmtl_spirv_bmask()` (`plugin/nvmtl_vk.c`, ~line 2041 in v2.5.3) builds the mask of bindings a pipeline's
  shaders use, so a draw writes only those descriptors. It leaves the heap (set 2) out but not the framebuffer-fetch set
  (set 3, bindings 192+n): any pipeline with framebuffer fetch voids the mask (`gmask_ok` / `bmask_ok` = 0) and every draw
  writes all ~180 descriptors. CoreAnimation's pipelines use framebuffer fetch, so WindowServer made ~12k descriptor sets per
  second with 2.2 million descriptor writes per second.
- **Change:** set 3 is left out of the mask like set 2 (a `skip_fetch` argument to the mask parser; `gmask2` / `bmask2` in
  `nvmtl_vk.h`). About 6 writes per set instead of ~180, and half as many new sets because more are reused.
- **Why should merge:** a bug in existing code with a large, measurable effect on every WindowServer draw; a few lines with
  no new mechanism.
- **Performance:** Safari animation, local display 1080p 165 Hz 67.6-69.2 -> 73.7-74.0 screen updates/s; Parsec 1080p
  27.9 -> 29.5-29.7 fps; descriptor writes 2.2 million/s -> 35,000/s. No differences in screenshots or in frame-by-frame checks of a screen recording.
- **Required by:** none.
- **Commits:** branch `upstream/fixes` (18c9cdd; on dev d712925, e3ce433).

### 2. Witness lap check

- **Problem:** `nvmtl_keep_verdict()` decides from a ring of 4096 completion witness slots (`NVMTL_WIT_SLOTS`) whether a command
  buffer has completed. If the verdict is asked after the slot has been reused, the slot holds a later sequence number
  (N + 4096k), the check fails, and the plugin waits `NVMTL_WIT_WAIT_MS` (1000 ms), then counts the command pool as lost. After
  `NVMTL_WIT_LOST_MAX` (8) losses, pool reuse is turned off for the process; WindowServer then created RM mappings for every
  command buffer and ran at ~12 fps.
- **Change:** a slot that holds a later lap of the same slot means the earlier submission completed.
- **Why should merge:** removes a 1 s stall and a permanent loss of pool reuse for any caller that asks late. Stock does not
  appear to ask 4096 submissions late today, so it is latent there; any deferred completion check (item 9 is one) hits it.
- **Performance:** no change on its own. With item 9 it was the cause of occasional ~1 s WindowServer stalls (single uploads
  of ~1000 ms in 6 of 14 Parsec runs of a full-screen Metal app; 0 of 12 with item 9 off) and of WindowServer dropping to ~12 fps after many sessions.
- **Required by:** item 9.
- **Commits:** branch `upstream/fixes` (3901503; on dev part of 5536b1e).

### 3. Ordered upload (`NVMTL_SURFIN_ORDERED`)

- **Problem:** in `nvmtl_vk_image_write_host()` (`plugin/nvmtl_vk.c`, ~line 6259 in v2.5.3) the layout transition before the
  surface-in copy uses `srcStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT` with no source access, so the copy is not ordered after
  earlier GPU reads of the image (a write-after-read hazard; a torn frame is possible).
- **Change:** `srcStage = ALL_COMMANDS`, `srcAccess = MEMORY_READ | SHADER_READ`.
- **Why should merge:** makes the surface-in copy correct under Vulkan's synchronisation rules at no measurable cost.
- **Performance:** no cost (3.92 vs 3.98 ms per upload). The tear was not provoked in testing; the fix follows from the
  barrier semantics.
- **Required by:** item 9 (its deferred uploads move further from the reads they must follow).
- **Commits:** branch `upstream/fixes` (21ab072; on dev part of 6d1812e, e3ce433).

## Group B: capture order (items 4-5)

### 4. Captured frames in order (`NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=3`)

- **Problem:** a command buffer that writes an IOSurface through its private image reports "scheduled" before the image has
  been copied out to the surface's pages, so a capture reader can read the previous frame and frames arrive out of order.
  `NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=1` (`plugin/NVMTLEventSync.m`, ~line 322) fixes that for every surface write of every
  app, which costs too much to be on by default.
- **Change:** mode `=3` waits for the copy-out only for two-plane (NV12) private-image surfaces, which are the capture
  surfaces; on by default in the fork. `=2` covers every private-image surface (same capture result, same cost); `=0` is
  off.
- **Why should merge:** captured video (Parsec, OBS, screen recordings) comes out in order with no cost to apps that do not
  capture; it builds on the existing switch.
- **Performance:** screen recording with Screen Sharing connected, 1080p 165 Hz: 142-183 frames out of order per 20 s -> 0;
  Parsec 342-353 out of order per 30 s -> 0-1. While capturing it costs throughput: Parsec ~70 -> 62-65 fps (item 5 wins
  most of it back).
- **Required by:** item 5 (for its frames-in-order results).
- **Commits:** branch `upstream/capture-order` (c77ee56; on dev aea3bd0, cf64a20).

### 5. GPU copy-out (`NVMTL_GPU_COPYOUT`)

- **Problem:** the NV12 capture surface's private image is paged off to the surface's pages by the CPU when the reader locks
  it, on the reader's critical path.
- **Change:** at the end of the command buffer that writes a two-plane private-image surface, the GPU copies both planes into
  the surface's (host-imported) pages; the CPU page-off is skipped when that copy is current.
- **Why should merge:** moves the largest per-frame capture cost off the CPU and out of the reader's lock.
- **Performance:** Parsec 1080p 8-bit 58 -> 62-65 fps, 4K 31 -> 38-41; screen recording with Screen Sharing 98-108 ->
  129-154 fps; frames in order with item 4.
- **Required by:** none.
- **Commits:** branch `upstream/capture-order` (bfaaf26; on dev 10b56c2, 15e02de). Uses the one-private-image-per-IOSurface path.

## Group C: plane seed (item 6)

### 6. Plane seed (`NVMTL_PLANE_SEED`)

- **Problem:** whether a plane's private image is current is decided from the IOSurface seed. A write by the plugin to one
  plane of a two-plane surface bumps the surface's seed, so the other plane's private image is treated as stale and uploaded
  again: extra work, and stale content in some orders of writes and reads.
- **Change:** the seed bumps caused by the plugin's own writes are recorded per plane, so a plane's image stays current across
  writes to the other plane.
- **Why should merge:** removes redundant uploads of capture planes and a source of stale planes; the fork's longest-running
  change (on by default since its 2.4.3 builds).
- **Performance:** measured together with item 8 and a texture pool on a GTX 1650 with NullMoth 2.4.3: Parsec 1080p 144 Hz
  46-47 -> 71-72 fps, no tearing. Not measured alone.
- **Required by:** items 7 and 8.
- **Commits:** branch `upstream/plane-seed` (0c98c3e; on dev 59d118f).

## Group D: the rest (items 7-9)

### 7. Reader skip (`NVMTL_SURFIN_READER_SKIP`)

- **Problem:** a capture reader's CPU lock bumps the surface seed by one without changing the content, so the surface is
  uploaded into its private image again before the next GPU use.
- **Change:** the surface-in is skipped when the seed moved by exactly one since the plugin's last write (after its own
  recorded bumps) and the plane's VRAM generation is unchanged; for shared-VRAM render targets drawn with Load, and for
  private-image planes.
- **Why should merge:** removes one full upload per captured frame.
- **Performance:** Parsec 4K 10-bit 30 -> 37 fps, 1080p 10-bit 55 -> 63-65, 1080p 8-bit 54 -> 56-57; late frames gone.
- **Required by:** none.
- **Commits:** branch `upstream/reader-skip` (1e7d414; on dev 34c65a7, e012b57, cc2c2b1). Needs item 6. The rule "exactly one bump means a read-only lock" is an inference
  about reader behaviour; it held in every test, but deserves your review.

### 8. VRAM import cache (`NVMTL_SURF_IMPORT_CACHE`, size cap by VRAM, 128 entries)

- **Problem:** every wrapper (texture or buffer) of an IOSurface imports the surface's VRAM family allocation on its own;
  imports are expensive and happen every frame during capture.
- **Change:** one import per IOSurface, shared by its wrappers and kept `NVMTL_SURF_IMPORT_CACHE_IDLE_MS` (2000 ms) after the
  last wrapper goes; a per-surface size cap of 64 MB with 8 GB of VRAM or more, else 16 MB
  (`NVMTL_SURF_IMPORT_CACHE_MAX_MB`); a table of 128 entries (with 32, the table filled up during capture and the menu-bar
  surfaces were imported again every frame).
- **Why should merge:** removes repeated imports of the same surfaces, the main remaining per-frame cost in screen recording.
- **Performance:** screen recording 1080p 165 Hz 103-123 -> 138-157 fps, 0 stalls. Without a cap, a GTX 1650 stalled at 4K
  HiDPI (up to 67 stalls per 15 s), hence the cap.
- **Required by:** none.
- **Needs:** item 6. Alone (GTX 1650, NullMoth 2.5.0) it made screen recording worse: 54-59 fps with 26 / 18 swap timeouts;
  with the plane seed 157-161 fps with 1 / 0.
- **Commits:** branch `upstream/import-cache` (6d20e60; on dev 443b1ce, b280be5, 7876e00, 284bb99, 18bf0cc). The cap and idle time
  were tuned on one machine.

### 9. Page cache + async upload (`NVMTL_SURFIN_PAGE_CACHE`, `NVMTL_SURFIN_ASYNC`)

- **Problem:** every surface-in of a CPU-drawn window wires and maps the surface's pages through the kernel (~8100 pages for a
  4K window), copies, and unmaps, while WindowServer waits for the copy to finish.
- **Change:** (a) the page import is kept between uploads (64 entries, at most 512 MB wired, released 2 s after the last
  upload); (b) the copy is not waited for: it is recorded ahead of the command buffer that uses the window, with the entry
  pinned until it lands; (c) deferred uploads whose fence has signalled are collected right away and by a 500 ms timer, which
  also frees idle entries.
- **Why should merge:** the largest gain for CPU-drawn windows (most of the desktop), and much less WindowServer CPU.
- **Performance:** Safari animation, local display 1080p 165 Hz 73 -> 128 screen updates/s, 4K HiDPI 58 -> 60 (the refresh
  rate) with WindowServer system CPU 28 % -> 7 %; Parsec 1080p 34 -> 37 fps, 4K 15.6 -> 17.3; a full-screen Metal app
  unchanged; with item 2, no stall and no lost witness in 6 Parsec soak rounds plus 10 Parsec runs of a Metal app.
- **Required by:** none.
- **Commits:** branch `upstream/page-cache` (aed2036 + 97f1db1, the timer's dispatch source kept alive: under ARC it was released at once and the 500 ms timer never fired; based on `upstream/fixes`; on dev 6d1812e, 05ac4bb, 284bb99, 5536b1e, e3ce433,
  49091b2). Needs items 2 and 3. The newest change (2026-10-23), so far tested on the RTX 4090 only.

---

## Outside the plugin

### NVRMFB: more display modes (`--resolution` in the fork's overlay)

- **Change:** the display's timings below the boot raster are offered as real modes, and EDID overrides
  (`/Library/NullMoth/edid-override/<vendor>-<product>.bin`, with an `nvfb-edid` tool to list displays and add timings) add
  refresh rates the display's EDID does not list. Smaller desktops are turned on by `/Library/NullMoth/nvfb-small` (a
  boot-arg `nvfbsmall=0` / `=1` overrides it).
- **Why should merge:** desktops below the boot size where scaled modes cannot be shown (for example the 4K-only boot raster
  of an HDMI dummy plug), and high refresh rates on displays with a short EDID.
- **Performance:** on a 1080p 165 Hz dummy plug, 119 modes, all at 60 Hz -> 164 modes up to 165 Hz (NullMoth 2.5.2's scaled
  and HiDPI modes included); every distinct mode was switched to and checked. GTX 1650: 1080p up to 240 Hz with an override.
- **Required by:** none.
- **Commits:** branch `upstream/nvrmfb-modes` (9c023cd; first written as fork commits 4f5345e, 798b93f, dacec61), built against the
  615.78.08 headers with `build/fb_build.sh`, which reproduces NullMoth's own 2.5.2 NVRMFB byte for byte.
