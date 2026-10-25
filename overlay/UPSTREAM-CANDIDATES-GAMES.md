# Driver fixes that Steam games needed, as branches on v2.5.4

Seventy Intel-Mac Steam games were tested on macOS 26.7.1 with an RTX 4090 on NullMoth's driver (2.5.3, with this fork's
plugin and translator). Results, with ten screenshots and fps/CPU/RAM/VRAM per game:
[mickys.github.io/nvidia-macos-driver](https://mickys.github.io/nvidia-macos-driver/). Its **Fix branch** column shows
which of the branches below a game needs. Final count: 66 work, 3 run (one needs a gamepad, one is online-only, and Dota 2's
world turns a flat colour after a minute; that one is open), 1 fails (BioShock 2 Remastered: the game's old Steamworks
library, not the driver).

Thirteen of the 70 needed a driver change. This report lists those changes as **one branch per fix, each based on
NullMoth's v2.5.4** (4677905), so each one can be reviewed, merged or skipped on its own. Every branch holds only its fix (one
commit; `games/pr343` holds PR #343's two commits; `games/fail-details` holds the diagnostics commits), has no diagnostics
of ours in it, and builds on its own. The plugin is a release build with macOS 15.0 as the minimum. The translator crate's
tests were run on every translator branch. All the branches together merge cleanly into `games/all`, except for one spot
covered in **Merging**.

The other report, [UPSTREAM-CANDIDATES.md](UPSTREAM-CANDIDATES.md), covers the desktop and capture performance changes
(`upstream/*` branches on v2.5.3). This one covers only what games need.

## Branches

Base for every branch: v2.5.4 = [4677905](https://github.com/mickys/nvidia-macos-driver/commit/4677905).

| # | Branch | Part | Fixes | Games that need it | Commit |
|---|---|---|---|---|---|
| 1 | [`games/argb8-pixel-format`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/argb8-pixel-format) | plugin | Apple GL's private ARGB8 pixel format (84) answered nil | Homeworld: Deserts of Kharak, Master of Orion, Endless Legend | bc0d175 |
| 2 | [`games/struct-member-arrays`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/struct-member-arrays) | plugin | reflection dropped the length of array members of plain structs | Hades, Graveyard Keeper | 1208932 |
| 3 | [`games/xlate-local-field-phi`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/xlate-local-field-phi) | translator | a phi of two loads of a local pointer field became a zero pointer | Hades | b17331b |
| 4 | [`games/xlate-rrm-identity`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/xlate-rrm-identity) | translator | rasterization-rate-map calls refused the whole function | Darkest Dungeon II, Imagine Earth (one variant) | ce68963 |
| 5 | [`games/xlate-gather-compare`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/xlate-gather-compare) | translator | `air.gather_compare_depth_*` not lowered | Civilization VI | af426fa |
| 6 | [`games/pr343`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/pr343) | plugin + translator | PR #343 (Del4y) as is, on v2.5.4 | Stellaris | 3c998bf, 796dc2c |
| 7 | [`games/xlate-cube-as-array`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/xlate-cube-as-array) | translator | Apple GL's cube-as-2D-array sample went down the array path | Stellaris (with 6 and 8) | 2a5e7fd |
| 8 | [`games/xlate-gld-splice`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/xlate-gld-splice) | translator | Apple GL's `gld.*` helpers not spliced | Stellaris (with 6 and 7) | 2314db3 |
| 9 | [`games/xlate-sampler-param`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/xlate-sampler-param) | translator | sampler2D helper parameters chosen through a compare chain | Dome Keeper | 53d2a47 |
| 10 | [`games/depth16-texel-size`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/depth16-texel-size) | plugin | Depth16/Stencil8 recorded as 4 bytes per texel | Dome Keeper | 40db52b |
| 11 | [`games/bc-small-mip-copy`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/bc-small-mip-copy) | plugin | copies of a BC texture's 1x1/2x2 mips refused | Cult of the Lamb | 7ba5002 |
| 12 | [`games/trace-id-lock`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/trace-id-lock) | plugin | deadlock with the Metal HUD on (`@synchronized` on the app's command buffer) | Soulstone Survivors, Cult of the Lamb | 29db43e |
| 13 | [`games/present-queue`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/present-queue) | plugin | deadlock with the Metal HUD on (present inline on the execution queue) | No Man's Sky | 0c394f0 |
| 14 | [`games/encoder-commandbuffer`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/encoder-commandbuffer) | plugin | encoders answered `-commandBuffer` (SPI) with nil | Hades (22,000 stub calls in two minutes) | dab4d7b |
| 15 | [`games/depth-texture-reflection`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/depth-texture-reflection) | plugin | texture arguments always reported as float, never depth | Apple GL shadow samplers (test program; no game in the list needs it alone) | dea3f37 |
| 16 | [`games/fail-details`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/fail-details) | plugin | diagnostics: refused translations dumped, failed blits described, in release builds | (how 9-11 were found) | 2267364, f850c28, 71883d5, 11c52d9 |
| | [`games/all`](https://github.com/mickys/nvidia-macos-driver/compare/4677905...games/all) | | every branch above merged: for testing, not for merging | | fc64dae |

Dependencies: Stellaris needs 6, 7 and 8 together. 7 and 8 build and pass their tests without 6, but the refusals they
fix only show up after PR #343's retry. Everything else stands alone.

## Merging

`games/present-queue`, `games/fail-details` and `games/pr343` each add one line to the list of `NVMTL_*` variables that
release builds keep (`nvmtl_conf_knobs`, `NVMTLObjects.m`). Merging two of them conflicts on those lines. Keep all of the
lines (see `games/all`). Nothing else overlaps.

## The fixes

Each section covers what the game showed, the cause, the change, and how it was checked. "Before" means the same build
without that commit.

### 1. Apple GL's private ARGB8 pixel format (`games/argb8-pixel-format`)

- **Seen:** Unity 5 games on OpenGL 2.1 had UI textures missing. In Homeworld: Deserts of Kharak the checkboxes, sliders
  and panels were gone. In Master of Orion the menu backdrop and the system view were black. Endless Legend's menu panels
  were missing, so the game could not be navigated. Apple's GL logged `unit 0 GLD_TEXTURE_INDEX_2D is unloadable ... using
  zero texture`.
- **Cause:** AppleMetalOpenGLRenderer asks for `MTLPixelFormat` 84 (private, not in the SDK header) when a GL_RGBA8 texture
  is uploaded as GL_BGRA + GL_UNSIGNED_INT_8_8_8_8, which gives bytes A,R,G,B. Unity 5 on GL 2.1 uploads its ARGB32 textures
  that way. The device answered nil, Apple's GL marked the texture unloadable, and it sampled as 0.
- **Change:** format 84 is stored as `VK_FORMAT_R8G8B8A8_UNORM` and its views swizzle R<-G, G<-B, B<-A, A<-R
  (`nvmtl_a8_mapping`, also combined with `MTLTextureSwizzle` views). Clears store (A,R,G,B). As a colour attachment the
  channels are not reordered, because Vulkan attachment views take no swizzle. Apple's GL only uploads into it.
- **Checked:** a GL legacy-context test uploads and draws one texel per format. `rgba8argb` read `000000ff` before and
  `30557a0b` (the expected R,G,B,A) after, and every other format was unchanged. All three games render their UI.
  Homeworld's menu was rechecked on `games/all`.

### 2. Reflection of array members in plain structs (`games/struct-member-arrays`)

- **Seen:** Hades (Supergiant, The Forge renderer on Metal) loaded and presented at 165 fps with a black screen. Graveyard
  Keeper (Unity 2020.3, OpenGL 4.1) drew everything outdoors black.
- **Cause:** the AIR `struct_type_info` of a plain buffer struct gives offset, element size, element count, type and name
  for each member. The parser dropped the count, so `float4x4 u_modelView[2]` was reflected as one `float4x4` with
  `arrayType` nil. Engines that size their uniform updates from reflection then copy too little. Hades wrote 64 of the 128
  bytes, so every screen-space vertex (which reads `u_modelView[1]`) used a zero matrix. Apple's GL sized Unity's light
  arrays the same way, so the lights outdoors were zero.
- **Change:** a member with a count above 1 is reported as `MTLDataTypeArray` with an `MTLArrayType` (element type, array
  length, stride = element size), as Apple's reflection does. The buffer's data size covers every element.
- **Checked:** A/B on Graveyard Keeper: the same plugin without this commit is black outdoors, and with it the yard, path,
  road and cliffs render. Hades renders at 141-165 fps (with fix 3). Hades' menu was rechecked on `games/all`.

### 3. Phi of two loads of a local pointer field (`games/xlate-local-field-phi`)

- **Seen:** with fix 2 Hades rendered, but the main menu's labels were invisible (their selector highlight drew).
- **Cause:** the shader object (`struct { texture, sampler, constant T *uniforms }`) is built in the entry point and passed
  to `main`. A pointer loaded from it becomes a placeholder copy, which `recover_unique_local_pointer_field_loads` resolves
  after emission. DistanceFieldFancy.frag reloads the uniform pointer after a `discard` and merges both loads in a phi, and
  that phi became an unmodelled private zero pointer. `u_OutlineThickness`, `u_Scale`, `u_ShadowBlur` and
  `u_ResolutionScale` read 0, and the smoothstep divided by zero.
- **Change:** when every incoming value of a phi is an unresolved load of the same field, the phi is one more placeholder
  of that field (placed after the block's phis) and is recorded with the same root and indices. The recovery still rewrites
  only fields with exactly one store, so nothing else changes.

### 4. Rasterization-rate-map calls (`games/xlate-rrm-identity`)

- **Seen:** Darkest Dungeon II (Unity URP) logged `Metal: Failed to get shader entry point 'xlatMtlMain'` at startup, and
  the translator logged `air.map_physical_to_screen_coordinates ... requires rasterization-rate-map parameter data
  decoding`. Imagine Earth lost one function-constant variant to the same call.
- **Cause:** the shaders carry the call for an optional foveation path, and refusing it fails the whole function.
- **Change:** the driver reports `supportsRasterizationRateMapWithLayerCount:` NO and `newRasterizationRateMapWithDescriptor:`
  returns nil (checked on the RTX 4090), so no map can exist and nothing can fill a `rasterization_rate_map_data` buffer.
  Without a map, physical and screen coordinates are the same, so both calls return their coordinate (`OpCopyObject`).
  `METAL2VULKAN_NO_RRM_IDENTITY=1` restores the refusal. The unit test now expects the identity.
- **Checked:** Darkest Dungeon II from the title screen through the Crossroads, hero select, the road, first combat and the
  pause menu at 78-124 fps, with a clean Player.log.

### 5. `gather_compare` on depth textures (`games/xlate-gather-compare`)

- **Seen:** Civilization VI's model, fire, leader and terrain fragment shaders were all refused with `unrecognized AIR
  intrinsic family: air.gather_compare_depth_2d.f32`.
- **Change:** `air.gather_compare_depth_{2d,2d_array,cube}` are lowered to `OpImageDrefGather` (the Vulkan sampler carries
  the compare function). A constant non-zero offset becomes `ConstOffset`, a dynamic one is folded into the coordinate as
  the plain gather does, and arrayed forms append the layer. Metal and Vulkan share the gather footprint order, so no
  swizzle is needed. Unit and integration tests are included.
- **Checked:** Civilization VI runs at 90-161 fps with 0 refusals.

### 6-8. Stellaris (`games/pr343`, `games/xlate-cube-as-array`, `games/xlate-gld-splice`)

- **Seen:** Stellaris (Clausewitz, OpenGL 2.1) had 18 shader refusals. Planets, the galaxy and the system view were
  missing.
- `games/pr343` is PR #343 as is (Del4y's two commits, author kept), cherry-picked onto v2.5.4 without conflicts. It
  fixes most of the refusals. Its translator code is byte-identical to the PR's head, and its tests pass.
- `games/xlate-cube-as-array`: Apple's GL samples a non-seamless cube map through a 2D-array view and keeps the real cube
  sample on a branch chosen by a per-unit mask. In a helper that takes the sampler as an argument, both calls reach the same
  texture, which is then typed as a 2D array, so the cube call went down the array path and read its LOD flag as the layer
  (`air.sample_texture layer is not scalar int/float`, 6 refusals). The cube call now becomes the 2D-array sample of the
  face its direction hits (Metal face order, as in `gld.cube_vector_to_uv`).
- `games/xlate-gld-splice`: Apple's GL links `gld.cube_vector_to_uv` / `gld.compute_lod_texture2d_array_cubeAsArray` into
  the shader as external definitions. The LOD helper takes a pointer into the GL uniform block, which cannot cross a call,
  and the splice only inlined internal helpers (4 refusals). Definitions named `@gld.*` now count as internal.
- **Checked:** 0 refusals. Menus run at 80-155 fps and the galaxy map at 30-80 fps (vsync, CPU-bound).

### 9. Sampler2D helper parameters (`games/xlate-sampler-param`)

- **Seen:** Dome Keeper (Godot 4, OpenGL compatibility renderer) had six fragment shaders refused (`sampler operand is a
  pointer whose exact sampler state was not recovered`), so Apple's GL ran them on the CPU.
- **Cause:** Apple's GL passes a GLSL helper that takes a `sampler2D` every texture/sampler pair plus a pointer to the
  texture unit the caller stored, and picks the pair with a switch. `resource_phi_fold` only resolved this when the
  selector had one store and every phi edge left one switch header. Dome Keeper calls `make_outline(vec2, sampler2D, vec2)`
  twice with the same unit, and the 11-way switch is lowered to a chain of compares.
- **Change:** the taken edge is found by reachability from the entry block (a branch on a known condition follows only its
  taken target). A resource phi with one live incoming value is replaced by that value. A selector may have several stores
  when all of them store the same literal.

### 10. Depth16 / Stencil8 texel size (`games/depth16-texel-size`)

- **Seen:** Dome Keeper: `blit copyFromBuffer:toTexture: FAILED ... pf 250 ... row 8` for a 4x4 Depth16 texture.
- **Change:** depth images record their real bytes per texel (Depth16 2, Stencil8 1) instead of 4 for every depth format.

### 11. BC tiny-mip copies (`games/bc-small-mip-copy`)

- **Seen:** Cult of the Lamb had 8 `blit copyFromTexture: FAILED` per start, a black screen and fonts not loaded.
- **Cause:** Metal sizes a block-compressed copy in whole blocks, so the 1x1 and 2x2 mips of a BC1/BC3 texture are copied
  as 4x4, and `copy_image_sub` refused the region as outside the mip.
- **Change:** the extent is clamped to the mip's edge when it runs past it by less than a block, as Vulkan requires for
  compressed copies.

### 12. Trace-ID lock (`games/trace-id-lock`)

- **Seen:** with the Metal performance HUD on (`MetalForceHudEnabled`), Soulstone Survivors and Cult of the Lamb hung on a
  black screen at start. The main thread was in a semaphore wait and the handler thread in `objc_sync_enter`.
- **Cause:** the HUD asks for a command buffer's trace ID from its scheduled handler, and `nvmtl_global_trace_id` did
  `@synchronized` on the command buffer. An app holding that lock while it waits for the handler deadlocks.
- **Change:** a private lock.

### 13. Presents on their own queue (`games/present-queue`)

- **Seen:** with the Metal HUD on, No Man's Sky showed a white window at start.
- **Cause:** `-[CAMetalDrawable present]` takes the layer's lock, which `-[CAMetalLayer nextDrawable]` holds on the app's
  thread. The HUD creates its font texture inside `nextDrawable` and waits for that command buffer, which was queued
  behind the one presenting.
- **Change:** presents run in order on a serial queue of their own (`nvmtl.present`). `NVMTL_PRESENT_INLINE=1` (kept in
  release builds) restores inline presents.
- **Checked:** A/B against inline presents with a full-screen Metal animation, alone and under a screen recording, both
  with and without a Parsec client connected. Fps was the same both ways and frame order was clean both ways (0 frames
  shown after a newer one, 0 timeouts).

### 14. `-commandBuffer` on encoders (`games/encoder-commandbuffer`)

- **Seen:** Hades asks every render encoder for its command buffer each frame. The forwarding stub answered nil
  (`SPI-STUB -[NVMTLRenderCommandEncoder commandBuffer] ... NOT IMPLEMENTED`, 22,000 calls in two minutes).
- **Change:** render, compute and parallel encoders return their command buffer, and keep answering after `endEncoding`
  as Apple's do. Blit and acceleration-structure encoders keep a weak owner for it, and the parallel encoder's deferred
  sub-encoders answer it directly.
- On its own it did not change Hades' picture (fixes 2 and 3 did). It removes the stub calls and gives back what the game
  asks for.
- Note: we also tried answering `-encodeWaitForEvent:value:timeout:` (another stub, about 230 calls/s in Hades) like
  `-encodeWaitForEvent:value:`. That made every Apple GL game crash in `gldPresentFramebufferData`, so it is **not** in
  this branch.

### 15. Depth and component type of texture arguments (`games/depth-texture-reflection`)

- **Cause:** Apple's GL-on-Metal takes a texture unit's sampler type from the pipeline reflection (`MTLArgument
  isDepthTexture` / `textureDataType`). Texture arguments always answered NO / Float, so a `sampler2DShadow` unit counted
  as a float texture and Apple's GL never filled that unit's compare swizzle. Every shadow lookup returned 0.
- **Change:** `depth2d` / `depthcube` / ... arguments answer `isDepthTexture` YES, and `<uint>` / `<int>` / `<half>`
  textures answer UInt / Int / Half, as Metal does.
- **Checked:** a GL shadow-sampler test (lit 255 / shadowed 0 at four compare values) fails before and passes after. No
  game in the list was found to need it alone (it was found while chasing Graveyard Keeper, whose cause was fix 2).

### 16. Diagnostics in release builds (`games/fail-details`)

- `NVMTL_XLATE_FAIL_DUMP=<dir>` keeps a library entry the translator refuses (AIR text, stage, name, error), also in
  release builds (it writes only when a translation is refused).
- A failed texture-to-texture or buffer-to-texture blit names its formats, sizes, subresources and region in release
  builds.
- This is how fixes 9-11 were found from players' logs. It is optional.

## Tests

- **Plugin:** every branch and `games/all` built as a release build against v2.5.4 (Xcode clang, x86_64, macOS 15.0
  minimum), with the same warning count on every branch.
- **Translator:** the crate's tests (release, Rust 1.98.1, Linux) for v2.5.4 and every translator branch. Some validation
  fixtures that the tests include are not in the repository; empty stubs stand in for them, and their tests fail on
  v2.5.4 already (48 failures there, all pre-existing). Results per branch are under **Translator test results** below.
- **On the machine:** `games/all` (plugin) with the same translator code was installed on the test machine. Homeworld's
  menu (fix 1) and Hades' main menu (fixes 2 and 3) rendered with 0 refusals, and the desktop stayed fine. Each fix was
  also tested on its own game when it was made (the per-fix **Checked** lines).

### Translator test results

Tests passed / failed (translator crate, wrapper crate). The same 48 + 2 tests fail on v2.5.4 itself in this environment
(Linux, stubbed fixtures). No branch fails any test that passes on v2.5.4, and the new tests each branch adds pass.

| Ref | translator | wrapper |
|---|---|---|
| `v2.5.4` | 2308 / 48 | 32 / 2 |
| `games/pr343` | 2312 / 48 | 42 / 2 |
| `games/xlate-cube-as-array` | 2308 / 48 | 32 / 2 |
| `games/xlate-gld-splice` | 2308 / 48 | 32 / 2 |
| `games/xlate-sampler-param` | 2313 / 48 | 32 / 2 |
| `games/xlate-gather-compare` | 2314 / 48 | 32 / 2 |
| `games/xlate-rrm-identity` | 2308 / 48 (one existing test now expects the identity) | 32 / 2 |
| `games/xlate-local-field-phi` | 2308 / 48 | 32 / 2 |
| `games/all` | 2323 / 48 | 42 / 2 |

## Not driver problems (for players' reports)

- **Old Steamworks SDK** (i386 + x86_64 `libsteam_api.dylib`): the game quits at launch with `EXC_GUARD` /
  `GUARD_TYPE_MACH_PORT INVALID_RIGHT` in `CSimpleMachClient::~CSimpleMachClient` during `SteamAPI_Init`, because macOS
  26 guards the port the old SDK releases. A newer `libsteam_api.dylib` that exports what the game imports fixes it.
  Affected: Loop Hero, Tails of Iron, Griftlands, Starbound, Craft The World, Don't Starve, Graveyard Keeper. BioShock 2
  Remastered (Feral) cannot be fixed this way, because its loader rejects any other library.
- **No audio output device:** games that open OpenAL at start (Nienix, MonoGame) abort. A virtual machine needs an
  audio device.
- **Press-and-hold UIs:** No Man's Sky and Darkest Dungeon II confirm by holding a button. No Man's Sky's update-notes
  screen wants the right button held.
