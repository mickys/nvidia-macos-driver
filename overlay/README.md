# mickys overlay for NullMoth's NVIDIA driver

An **unofficial** test build of the Metal plugin from [mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver)
(branch `dev`), installed on top of [NullMoth's driver](https://github.com/nullmoth/nvidia-macos-driver). It is not made,
reviewed or supported by NullMoth. Report problems with it at
[mickys/nvidia-macos-driver issues](https://github.com/mickys/nvidia-macos-driver/issues), not upstream.

It replaces one file, the Metal plugin binary (`NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver`), and adds
`libnvencvt.dylib` next to it. The kernel extensions, firmware and everything else stay NullMoth's.

## What it changes

**Faster desktop with CPU-drawn windows.** When WindowServer composites a window that an app drew with the CPU
(every WebKit view, including Safari, and CoreGraphics apps), the plugin copied the window's pages into video memory
with the CPU, and the pages were faulted in again for every frame. The overlay lets the GPU copy them, and
WindowServer keeps the surfaces it uploads mapped. Measured on an RTX 4090 (macOS 26.7.1, in a VM) with a full-screen
CSS animation in Safari, for a 3158x1816 window:

| | per frame | WindowServer CPU (user) | screen updates/s |
|---|---|---|---|
| NullMoth 2.3.6 plugin | 15.0 ms | 128 % of a core | 24 |
| overlay | 5.3 ms | 30 % of a core | 30 |

Turn it off with `NVMTL_SURFIN_UPLOAD=cpu` (GPU copy) and `NVMTL_SURFIN_KEEP=0` (keep mapped) in
`/Library/GPUBundles/nvmtl/nvrm610.conf`, then log out and in.

**Hardware H.264 encoding on RTX 40 (Ada).** NullMoth's driver registers its NVENC encoders only on Blackwell (RTX 50),
so on older cards VideoToolbox encodes H.264 in software. The overlay adds an open-source H.264 encoder for Ada NVENC
([mickys/nvenc](https://github.com/mickys/nvenc), `libnvencvt.dylib`) for the processes you list. Parsec at 4K: about
4.8 ms per frame. It checks the GPU first and stays off on cards without Ada NVENC (RTX 20/30 and GTX 16 keep Apple's
encoder). HEVC is not supported yet.

## Requirements

- NullMoth's driver **2.3.6** installed and running. The installer refuses anything else: it checks NullMoth's version
  record, the version of the NVRM, NVAccel and NVRMFB kernel extensions on disk, and the version of the ones running
  (after a NullMoth update, restart before installing the overlay). The plugin and the kernel driver share interfaces,
  so an overlay is built for one NullMoth version (`COMPATIBLE-DRIVERS` in the package).
- An x86_64 Mac (Intel or AMD hackintosh) running macOS 15 or 26, as NullMoth's driver requires. Tested only on
  macOS 26.7.1 with an RTX 4090 so far.
- The encoder part needs an RTX 40 card. The desktop part works on every card the driver supports.

## Install

```bash
tar -xzf mickys-overlay-<version>.tar.gz && cd mickys-overlay-<version>
sudo ./install.sh                      # encoder for parsecd, obs, ffmpeg, sunshine
sudo ./install.sh --nvenc=1            # encoder for every app
sudo ./install.sh --nvenc=off          # desktop change only
```

Then log out and back in (or restart). The installer checks every file against `SHA256SUMS`, backs up the current
plugin and `nvrm610.conf` to `/Library/NullMoth/overlay-backup-<date>`, installs, re-signs the bundle and sets
`NVMTL_NVENCVT` in `nvrm610.conf`.

## Undo

```bash
sudo ./uninstall.sh
```

Then log out and back in. Updating NullMoth's driver also replaces the overlay (its installer writes the whole bundle).

## Check that it is active

- `codesign -dv /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver` and compare the hash with
  `SHA256SUMS`, or `shasum -a 256` the file.
- Encoder: a listed app shows "nvenc H.264 (NVIDIA pre-Blackwell)" / `org.nvenc.videoencoder.avc` as its encoder;
  Parsec's host log (`~/.parsec/log.txt`) says `encoder = Hardware`.

## Source

- Plugin: `plugin/` of [mickys/nvidia-macos-driver](https://github.com/mickys/nvidia-macos-driver) at the tag named in
  `VERSION` (NullMoth 2.3.6 plus the overlay's commits), built as a release (`NVMTL_RELEASE=1`, macOS 15.0 minimum).
- Encoder: [mickys/nvenc](https://github.com/mickys/nvenc) at the commit named in `VERSION`.
- The plugin source is under the PolyForm Noncommercial License 1.0.0 (`LICENSE`), like NullMoth's. The encoder is MIT
  (`LICENSE-nvenc`).
