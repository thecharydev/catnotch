# 0004. Make the closed and open notch merge with the MacBook cutout

**Date**: 2026-10-29
**Status**: Accepted

## Summary

On a notched MacBook, DeskNotch should look like the real cutout grew, the way Vibe Island does. Today it can show as a separate shape below the cutout, and it shrinks to a sliver when Brave is in front. This spec pins the window to the very top, makes the idle notch exactly the cutout, puts status in two wings beside the cutout, makes the open panel hang from the cutout with no seam, and stops the browser tuck on notched screens so Brave's tabs are never covered. It amends spec 0001 (AC-2 and the tuck part of AC-11).

## Context

Spec 0001 says the closed notch matches the cutout and sits flush with it. The pieces exist: the Swift helper reports the cutout size per display (checked on this Mac: 179 by 32 points on display 1), and `NotchChassis` sizes the closed shell to it. The reported problem is that the result looks like a second pill under the cutout.

Two causes are likely, and only one has been confirmed by reading. Confirmed: the closed notch is exactly as wide as the cutout, so anything the bar draws (`CollapsedStatus`) sits behind the physical notch and cannot be seen, and the open panel starts with a 6 pixel bar then full width, so it never visually grows out of the cutout. Not yet confirmed: whether macOS places the window below the menu bar. The window is a `panel` made with `enableLargerThanScreen`, but the level is raised only after creation, and macOS clamps a frame to the area under the menu bar at construction. This must be measured, not assumed.

Separately, `fullscreen.ts` tucks the notch to a 6 pixel sliver when a browser is frontmost, to keep it off the tab strip. On a notched screen the cutout is already there and the sliver adds a second, odd shape.

## Requirements

**User stories**:
- As a MacBook user, I want the notch to look like the cutout itself, so it feels native.
- As a Brave user, I want my tabs left alone, so the notch never adds black over them.
- As a user, I want status beside the cutout, not hidden behind it.

**Acceptance criteria** (notched display unless stated):
- **AC-1**: The notch window's top edge equals the display's top edge (`window.getBounds().y === display.bounds.y`). Idle and closed, the drawn shape is exactly the cutout size (width `w`, height `h` from the helper) and is pure black, whatever the Notch style setting says.
- **AC-2**: When the closed notch has something to show (the item `CollapsedStatus` already picks: a moment, timer, playing media, and so on), it widens to the cutout plus one wing each side. The left wing shows that item's icon, the right wing its time, detail or progress. Nothing is drawn inside the cutout width. When there is nothing to show, it returns to exactly the cutout.
- **AC-3**: Open, the shape's top edge is cutout wide for the cutout height, then widens to the open width with concave curved corners at the join. There is no gap or seam, and view content starts below the cutout row. Open shapes of existing views keep their content size.
- **AC-4**: With Brave (or any listed browser) in front, the closed notch on a notched display is not shrunk and adds no black outside the cutout and its wings. On a display without a cutout (the pill), the existing Shrink over browsers behaviour is unchanged.
- **AC-5**: Hover and click areas follow the drawn shape, wings included, and the strip still passes clicks through everywhere else.
- **AC-6**: With no helper or no cutout reported, the notch renders exactly as it does today (pill, sliver tuck, 6 pixel open bar).

## Options considered

### Option 1: Fix the window and split the existing bar (chosen)

Keep one window per display and the current `NotchChassis`. Fix the window position, add wings by splitting `CollapsedStatus` into a left and right slot around the cutout, give the open shell a cutout wide neck, and skip the tuck when a cutout exists.

**Pros**:
- Small change, no new window or process.
- Reuses the helper values and the existing status selection.

**Cons**:
- The open shape needs a custom outline with concave corners.

### Option 2: A second native window for the wings

Draw wings in a separate window placed beside the cutout.

**Pros**:
- Wings could never be clipped by the main strip.

**Cons**:
- Two windows to keep aligned, animate and hit test. More moving parts for the same look.

### Option 3: Leave the shape, only drop the tuck

**Pros**:
- Almost no code.

**Cons**:
- The notch still looks like a pill below the cutout, which is the main complaint.

## Decision

**Chosen option**: Option 1: Fix the window and split the existing bar

One strip window, pinned to the top edge, whose renderer draws a cutout sized idle shape, wings when active, a neck shaped open panel, and no tuck on notched displays.

## Rationale

The helper and the chassis already model the cutout, so the gap is presentation, not data. A second window (Option 2) would double the synchronisation problems the single strip was built to avoid. Dropping only the tuck (Option 3) does not answer the look the engineer wants. Wings need no new data because `CollapsedStatus` already chooses one item to show; this only splits where it is drawn.

## Feature design

**Constants** (new, in `NotchChassis.tsx`): `WING = 64` points per side (room for an icon on the left and a short time on the right), `FILLET = 12` points for the concave corners. Both are recommendations; tune on a real notch.

**Shape rules** (hardware `w`, `h` from `useHardwareNotch`):

| State | Width | Height | Outline |
|---|---|---|---|
| Closed, idle | `w` | `h` | rounded bottom corners only, black |
| Closed, active | `w + 2 * WING` | `h` | same, black, content only in the two wings |
| Open | `expandedWidth` | `expandedHeight + (h - BAR_OPEN)` | neck `w` wide for the top `h`, then full width with `FILLET` concave joins, Notch style applies below the neck |
| Pill (no cutout) | as today | as today | as today |

**Value sourcing**:
| Action | Value | Source |
|---|---|---|
| Size the idle shape | `w`, `h` | `notch:hardware` from the helper (spec 0001) |
| Pin the window | top edge | `display.bounds.y` in `main/display.ts` |
| Decide wings | whether active | `CollapsedStatus` already has a chosen item or none |
| Left wing | icon | the chosen item's icon (`MOMENT_ICON` and the existing media, timer and task icons) |
| Right wing | time, detail, progress | the chosen item's existing text |
| Skip tuck | cutout exists | `hardware !== null` in the renderer; `notch:tucked` is left as is |
| Closed colour on cutout | black | fixed, not `notchStyle` |

**Key invariants**:
- Nothing is drawn within `w` of the closed shape's centre.
- The window top equals the display top.
- Total open height stays under `STRIP_HEIGHT` (500) in `main/main.ts`.

**Critical test scenarios**:
- Happy path: notched Mac, idle, nothing in the cutout row but black, window y is 0, verifies **AC-1**. Start a timer, wings appear and the cutout area stays plain, verifies **AC-2**. Hover, panel hangs from the cutout, verifies **AC-3**.
- Browser: Brave frontmost, idle, no extra shape over the tab strip, verifies **AC-4**. An external monitor still tucks, verifies **AC-4**.
- Failure: delete the helper binary and launch, behaviour is as today, verifies **AC-6**.
- Pointer: click Brave's tab just left of the wing, the click reaches Brave, verifies **AC-5**.

## Build plan

Ordered as a tracer bullet: prove the position first, then thicken.

1. Measure first. Log `window.getBounds()` against `display.bounds` for each notch window on this Mac, and capture a screenshot of the top of the screen. Record whether y is pushed down. This decides step 2, satisfies **AC-1**.
2. If y is pushed down: call `window.setBounds(bounds)` after `setAlwaysOnTop(true, 'screen-saver')` in `createNotchWindow` (`main/main.ts`) and again on `show`, so the frame is set once the level is high. If y is already the top: the offset is in the renderer, so find the wrapper that pads the top of the page in `home.tsx` or `NotchChassis` and remove it. Satisfies **AC-1**.
3. Closed idle on a cutout: force black and exact `w` by `h` in `NotchChassis` regardless of `notchStyle`. Satisfies **AC-1**.
4. Skip the tuck when a cutout exists: `const sliver = tucked && !isOpen && !hardware`. Satisfies **AC-4**, **AC-6**.
5. Wings: give `CollapsedStatus` a `split` mode when `hardware` exists, rendering the chosen item's icon in a left slot and its text in a right slot with a `w` wide empty centre, and have `NotchChassis` animate the closed width between `w` and `w + 2 * WING`. Pill mode keeps today's single row. Satisfies **AC-2**, **AC-6**.
6. Open shape: add the `w` wide neck and `FILLET` concave joins as the shell's outline (clip path or SVG mask), offset content by `h - BAR_OPEN`, and report the new rectangles through `notch:bounds`. Satisfies **AC-3**, **AC-5**.
7. Update spec 0001 AC-2 and AC-11 text to point here, and run the scenarios above on this Mac and one external monitor. Satisfies **AC-1** to **AC-6**.

## Consequences

**Positive**:
- Looks native on a notched MacBook; Brave's tabs are untouched.
- Status becomes visible when closed, where before it hid behind the cutout.

**Negative / tradeoffs**:
- The open shape needs a custom outline, harder to style than a rounded rectangle.
- Open panels grow a little taller on notched displays (by the cutout height minus 6).

**Neutral**:
- The Shrink over browsers setting now only affects displays without a cutout.
- Idle closed notch is always black on a cutout, so Glass and Mica styles show only when open.

## Follow-up

- [ ] Step 1 may show a different cause than the one assumed here. If so, amend Context and step 2 before building on.
- [ ] Tune `WING` and `FILLET` on real hardware.
- [ ] Decide later if showing Brave's open tabs inside the notch is wanted. It was offered and not chosen, and would need browser automation permission.
