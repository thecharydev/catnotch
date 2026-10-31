# 0013. Draw the macOS Glass style with native vibrancy, masked to the notch shapes

**Date**: 2026-10-31
**Status**: Accepted

## Summary

Glass on macOS stops capturing the screen. Instead, a real macOS blur view (vibrancy, the same frosted material the system uses for menus) sits behind the notch's web content and is cut to the exact shapes of the notch, its two ears, the tabs dock and the apps tray. You keep the full width strip window, so clicking, display handling, and the fullscreen tuck work as they do today. The blur is drawn by a small native piece (an addon, a compiled plugin Electron can load), and if it fails to load, Glass falls back to today's capture and its permission. Windows and the Transparent style do not change.

## Context

> ⚠️ Premise note: spec 0010 ruled out Electron's `vibrancy` window option because it fills the whole window rectangle. That is still true of the option, so this spec does not use it. It uses a native view that the option does not offer. This also amends two parts of 0010: Glass no longer needs Screen Recording on macOS when the native piece loads (0010 AC-1 and AC-9 now apply only on the fallback path).

Today Glass shows a blurred live capture of the screen (`Backdrop.tsx`): one `getUserMedia` stream at 15 frames per second, shared by every surface, which needs the Screen Recording permission. It also forces `glass:protect` (the window is excluded from capture) and a drift fix in `main.ts` (`pin()`), because starting a capture makes macOS shift the strip up by the cutout's height. Users who do not want to grant Screen Recording cannot use Glass at all.

The notch window is a transparent strip, the full width of the display and 500 points tall (`STRIP_HEIGHT`). The renderer draws everything inside it with springs: the shell (`NotchChassis`), two 8 point ears, the dock (up to three sides) and the apps tray (up to three sides). Main already receives every surface's rectangle through `notch:bounds` and polls the cursor against them, so the strip never needs to change size for clicks to work. `display.ts` creates one such window per target display and moves them on `display-metrics-changed`. `fullscreen.ts` hides a window with `hide()` and tells the renderer to tuck (the closed shell shrinks to a 6 point sliver).

A macOS blur view blurs whatever is behind its own window, with no capture and no permission. The only question is how to make it cover just the notch's shapes and not the whole strip.

Workspace: single repo, macOS only. Stack from the code: Electron 43, Next.js renderer with Nextron, a Swift helper built by `scripts/build-helper.sh`. There is no `AGENTS.md`, so conventions come from specs 0004 and 0010 and the existing code.

## Requirements

**User stories**:
- As a Mac user, I want Glass without granting Screen Recording, so I can use it without giving an app screen access.
- As a user, I want the blur to cover only the notch, the dock and the tray, so the strip around them stays clear and clicks pass through.
- As a user with several displays, I want each notch to look the same, so choosing All displays does not change the look.

**Acceptance criteria** (macOS, Glass style, native piece loaded):
- **AC-1**: Glass shows a live blur of what is behind the notch with no Screen Recording permission and no permission hint in Settings. No `getUserMedia` call and no `glass:protect` call is made.
- **AC-2**: The blur appears only inside the shapes of the shell, the two ears, the dock and the apps tray. The rest of the strip shows the desktop unblurred.
- **AC-3**: The blur edge matches the drawn shape, including the closed and open corner radii and the concave ears. There is no seam where the shell, ears, dock and tray meet.
- **AC-4**: While the notch springs open or closed, the blur edge follows the shell every frame. After the spring settles the blur edge is within 1 point of the drawn shape. During the spring it is at most one frame behind at 60 Hz.
- **AC-5**: Hit testing is unchanged: a click outside the notch parts goes to the app below, a click on a part reaches the notch.
- **AC-6**: Fullscreen hide removes the blur with the window, and showing the window again shows the blur again without a flash. A tuck to the 6 point sliver shrinks the blur to the sliver.
- **AC-7**: With All displays each notch has its own blur. Switching the selected display, plugging in or unplugging a display, keeps a working blur and leaves no stray view.
- **AC-8**: On a notched display, closed with nothing to show, the notch is pure black with no blur. Closed with wings, the wings show the blur and the cutout stays black. Without a cutout, the whole closed pill shows the blur.
- **AC-9**: If the native piece cannot load (not macOS, missing file, or load error), Glass uses today's capture path and its permission gate exactly as in spec 0010.
- **AC-10**: Windows, and the Transparent and Default styles on macOS, behave as before. Transparent starts no native view.
- **AC-11**: Nothing is sent or applied while no shape changes (closed and idle). The blur view is hidden when no glass surface is on screen.
- **AC-12**: A packaged, ad hoc signed build on both arm64 and x64 loads the native piece and shows the blur.

## Options considered

### Option 1: One native blur view in the strip window, masked to the surfaces

A small native addon (Objective-C, loaded through N-API, Node's stable plugin interface) adds one `NSVisualEffectView` inside the strip window's content view, underneath the web contents. A single `CAShapeLayer` mask holds the union of every surface's shape, and the view's frame is the bounding box of those shapes. The renderer already knows each surface's rectangle; it sends the list (rectangle, four corner radii, ear flag) to main each frame it changes, and main hands it to the addon.

**Pros**:
- The strip window, hit testing, display sync and fullscreen tuck are untouched.
- One view and one path means no seams between surfaces and one update per frame.
- No permission, no capture, no `pin()` drift.

**Cons**:
- New native code to build, sign and ship for two architectures.
- The blur sits in a layer under Chromium's compositor, so it is one IPC hop behind the DOM during a spring (budgeted in AC-4).
- It depends on how Electron 43 stacks the web view; this needs a spike (Build plan, task 1).

### Option 2: Blur panels owned by the Swift helper

The existing Swift helper opens its own transparent panels with `NSVisualEffectView`, one per surface, ordered just below the strip window. Main sends rectangles to it over the helper's line protocol.

**Pros**:
- No N-API addon; it reuses the helper build.
- A helper crash cannot take Electron down.

**Cons**:
- Ordering a window relative to another process's window is fragile, and fullscreen Spaces, `screen-saver` level and Mission Control behaviour would have to be matched in two processes.
- Visibility, display moves and fullscreen hide must be mirrored to a second set of windows.
- Per frame messages travel through a pipe and a second process before they draw.

### Option 3: Shrink the window to the notch and use Electron's `vibrancy`

Each surface becomes its own small window with the `vibrancy` option, resized from main to follow the spring.

**Pros**:
- No native code.

**Cons**:
- The blur is a rectangle (no ears, no changing radii), which does not match the shell.
- The window chases the spring through IPC and `setBounds`, and macOS resizes lag behind the DOM.
- Hit testing, display sync, the tuck and the `pin()` logic all change, and each surface needs its own window.

### Option 4: One vibrancy window for the largest open footprint

One window sized to the open notch with the dock and tray, drawn over.

**Pros**:
- Simple.

**Cons**:
- Blur shows in the gaps between the notch, dock and tray, so it does not cover only the notch. It also leaves the blur visible when the shell is smaller than the window.

## Decision

**Chosen option**: Option 1: One native blur view in the strip window, masked to the surfaces

On macOS, Glass is drawn by a native `NSVisualEffectView` cut to the union of the surfaces' shapes, and the existing capture path stays only as the fallback when the native piece cannot load.

**Implementation skills**: `liquid-glass` (`.agents/skills/liquid-glass/`) · `macos-design-guidelines` (`.agents/skills/macos-design-guidelines/`) for the material choice and dark appearance. Neither is required to build the addon.

## Rationale

The strip is wide and tall only so the renderer can animate freely, and the whole app already works around that: main tests the cursor against reported rectangles, `display.ts` places one window per display, `fullscreen.ts` hides it whole. Anything that changes the window's size or count (Options 3 and 4) forces all of that to change, and the spring then has to be chased by `setBounds`, which is the one thing macOS windows do badly. Option 2 keeps the window but moves the blur into another process, which makes window ordering and the fullscreen Space behaviour a second thing to keep right. Option 1 keeps the window and every behaviour that depends on it, and spends its cost in one place, a small native file.

The notch is the shape that matters most, so a mask is the right tool: it gives the concave ears and the animated radii for free, and a single mask over all surfaces cannot show a seam. The one honest weakness is the one frame lag between the DOM and the native mask. It is small, and it is the reason AC-4 is a measured gate in the spike and not an assumption.

Choosing a native addon over the helper (Option 2) follows the engineer's pick of masked views in the window. The runner up is Option 2 if the spike shows Electron 43 does not let a sibling view sit under the web contents.

## Feature design

**Where the pieces live**:
- `native/mac/vibrancy/vibrancy.mm`: the addon. Exports `attach(handle)`, `update(handle, shapes)`, `detach(handle)`.
- `main/mac/vibrancy.ts`: loads the addon (macOS only, in a try and catch), exposes `attachGlass(window)`, `updateGlass(window, shapes)`, and `glassAvailable`.
- `renderer/lib/glassShapes.ts`: the single place that gathers shapes and sends them (replaces each Backdrop's own follow loop when native is on).
- `renderer/components/notch/Backdrop.tsx`: keeps tint, rim and top highlight, and skips the video and the capture when native is on.

**Native view**:
- One `NSVisualEffectView`, `blendingMode` behind window, `state` active (so it blurs even when the panel is not key), material `hudWindow`, appearance `NSAppearanceNameVibrantDark`. Material is a constant in the addon; the DOM tint (`--notch-fill`) still sets how smoked it looks.
- Inserted below the web contents view in the strip's content view. The view does not take mouse events.
- Its frame is the bounding box of the shapes; its mask is the union path. With no shapes, the view is hidden.
- Coordinates arrive in CSS pixels from the window's top left, which equal AppKit points. The addon flips y using the content view's height.

**Shape message**:
```
Shape = { x, y, width, height, radii: [tl, tr, br, bl], ear?: 'left' | 'right' }
```
An `ear` shape is the 8 point box; the addon fills only its concave quarter, same as the DOM mask in `Ear`.

**IPC**:
| Channel | Direction | Payload | Notes |
|---|---|---|---|
| `notch:glass` | renderer to main (`send`) | `Shape[]` | only when the list changed since last send |
| `glass:native` | renderer to main (`invoke`) | none, returns boolean | true when the addon loaded |

`glass:source`, `glass:protect` and `glass:permission` stay, used only by the fallback.

**Value sourcing**:
| Action | Value produced or displayed | Source |
|---|---|---|
| Send shapes | rectangle of each surface | `getBoundingClientRect()` of the host element each `Backdrop` already holds |
| Send shapes | the four corner radii | `getComputedStyle(host)` border radius, read each frame (the radii are animated) |
| Send shapes | ear side | the `side` prop of `Ear`, passed to its `Backdrop` |
| Apply shapes | which native view | `BrowserWindow.fromWebContents(event.sender).getNativeWindowHandle()` |
| Decide native vs capture | whether to use the addon | `glass:native` result, read once at mount in `Backdrop` and in `SettingsPanel` |
| Blur look | material, appearance | constants in `vibrancy.mm` (not user settable) |
| Tint and rim | colour and alpha | existing CSS tokens `--notch-fill`, `--notch-rim` (unchanged, spec 0010 recipe) |
| Hide and show | last shapes for a window | main keeps the last list per window id and reapplies it on `show` |

**Hit testing (`main/main.ts`)**: unchanged. The strip stays full width and 500 points tall, `notch:bounds` and the 60 ms cursor poll stay. The native view takes no mouse events. The `pin()` drift fix stays for the fallback and costs nothing when no capture runs.

**Display sync (`display.ts`)**: unchanged. The native view belongs to the window, keyed by its handle, so a window moved to another display keeps its view, and its shape coordinates are window relative so they do not change. `syncNotchWindows` calls `detach` for windows it destroys (the addon also drops a view when its window closes). `Backdrop` no longer sizes a layer to `window.screen.width` on the native path.

**Fullscreen tuck (`fullscreen.ts`)**: unchanged. `hide()` hides the view with the window. `restoreWindow` is followed by a reapply of the last shapes in the `show` handler in `main.ts`. The tuck changes the shell's rectangle, and the mask follows it like any other size change. A tucked sliver on a display without a cutout is the shell's rectangle, so it is blurred as a sliver.

**Open and close animation**: `Backdrop` registers its host in `glassShapes.ts` while mounted. One `requestAnimationFrame` loop reads every registered host, builds the list, compares it with the last sent list, and sends only on change. The loop idles (no frame request) when no host is registered and when the window is hidden, and resumes on the next register or `visibilitychange`. The spring's own frames drive the sends, so there is nothing to time separately.

**Hardware notch**: `NotchChassis` already forces the style to black when closed with no wings (AC-8), and then no `Backdrop` is mounted, so no shapes are sent and the view hides. With wings, the wings are shells that register as shapes, and the black cutout block stays opaque in the DOM above the blur.

**Multiple displays**: every window runs its own renderer, its own loop and its own native view. Nothing is shared between them.

**Key invariants**:
- The native view is attached at most once per window and detached when the window closes.
- A Windows build, a missing addon or any load error keeps `glass:native` false, and every code path takes the capture route.
- Transparent never attaches a native view.

**Security model**: no permission is requested for native Glass. The addon runs in the main process with the app's own privileges, reads nothing from other apps, and takes only shape numbers from the renderer. Main validates the list before passing it on (an array of at most 16 finite numbers per shape, ear values limited to the two sides) so a bad message cannot crash the addon.

**Critical test scenarios**:
- Happy path: Glass on macOS with Screen Recording denied shows a blur only inside the open notch, dock and tray, verifies **AC-1**, **AC-2**, **AC-3**.
- Spring: record the screen at 60 fps through an open and a close, and check the blur edge against the shell, verifies **AC-4**.
- Hit testing: click on the strip beside the notch, then on the notch, verifies **AC-5**.
- Fullscreen: enter a fullscreen app, then leave it, verifies **AC-6**.
- Displays: All displays, then switch to one, then unplug one, verifies **AC-7**.
- Cutout: closed idle, closed with wings, and a display without a cutout, verifies **AC-8**.
- Fallback: rename the addon so it fails to load, and Glass asks for Screen Recording as before, verifies **AC-9**.
- Idle: with the notch closed and nothing changing, no `notch:glass` messages arrive, verifies **AC-11**.
- Packaged: build, ad hoc sign, run on arm64 and x64, verifies **AC-12**.

**Configuration required**: none for users. For the build: the Node API headers (a `node-api-headers` dev dependency, or the headers Electron already caches) and the existing Xcode command line tools.

## Build plan

Ordered as a tracer bullet: a thin working thread first, then the pieces around it.

1. **Spike gate.** Write a minimal `vibrancy.mm` that adds one `NSVisualEffectView` under the web contents and masks it to a fixed rounded rectangle; load it from `main.ts` behind an environment flag. Prove it on Electron 43 in the real panel window (`screen-saver` level, visible on fullscreen Spaces), then drive it with a spring and measure the lag and CPU. Satisfies **AC-1**, **AC-4**. If it fails, stop and take the fallback (keep capture Glass behind the permission), then tell the engineer.
2. **Real masking.** Build the union path from shapes, including the ear quarter and per corner radii, and set the frame to the bounding box. Add `attach`, `update`, `detach`. Satisfies **AC-2**, **AC-3**.
3. **Main side.** Add `main/mac/vibrancy.ts`, attach in `createNotchWindow`, handle `notch:glass` with validation, `glass:native`, keep the last list per window and reapply on `show`, and detach on close. Satisfies **AC-5**, **AC-6**, **AC-7**, **AC-9**.
4. **Renderer.** Add `renderer/lib/glassShapes.ts` with the single rAF loop and change-only send. Make `Backdrop` skip capture and video on the native path and register its host. Pass `ear` from `Ear`. Satisfies **AC-1**, **AC-3**, **AC-4**, **AC-11**.
5. **Settings.** In `SettingsPanel`, skip the Screen Recording check and hint when `glass:native` is true; keep it on the fallback. Satisfies **AC-1**, **AC-9**, **AC-10**.
6. **Cases.** Walk every scenario above: hardware notch closed, wings, no cutout, fullscreen hide and tuck, All displays, display unplug. Fix what the spike did not cover. Satisfies **AC-6**, **AC-7**, **AC-8**.
7. **Packaging.** Compile the addon for arm64 and x86_64 in `scripts/build-helper.sh`, lipo them together, ad hoc sign, and add it to the app files in `electron-builder.yml` (unpacked from the asar). Run the packaged app on both architectures. Satisfies **AC-12**.
8. **Docs.** Add a one line note to spec 0010 pointing here for the macOS Glass source.

## Migration plan

**Strategy**: strangler, switched by whether the native piece loads. The capture path stays in the code until native Glass has shipped and held up.
**Phases**:
1. Land the addon, main side and renderer together, with the capture path as the fallback (tasks 1 to 6).
2. Ship the packaged build and watch for load failures (task 7).
3. In a later spec, delete the capture path on macOS if the fallback was never hit.
**Rollback**: set `glassAvailable` to false (or revert the commit); Glass goes back to the capture path and its permission, with no data to migrate.
**Risks**: Electron's view stacking may not allow a sibling under the web contents (the spike answers this); the mask can lag the DOM by a frame; the unsigned addon could be refused if hardened runtime and library validation are ever turned on.

## Consequences

**Positive**:
- Glass on macOS needs no Screen Recording permission and no capture.
- The `pin()` drift problem and the 15 fps capture cost go away on the native path.
- Window shape, hit testing, display sync and the tuck stay as they are, so the risk stays in one file.

**Negative / tradeoffs**:
- DeskNotch now ships a compiled native addon for two architectures, which adds a build step and a place to break.
- The blur trails the drawn shape by up to one frame during a spring.
- The Glass look is the system's material, so it is less tunable than the capture recipe (blur radius and saturation are no longer ours to set).
- Two code paths exist for Glass until the capture path is removed.

**Neutral**:
- Spec 0010's Glass recipe still sets tint, rim and top highlight; only the blurred picture changes source.
- The `glass:*` capture channels stay for now.

## Follow-up

- [ ] Confirm `node-api-headers` (or Electron's cached headers) is the build input for the addon, and add it to `devDependencies`.
- [ ] Decide whether to remove the capture path on macOS after one release without fallback hits.
- [ ] If the one frame lag is visible on close, test a 1 point inset on the mask while the shell shrinks.
- [ ] Add a note to spec 0010 (task 8).
