# 0012. Add the Catppuccin cat as a companion, built on the same engine as the other companions, with switches to turn motion off

**Date**: 2026-10-31 (updated 2026-10-31: the cat now uses the library's own 3D engine)
**Status**: In Progress

## Summary

You get a new companion character, a cat drawn after the official Catppuccin mascot (dark body, light face, pink bow tie), that you pick in Settings next to ghost, blob and the others. It moves exactly like the other companions, because it runs on the same engine: the head turns in 3D to follow the pointer, the eyes blink and glance, it hops and spins when it is busy, and it breathes and nods when it sleeps. You choose the colour of its face from the notch's current Catppuccin flavour (Mocha, Macchiato or Frappé), and the tile glow and rings take that colour too. The cat is our own outline, not the official picture file, because the official file's licence is unconfirmed and a flat picture cannot move or recolour. Three new switches (Look around, Sleep at night, React to events) turn the companion's motion on or off for every character, all off by default.

## Context

The companion is a character that sits on the notch and reacts to the timer, tasks, music and the clock. Characters come from the `bot-avatars` library (ghost, cat, blob, clover, droid, alien, cloud) plus the user's own photo. The saved value is `avatar: BotAvatarType | 'photo'`. The notch already has Catppuccin flavours in `renderer/lib/catppuccin.ts` (three dark flavours, each with a base colour and eight accents), chosen in Settings for the notch fill.

**How the other companions work (checked in `node_modules/bot-avatars`, MIT licence).** Each bot is a 100 by 100 outline (an SVG path string) drawn on a canvas by `drawBotAvatarFrame`. The outline is stacked thirteen times through a depth and shaded as a glossy plastic solid, so it can turn (yaw), tilt (pitch) and roll in real 3D. A small simulation, `BotAvatarSim`, drives a pose each frame: yaw, pitch, roll, position, squash, blink, glance, breathing. It has three states: `default` (turns to look around, blinks, now and then a jump with a full turn), `working` (hopping, every third hop a spin, a wide smile, the odd laugh where the eyes close), `sleeping` (head down, lids shut, slow breaths, the odd nod). `setPointer` makes the head and eyes follow a pointer that comes near, and `poke` makes it hop. One shared frame loop runs all avatars and pauses offscreen. The library exports `BotAvatarSim`, `drawBotAvatarFrame`, `restPose`, `autoInk`, `BOT_AVATAR_OVERSCAN` and `BOT_AVATAR_RISE`, and the draw call takes any `Path2D`, so a new body is just a new outline.

The first version of the cat (inline SVG, moved by hand) looked flat and slid left and right, because it copied the look but not this engine. The official art (viewed for reference only, not bundled) is a dark head and shoulders, light closed smiling eyes, a small triangle nose, a wavy mouth and a pink bow tie, with the face turned slightly to the side. The official files are PNGs in the Catppuccin repo, the repo licence (MIT) does not mention the logo art, and a flat picture cannot take a chosen colour or move.

The companion also runs several things all the time. While the pointer is on the card, `useGaze` fires a fake pointer move every 90 ms and holds a capture listener. `useBurst` reacts to track, task and timer changes. The tile runs looping sway and bob animations. Today none of these can be turned off, and the sleep rule is only a choice between three schedules.

No design tool or `design.md` exists. The design source is the existing companion tile, the Settings companion section, and the official mascot.

## Requirements

**User stories**:
- As a user, I want a Catppuccin cat as my companion so the notch matches my Catppuccin setup.
- As a user, I want the cat to look like the official mascot and move like the other companions, so it does not feel like a flat sticker.
- As a user, I want to pick the cat's face colour from my flavour's colours so it matches my notch.
- As a user, I want to turn off the companion's looking, sleeping and reacting so it costs less memory and processor time.

**Acceptance criteria**:
- **AC-1**: Settings, Companion, Character offers a Catppuccin cat after the existing bots. Choosing it shows the cat in the companion tile (every mode), in the Focus and tasks desk view, and saves `avatar: 'catppuccin'`. The library `cat` stays available and unchanged.
- **AC-2**: When the cat is the chosen character, the Companion section shows a Coat row with the eight accents of the notch's current flavour as swatches. The default is Mauve. Picking one recolours the cat's face (eyes, nose, mouth, bow edge) in the tile, the desk view and the collapsed notch within about a second, with no restart.
- **AC-3**: The coat is stored by accent name (for example `Peach`), not by hex, so changing the notch flavour re-colours the cat with the new flavour's value of the same accent. A stored name the flavour does not have falls back to Mauve.
- **AC-4**: With the cat chosen, the tile glow, the sleeping Zs, the desk accent and the collapsed notch ring use the coat colour, the way other characters use their palette colour.
- **AC-5**: The cat behaves like the library bots because it runs on the same simulation: in `default` it turns its head in 3D, blinks and glances; in `sleeping` it has its head down, lids shut, slow breaths; in `working` it hops, spins every third hop, and laughs now and then. It follows a pointer that comes near (real or the companion's own aim) with head and eyes, and hops when clicked. It stays inside its tile box and never covers the task list.
- **AC-6**: The cat is drawn from one outline path in code. It makes no network request, adds no image file, and renders offline.
- **AC-7**: On a notch with a cutout, the collapsed notch shows the cat at 20 px in the left wing where the other characters show, behaving as the other characters do there, with its ring (when focusing) in the coat colour.
- **AC-8**: The Companion section has three switches: **Look around**, **Sleep at night**, **React to events**. They apply to every character, including the cat, ghost and the rest. Each is off by default (a missing saved value reads as off).
- **AC-9**: With **Look around** off, the companion starts no gaze timer, adds no pointer capture listener and dispatches no synthetic pointer events, and the body does not lean. With it on, behaviour is as today. A real pointer near a bot or the cat still turns its head, as it does for every bot today (that is the library's own pointer play).
- **AC-10**: With **Sleep at night** off, the companion never sleeps (no sleeping state, no Zs), including in Clock mode at night, and the existing Sleep schedule row is hidden. With it on, the Sleep schedule row shows and the existing rule applies unchanged.
- **AC-11**: With **React to events** off, there is no burst (the working state) on a new track, a finished task or a timer change, and no looping idle motion (focus sway, clock bob, task hop). With it on, behaviour is as today.
- **AC-12**: Existing saved settings load unchanged: no key is renamed or removed, the `ghost` default stays, and a user with the old `cat` bot still sees that bot. The only change on update is that the three new switches read as off.
- **AC-13**: The `photo` character and the library bots behave as before apart from the three switches.
- **AC-14**: The cat's silhouette reads as the official mascot: dark head and shoulders with two pointed ears, a face in the coat colour, a bow tie in the flavour's Red (Pink when the coat is Red), and a faint rim in the coat colour so the dark body still shows on the dark notch.

## Options considered

### Option 1: Our own SVG cat moved by hand (first build, replaced)

Draw the cat as a small React component of SVG shapes and move it with the motion library.

**Pros**:
- Exact palette colours, no canvas, tiny.

**Cons**:
- It cannot turn in real 3D, so it slid and swayed in 2D and did not feel like the other companions (this is why it was replaced).
- Every behaviour (blink, glance, hop, nod) would have to be re made by hand and kept in step.

### Option 2: Bundle the official PNG and tint only the accent

**Pros**:
- It is the real mascot, almost no drawing work.

**Cons**:
- The cat cannot change colour, cannot move, has no states, and the logo licence is unconfirmed. A Mocha or Frappé file was not found.

### Option 3: Official PNG with a hue rotate filter

**Pros**:
- Quick, uses the official art.

**Cons**:
- Colours drift from true palette values, no motion, same licence question.

### Option 4: Recolour the library `cat`

**Pros**:
- Least code, full engine behaviour.

**Cons**:
- It is a round butter coloured cat, not the Catppuccin look, and the library has no per part colour.

### Option 5: Our own outline of the official cat, drawn by the library's engine (chosen)

Write a small canvas component, `CatppuccinCat`, that does what the library's `BotAvatar` does: a `BotAvatarSim` for the motion, `drawBotAvatarFrame` for the 3D solid, the library's shared pointer and frame loop pattern, and our own outline path, our flavour colours for body, face and bow.

**Pros**:
- Same 3D turn, blink, glance, hop, spin, laugh, nod and breathing as every other companion, with no behaviour re made by hand.
- Exact flavour colours and a true coat picker, and no licence question (our outline, MIT engine).
- One outline string, no image file, no network.

**Cons**:
- The engine draws round eyes that blink. The official closed smiling eyes appear only in the working laugh. A nose is not drawn by the engine.
- The bow tie is drawn by us on top of the solid and slides with the head's yaw, so it is a little flatter than the body.
- It is a canvas, so there is no memory saving over the other characters.
- We rely on the library's exported rig staying as it is (pinned at `bot-avatars` 0.1.1).

## Decision

**Chosen option**: Option 5: our own outline of the official cat, drawn by the `bot-avatars` engine.

We add a new `catppuccin` character: a canvas component built on `BotAvatarSim` and `drawBotAvatarFrame` with our own outline path, recoloured from the notch flavour by accent name, and add three global motion switches, all off by default. In the tile and everywhere else it is treated like any bot (the same lean wrapper, the same `CALM` settings, the same pointer play).

**Implementation skills**: `frontend-design` (`.claude/skills/frontend-design/`) · `macos-design-guidelines` (`.claude/skills/macos-design-guidelines/`)

## Rationale

The engineer asked for the official look and for the cat to move like the other companions. Reading the library showed the movement comes from a shared engine that is exported and accepts any outline, so the cheapest way to move exactly like the others is to use it, not to imitate it. That is Option 5. Runner up: Option 1, which the engineer rejected after seeing it slide in 2D.

The official art cannot be used as the picture itself (licence unconfirmed, flat, no colour or motion), so we redraw its outline and colours. The engine's round eyes replace the closed smiling eyes, which the engineer accepted by asking for the same behaviour as the others. Runner up: draw the closed eyes ourselves on top of the solid, which would not blink or follow the head.

The coat is stored as an accent name rather than a hex so the cat follows the flavour with no extra setting (AC-3). Runner up: a hex, which would stay on the old flavour's value. The coat colours the face and glow, while the body stays the flavour's dark base as in the mascot (runner up: coat as the body colour, which the engineer found did not look official).

The three switches default to off because the engineer chose that, and they apply to every character because the gaze timer and animations are shared code. The engineer was shown that this changes existing behaviour on update and kept it. Runner up: default on for existing characters, off for the cat only.

## Feature design

**Data model sketch**:

No database. The change is to the saved `Settings` object in the main process store (`desknotch-store.json`), through the existing `store:set` and `store:changed` sync.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `avatar` | `BotAvatarType` or `'photo'` or `'catppuccin'` | `'ghost'` (unchanged) | The chosen character. `'catppuccin'` is new. |
| `catAccent` | string, optional | missing (reads as `Mauve`) | Accent name for the cat's face colour, one of the flavour's accent names. |
| `companionLook` | boolean, optional | missing (reads as off) | Look around: gaze and lean. |
| `companionSleepOn` | boolean, optional | missing (reads as off) | Sleep at night: allows any sleeping. |
| `companionReact` | boolean, optional | missing (reads as off) | React to events: bursts and looping idle motion. |

The existing `companionSleeps` (`time`, `idle`, `never`) is kept and only used when `companionSleepOn` is on.

**State transitions**:

No new machine. The tile passes the cat the state it already computes: `sleeping` when asleep (only if `companionSleepOn`), `working` while a burst runs (only if `companionReact`), else `default`. The simulation owns everything the state looks like.

**API surface**:

| Surface | Kind | Key inputs | Key outputs | Auth | Key errors |
|---|---|---|---|---|---|
| `CatppuccinCat` component | React canvas, `renderer/components/widgets/CatppuccinCat.tsx` | `size:number`, `coat:string` (hex), `flavor:Flavor`, `state`, plus `interactive`, `paused`, `turn`, `jumpEvery` as the bots take them | a canvas that draws the cat | none | none |
| `catCoat(flavor, accentName)` | function in `renderer/lib/catppuccin.ts` | flavour id, accent name or undefined | hex string | none | unknown name returns the flavour's Mauve |
| `avatarAccent(settings)` | function in `renderer/lib/catppuccin.ts` | the settings | hex: the coat for the cat, `botAvatarPalette[avatar]` for bots, white for photo | none | none |
| `CompanionTile` props | change | adds `accent`, `look`, `canSleep`, `react`, `flavor` | none | none | none |
| Settings, Companion section | UI change | the three switches, the Coat row, the picker button | writes through `onChange` | none | none |

No new IPC, endpoints or main process code.

**Value sourcing**:

| Action | Value produced / displayed | Source |
|---|---|---|
| Draw the cat | Face colour (eyes, nose, mouth) | `catCoat(settings.notchFlavor ?? DEFAULT_FLAVOR, settings.catAccent)`: the flavour's accent named by `catAccent`, Mauve if missing or unknown, passed to the engine as `ink` |
| Draw the cat | Body colour | The flavour's `base` (the mascot's dark), passed as `color` |
| Draw the cat | Bow colour | The flavour's `Red` accent; if the coat is Red, the flavour's `Pink` |
| Draw the cat | Rim colour | The coat colour at low strength, so the body shows on the dark notch |
| Draw the cat | Pose (turn, blink, hop, nod, breathing) | `BotAvatarSim` from `bot-avatars`, seeded per instance, state from the tile |
| Draw the cat | Where the head looks | `BotAvatarSim.setPointer` from the document pointer position, as the library does |
| Tile glow, Zs, desk accent, collapsed ring | Accent colour | `avatarAccent(settings)`, computed once in `home.tsx` and passed down as `accent` |
| Cat state | `sleeping`, `working` or `default` | The existing `asleep` and `bursting` values in `CompanionTile`, after the switch gates below |
| Gate gaze | Whether `useGaze` runs | `settings.companionLook === true`, passed as `look` |
| Gate sleep | Whether the companion may sleep | `settings.companionSleepOn === true`, passed as `canSleep`; the schedule still comes from `companionSleeps` |
| Gate reactions | Whether bursts and idle loops run | `settings.companionReact === true`, passed as `react` |
| Coat swatches | Eight colours and names | `FLAVORS[settings.notchFlavor ?? DEFAULT_FLAVOR].accents` |
| Collapsed notch | Whether the cat shows | `settings.showAvatar` and the existing cutout rule in `CollapsedStatus`, unchanged |

**Key invariants**:
- A missing `catAccent`, `companionLook`, `companionSleepOn` or `companionReact` is valid and reads as Mauve, off, off, off. Nothing writes them until the user changes them.
- `companionLook` off means `useGaze` registers no listener and starts no interval; it is not a visual only gate.
- `companionSleepOn` off beats `companionSleeps`: `asleep` is false whatever the schedule says.
- `companionReact` off beats all looping or burst motion; sleeping breathing is part of sleeping and not gated here.
- The cat's colours always come from `FLAVORS`, never from literals in the component.
- The cat uses the library's exported engine only through its documented exports (`BotAvatarSim`, `drawBotAvatarFrame`, `restPose`, `autoInk`, `BOT_AVATAR_OVERSCAN`, `BOT_AVATAR_RISE`), and its canvas keeps the library's overscan margins so a hop is never clipped.
- The library `cat` value and the `photo` value keep their current code paths.

**Security model**:

No new data, permissions, network access, secrets or storage beyond three booleans and one accent name in the existing local settings file. No compliance scope.

**Configuration required**: none.

**Critical test scenarios**:
- Look: pick the cat and see a dark cat with a light face and a pink bow, with a glossy 3D body like the other bots, verifies **AC-14**, **AC-5**
- Motion parity: next to the ghost, the cat blinks, glances, turns its head in 3D, and hops when clicked, verifies **AC-5**
- Happy path: choose the cat, pick Peach, see a Peach face in the tile, desk and collapsed notch with a Peach glow, verifies **AC-1**, **AC-2**, **AC-4**, **AC-7**
- Flavour change: with Peach chosen, switch the notch from Mocha to Macchiato and the face becomes Macchiato's Peach, verifies **AC-3**
- Unknown accent: set `catAccent` to a name the flavour lacks and the face is Mauve, verifies **AC-3**
- States: with the switches on, a task done shows the working hops, night in Clock mode shows the sleeping cat with Zs, verifies **AC-5**
- Look off: with the pointer on the card and Look around off, no synthetic `pointermove` is dispatched and no 90 ms interval runs (check with a spy), verifies **AC-9**
- Sleep off: Clock mode at 2 AM with Sleep at night off shows an awake companion and no Sleep schedule row, verifies **AC-10**
- React off: a new track or finished task causes no burst and the focus sway does not run, verifies **AC-11**
- Offline: block the network and the cat still renders, verifies **AC-6**
- Upgrade: load a settings file saved before this change and the ghost, the old `cat`, and the other values are unchanged while the three switches show off, verifies **AC-12**, **AC-13**

## Build plan

Thin end to end slices (Tracer Bullet). Tasks 1, 5, 6 and 7 landed in the first build and stay. Tasks 2 to 4 are reworked for the engine.

1. [x] Add `'catppuccin'` to the `Avatar` type, add the four optional `Settings` fields, and add `catCoat` and `avatarAccent` to `renderer/lib/catppuccin.ts`, satisfies **AC-3**, **AC-12**
2. [x] Rework `CatppuccinCat.tsx` as a canvas component on `BotAvatarSim` and `drawBotAvatarFrame`: our outline path of the official cat, body from `base`, face ink from the coat, bow drawn on top and slid with yaw, library overscan margins, shared pointer following, click poke, reduced motion and offscreen pause as the library does, satisfies **AC-5**, **AC-6**, **AC-14**
3. [x] In `CompanionTile`, `CollapsedStatus`, `ReminderView`, `DoneView` and `SettingsPanel` render the cat like any bot (the same lean wrapper and idle move in the tile, `CALM` settings, `interactive` as bots have it), and remove the hand made `gx`, `gy` head turn, satisfies **AC-1**, **AC-4**, **AC-7**
4. [x] `accent` flows from `home.tsx` into the tile, desk, collapsed ring and the other views, satisfies **AC-4**
5. [x] Settings: the cat button after the bots, and the Coat row of flavour accent swatches shown only when the cat is chosen, satisfies **AC-1**, **AC-2**, **AC-3**
6. [x] The three switches in the Companion section, Sleep schedule row hidden when Sleep at night is off, each default off, satisfies **AC-8**, **AC-10**
7. [x] Gate the behaviour in `CompanionTile`: `look` into `useGaze`, `asleep` false without `canSleep`, bursts and looping `idleMove` skipped without `react`, satisfies **AC-9**, **AC-10**, **AC-11**, **AC-13**
8. [ ] Run the critical test scenarios above by hand, comparing the cat next to the ghost, satisfies **AC-2**, **AC-3**, **AC-5**, **AC-12**

## Consequences

**Positive**:
- A Catppuccin themed companion that looks like the mascot, moves exactly like the other companions, follows the notch flavour, and has a real colour picker.
- Turning the switches off stops a 90 ms timer, a capture listener and looping animations for every character.
- No new dependency, image file or network use.

**Negative / tradeoffs**:
- After updating, existing users' companions stop looking, sleeping and reacting until they switch those on. This is deliberate (all off by default) and should be in the release notes.
- The cat is our own outline in the official style, not the official artwork.
- The cat has round blinking eyes like the other bots; the official closed smiling eyes show only in the working laugh. There is no nose from the engine.
- The bow tie is drawn by us and only slides with the head's turn, so it is a little flatter than the body.
- The cat is a canvas like the other bots, so it brings no memory saving. The switches stop timers and animations only.
- The cat depends on `bot-avatars` internals that are exported but young (0.1.1); a library update that changes the rig could need a small fix.

**Neutral**:
- `avatarAccent` replaces three inline `botAvatarPalette` lookups, which touches `home.tsx`, `CompanionTile` and `CollapsedStatus`.
- The new settings keys are optional, so no migration is needed.

## Follow-up

- [ ] If Catppuccin confirms the logo art may be bundled, decide whether to offer the official PNG as a second look; it would not take a coat colour or move.
- [ ] Consider a switch or rule that also pauses the `bot-avatars` canvases when all three switches are off, for a larger saving. Not decided here.
- [ ] Mention the all off default in the next release note.
- [ ] `docs/scope/` does not exist yet, so this feature is not enrolled. Run `/scope` to enroll it if you want it tracked.
- [ ] Note in `AGENTS.md` (via `/sync`) that the cat is drawn on the `bot-avatars` exported engine.
