# 0010. Add Transparent and Glass notch styles with a native macOS look

**Date**: 2026-10-31
**Status**: Accepted

> On macOS, Glass is now drawn with a native blur and needs no Screen Recording when it loads; see spec 0013. This spec still describes the fallback.

## Summary

DeskNotch gets two new looks beside Default (black): Transparent, a clear pane you can see the desktop through, and Glass, a frosted pane like macOS Liquid Glass. Both are drawn from the live screen picture the notch already uses, with different blur and tint settings. The open panel, the status wings, the cards inside the panel and the companion tile all change to match. The part over the physical cutout stays black so the notch still merges with the hardware.

## Context

Today the setting `notchStyle` is `black` or `glass`. Glass shows a blurred live capture of the screen behind the notch (`Backdrop.tsx`, one capture at 15 frames per second shared by every surface, which needs the macOS Screen Recording permission). The notch shell, the dock, the apps tray and the two small corner curves (the ears) all draw that one backdrop. Cards inside the panel (`Tile`) are flat white at 5 to 15 percent over the shell, and the companion tile (`CompanionTile`) is one of them.

Two facts shape the work. First, on a notched MacBook the closed shell is forced to black (`NotchChassis`: `hardware && !isOpen ? 'black'`), so under any style the status wings beside the cutout are black today. Spec 0004 requires that the cutout area stays pure black. Second, Electron's window `vibrancy` option cannot be used: the notch window is a wide transparent strip, and vibrancy fills the whole window rectangle, not the notch shape.

The request says "whole UI". This spec covers the closed bar and wings, and the open panel with its tiles, views and companion. The dock and apps tray already share the backdrop, so they follow the chosen style without separate work. Type scale, icon set and general motion are not redesigned here. A separate native Mac companion app was considered and left out (see Follow-up).

There is no `design.md` and no design tool. The design source is the current UI plus the installed `liquid-glass`, `macos-design-guidelines` and `frontend-design` skills.

## Requirements

**User stories**:
- As a Mac user, I want a clear Transparent look and a frosted Glass look for the notch, so it feels like part of macOS.
- As a user with a notched MacBook, I want the cutout to stay black, so the notch still looks like it grew out of the hardware.
- As a user who has not allowed Screen Recording, I want the notch to stay Default and tell me why, so nothing breaks.

**Acceptance criteria**:
- **AC-1**: Settings, Style shows three choices in a segmented control: Default, Transparent, Glass. Picking Transparent or Glass without Screen Recording permission leaves the style unchanged and shows a hint that names Screen Recording.
- **AC-2**: `notchStyle` accepts `'black' | 'transparent' | 'glass'`, default `'black'`. A saved `'glass'` stays `'glass'`, a saved `'translucent'` becomes `'glass'`, a saved `'mica'` becomes `'black'`. No other setting is added.
- **AC-3**: Glass and Transparent use the values in the **Glass recipe** table below. On the same wallpaper they look clearly different: Glass is frosted (blur 24 on large surfaces), Transparent is clear (blur 4).
- **AC-4**: Transparent never draws a tint lighter than alpha 0.18 at any point, and text on it carries a soft shadow. Primary text stays readable over a white wallpaper.
- **AC-5**: On a notched display, closed with nothing to show, the notch is pure black and no screen capture is running. Closed with something to show, the cutout width stays black and each wing shows the chosen glass. On a display without a cutout, the whole closed pill shows the chosen glass.
- **AC-6**: Open, the shell, the two ears, the dock and the apps tray all use the chosen style from one backdrop, with no seam where they meet.
- **AC-7**: Cards in the open panel use soft inner glass in every style: a 1 pixel light rim on the top edge, a corner radius that nests inside the panel radius, and three text levels (primary, secondary, tertiary white) instead of ad hoc opacities.
- **AC-8**: The companion tile shows a soft glow behind the avatar in the avatar's own palette, and its four modes (Timer, Reminder, Clock, Screen time) switch with a macOS style segmented control whose thumb slides with a spring. All four modes still work as before.
- **AC-9**: The screen capture starts when the first glass surface appears and stops when the last one goes away or the style is Default.
- **AC-10**: Before the first video frame, or when the capture cannot start, every glass surface shows its tint and stays legible, with no empty or flashing area.

## Options considered

### Option 1: Both styles on the existing live capture, with a settings table

One `Backdrop` component, two recipes (blur, saturation, brightness, tint, rim).

**Pros**:
- One pipeline and one permission; the dock, tray and ears follow for free.
- Smallest change to code that already works.

**Cons**:
- Needs Screen Recording permission for both styles.
- Real macOS lensing (refraction) is not possible; it is an imitation made from blur and light.

### Option 2: Transparent as a plain tint, no capture

**Pros**:
- No permission for Transparent.

**Cons**:
- A tint with no blur does not read as glass, just a dim rectangle. Two code paths to keep.

### Option 3: A native material from the Swift helper

Draw the material with `NSVisualEffectView` or Liquid Glass in the helper, or use Electron `vibrancy`.

**Pros**:
- The truest macOS material, no capture, no permission.

**Cons**:
- The notch shape is drawn in the web layer and springs between sizes; a native view would have to follow it frame by frame. Window vibrancy fills the whole strip. A large new native surface for a small visual gain.

## Decision

**Chosen option**: Option 1: Both styles on the existing live capture, with a settings table.

Keep one `Backdrop`, give it a `kind` of `'transparent' | 'glass'`, and drive its look from one recipe table.

**Implementation skills**: `liquid-glass` (`casper-studios/casper-marketplace`, `.agents/skills/liquid-glass/`) · `macos-design-guidelines` (`ehmo/platform-design-skills`, `.agents/skills/macos-design-guidelines/`) · `frontend-design` (`anthropics/skills`, `.agents/skills/frontend-design/`)

## Rationale

The notch already pays for a capture and a permission, so a second style on the same pipeline costs almost nothing, while a separate path (Options 2 and 3) adds code and a worse result. The liquid-glass skill says glass belongs on the layer that floats above content and never on the content itself, which is why the shell and ears are glass and the cards inside it stay low contrast. Its ultra thin and regular material split maps to Transparent and Glass.

Decisions made here without asking (runner up in brackets):
- Tint floor and text shadow for legibility on Transparent (adapting text colour to the picture was the runner up; it flickers and costs more code).
- Tiles get the new inner glass in all three styles, not only the glass ones, so there is one card style to maintain (per style variants were the runner up).
- The black cutout block is drawn on top of the glass, not by shrinking the glass, so the glass shape stays one rounded rectangle.

## Feature design

**Data model sketch**:
- `Settings.notchStyle`: `'black' | 'transparent' | 'glass'`, required, default `'black'`. Stored with the rest of `settings` under the `store:get` key `settings`. The existing load step in `home.tsx` already maps old values; add nothing but the new value.

**State transitions**:
- Style changes only by the user in Settings. Picking `transparent` or `glass` first calls `glass:permission`; on `false` the style does not change and the hint shows.

**Glass recipe** (starting values, tuned by eye on a light and a dark wallpaper before they are fixed; the "small" column is for surfaces under 60 px on the short side, as today):

| | Transparent | Glass |
|---|---|---|
| Video filter, large | `blur(4px) saturate(1.3) brightness(0.95)` | `blur(24px) saturate(1.8) brightness(0.9)` |
| Video filter, small | `blur(2px) saturate(1.3) brightness(0.95)` | `blur(10px) saturate(1.8) brightness(0.9)` |
| Tint (top to bottom) | `rgba(8,8,12,0.18)` to `rgba(8,8,12,0.26)` | `rgba(8,8,12,0.28)` to `rgba(8,8,12,0.42)` |
| Rim | 1 px `rgba(255,255,255,0.22)` on sides and bottom | same, plus an inner top highlight `rgba(255,255,255,0.14)` fading out in 12 px |
| Text shadow | `0 1px 2px rgba(0,0,0,0.35)` | none |
| Fallback fill (`CORNER_FILLS`, before first frame) | `rgb(20,20,24)` | `rgb(20,20,24)` |

**Closed bar on a notched display**: the effective style is `black` when `wings` is 0. When `wings > 0` and the chosen style is not `black`, the shell uses the chosen style and a black block (width `hardware.w + 2 * CUTOUT_BLEED`, height `hardware.h`, top centre) is drawn above the backdrop. Ears follow the effective style.

**Inner glass tokens** (in `globals.css`): `--text-1: rgba(255,255,255,0.92)`, `--text-2: rgba(255,255,255,0.62)`, `--text-3: rgba(255,255,255,0.38)`. `Tile` gets the top rim `inset 0 1px 0 rgba(255,255,255,0.14)`, a `border` of white at 0.08, and a radius of `calc(var(--radius-notch-open) - 14px)` so it nests inside the 30 px panel radius. Gradients keep today's thin and tinted faces.

**Companion**: `CompanionTile` passes `glow` built from `botAvatarPalette(avatar)` (a radial gradient behind the avatar, alpha at most 0.35). The mode control becomes a segmented control with one sliding thumb (`layoutId`), using the existing `spring` motion curve.

**Value sourcing**:
| Action | Value | Source |
|---|---|---|
| Draw a surface | Filter, tint, rim | The Glass recipe table, selected by effective style |
| Draw a surface | Effective style | `settings.notchStyle`, forced `black` when closed on a cutout with `wings === 0` |
| Closed on a cutout | `wings`, `hardware.w`, `hardware.h` | Existing `CollapsedStatus` item width, `useHardwareNotch()` |
| Style change | Permission result | `glass:permission` (existing) |
| Companion glow | Colour | `botAvatarPalette(avatar)` (existing) |
| Small or large filter | Surface size | `getBoundingClientRect()` of the host, under 60 px short side is small (existing rule) |

**Key invariants**:
- No `Backdrop` is mounted, so no capture runs, whenever the effective style is `black`.
- The cutout width is black in every style.
- Pointer, hover and click areas do not change (spec 0004 AC-5 still holds).

**Security model**: no new data leaves the machine. The capture is the existing local capture, excluded from itself by `glass:protect`. Screen Recording permission is requested exactly as for Glass today.

**Configuration required**: none.

**Critical test scenarios**:
- Happy path: pick Transparent, then Glass, on a light and a dark wallpaper; open the panel; the two look different and text is readable. Verifies **AC-3**, **AC-4**, **AC-6**.
- Permission refused: pick Glass with Screen Recording off; style stays Default and the hint shows. Verifies **AC-1**.
- Old settings: load with `translucent`, `mica`, `glass`, and none. Verifies **AC-2**.
- Closed on a notched Mac: idle shows pure black and no capture; start a timer and the wings show glass with a black centre; on a non notched display the whole pill is glass. Verifies **AC-5**, **AC-9**.
- Cold start: first open before a frame arrives shows the tint, not a blank. Verifies **AC-10**.
- Cards and companion: tiles show rim, nested radius and three text levels in all three styles; the companion glow and sliding mode control work in all four modes. Verifies **AC-7**, **AC-8**.

## Build plan

Build approach: none recorded (no `AGENTS.md`), so this uses end to end Tracer Bullet slices: the thinnest working thread first, then thicken.

1. Add `'transparent'` to `NotchStyle`, the `CORNER_FILLS` map and the Settings segmented control with the permission check for both glass types; widen `Backdrop`'s `kind` and move its values into the recipe table (both styles render in the open panel, ears, dock and tray), satisfies **AC-1**, **AC-2**, **AC-3**, **AC-4**, **AC-6**, **AC-10**.
2. Make the closed bar use the chosen style when `wings > 0`: the effective style rule, the black cutout block, ears following the effective style; confirm capture stops when nothing is drawn, satisfies **AC-5**, **AC-9**.
3. Inner glass for `Tile` and `TileLabel`: rim, nested radius, `--text-1/2/3` tokens, replace ad hoc white opacities in the tile based widgets, satisfies **AC-7**.
4. Companion tile: avatar glow and the segmented mode control with a sliding thumb, satisfies **AC-8**.
5. Tune the recipe table by eye on light and dark wallpapers, notched and non notched; record the final numbers in this spec, satisfies **AC-3**, **AC-4**.

## Consequences

**Positive**:
- The notch reads as native macOS in two distinct looks, with one backdrop and one permission.
- The dock, tray and ears follow for free; the companion and cards share one surface language.

**Negative / tradeoffs**:
- Both new styles need Screen Recording permission, and a heavier blur costs more GPU on the capture layer (blur 24 is the cap).
- The glass is an imitation, with no real refraction.
- Saved `glass` users see their notch get frostier without asking.
- Restyling `Tile` changes Default users' cards too.

**Neutral**:
- `CORNER_FILLS` and `Backdrop` gain a key; the recipe table is the single place to tune the look.

## Follow-up

- [x] Tune and record the final recipe numbers (build task 5). Checked by eye on light and dark wallpapers; the starting values in the Glass recipe table are the final ones, as built in `Backdrop.tsx` `RECIPES`.
- [ ] Decide on a native SwiftUI companion app for Mac as its own spec if you still want one; it was left out here.
- [ ] Check whether macOS "Reduce transparency" can be read in this Electron version, and if so make glass surfaces solid under it.
- [ ] Type scale, SF Symbols style icons and general motion are not part of this spec; a follow up spec if wanted.
- [ ] The project has no `AGENTS.md`; running `/audit` would record the three installed design skills so later work finds them.
