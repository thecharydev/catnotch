# 0006. Claude requests as a slim strip, not a card

**Date**: 2026-10-29
**Status**: In Progress

## Summary

Today a Claude request (Allow, Deny, a question) takes over the whole notch with a tall card, so you lose the tab you were using. This changes it to a slim strip, about 44 pixels tall, that slides in at the top of whatever tab is open. The tab stays usable underneath. Allow is the one strong button, Deny is quiet, and "Ask in terminal" becomes a small icon. A simple question shows as a line with up to three answer chips you can tap; anything that needs reading or typing opens a full card in the same place. It also fixes one annoyance: the 30 second timer no longer runs while you are typing an answer.

## Context

Spec [0002](0002-claude-code-notch-popup/index.md) made the request a view of its own (`view === 'claude'`) sized 196 to 300 pixels tall, and spec [0005](0005-claude-section-sessions-and-answers.md) added typed answers and a Claude tab. In use, the card hides the tab you were on and forces the notch tall. The engineer wants that space back.

There is no `design.md` in the project and no design tool was chosen. The design source is the notch's own look (dark glass, `white/[0.08]` surfaces, pill buttons, the companion's accent colour, 10 to 13 pixel text) plus the installed `frontend-design` skill, whose rules shape the choices below: spend boldness in one place, no all caps labels, no strings joined with middle dots, no decoration without a job, motion only where it answers something.

The code touched is `renderer/components/widgets/ClaudeView.tsx`, `renderer/pages/home.tsx`, `renderer/components/notch/NotchChassis.tsx` (size only) and `main/ipc/claude.ts` (the timer). This is an ENHANCEMENT: the replies, guards and rules of 0002 and 0005 do not change.

## Requirements

**User stories**:
- As someone using the notch for other things, I want a waiting Claude request to take a thin strip, so that I keep my tab and my dock.
- As the same person, I want one clear Allow and calm Deny, so that I decide fast and do not hit the wrong one.
- As the same person, I want a quick question answered by one tap, and a long one to open so I can read and type.
- As someone typing a longer answer, I want the timer to wait for me, so that the question is not handed back mid sentence.

**Acceptance criteria** (the contract, each independently checkable):
- **AC-1**: With the notch open on any tab, a new request shows as a strip at the top of the content, with the tab dock still visible and clickable. The selected tab does not change. The strip is 44 pixels tall for a permission request and 76 for a question.
- **AC-2**: With the notch closed, a new request opens it to the strip alone (no tab content under it), and it folds again once nothing is waiting, as 0002 AC-3 and AC-10 require.
- **AC-3**: A permission strip shows the tool name and project folder name, the first line of the command in a monospace face cut with an ellipsis, a **Deny** button, a solid **Allow** button in the companion accent, and an icon button for "Ask in terminal" with a tooltip and an `aria-label`. With more than one waiting request it also shows "1 of N".
- **AC-4**: Clicking the command area expands the strip to show up to 6 lines (all lines scrollable, at most 110 pixels), and clicking again collapses it.
- **AC-5**: A question with one part and no multi select shows its text on one line and up to three option chips. A tap on a chip answers at once. With more than three options the third slot is a "+N" chip that opens the card.
- **AC-6**: A multi select question, a question with several parts, and any wish to type open the card through an expand control. The card is the 0005 question view (full scrollable text, options with descriptions, text box, Back, Next, Send, "Answer in terminal") in the same place, restyled to the rules in AC-7.
- **AC-7**: Style rules hold on strip and card: Allow is the only solid accent button; Deny and the terminal icon are quiet; no all caps text, no labels joined by middle dots, buttons are pills and fields have one corner radius; every control has a visible keyboard focus ring and an accessible name; text has at least 4.5 to 1 contrast on its background.
- **AC-8**: The strip slides down once on arrival (at most 200 ms) and fades out on answer (at most 150 ms). With the system "reduce motion" setting on there is no movement, only an instant change. No looping animation.
- **AC-9**: While the card's text box has focus or holds text, the 30 second fall through timer for that request does not run. It restarts at 30 seconds when the box loses focus empty, or never runs while text is in it; Send and Pass answer as before. A request with no typing behaves as in 0002 AC-5.
- **AC-10**: The Claude tab's sessions list is restyled to the same rules: a sentence case header with the count, no all caps, no middle dots; rows, badges and states as in 0005 AC-1.
- **AC-11**: While a strip shows, the notch is at least 420 pixels wide and returns to the tab's own width after.
- **AC-12**: Nothing else changes: the replies sent to Claude, the token and host guards, the in front rule, typed answers, the Claude tab and Settings all behave as in 0002 and 0005.

## Options considered

### Option 1: Strip on top of the open tab, expand for long questions

A slim strip over the tab content, chips for simple questions, a card only when needed.

**Pros**:
- Frees the space; the tab and dock stay usable.
- Most requests (a command, a yes or no style question) are one tap.

**Cons**:
- Two layouts (strip and card) to build and keep consistent.
- The notch grows a little when a strip arrives.

### Option 2: Replace only the dock row

**Pros**: content height does not change.

**Cons**: tabs are unreachable while waiting, which is part of what you wanted back.

### Option 3: A separate pill below the notch

**Pros**: the notch never changes size.

**Cons**: needs a taller transparent window and its own hit testing; more risk than the gain.

## Decision

**Chosen option**: Option 1: Strip on top of the open tab, expand for long questions

Requests render as a `ClaudeStrip` above the current view's content, expanding to the existing card on demand, with a typing aware timer.

**Implementation skills**: `frontend-design` (`anthropics/skills`, `.agents/skills/frontend-design/`)

## Rationale

Option 1 is the only one that keeps both the tab content and the dock in reach, which is the stated need. The card stays for the cases that need room (reading, typing, several parts), so nothing is lost. Option 3 is more machinery for the same result.

Following the installed skill's restraint rule, boldness goes in one place: the Allow button. Everything else is quiet text and ghost pills. Chips use the existing `white/[0.08]` surface so they read as options, not as a second set of buttons.

The timer fix is small and belongs here because the strip's expand control invites typing. Pausing while the box has focus keeps the 0002 safety property: a request still always ends, since leaving the box empty restarts the 30 seconds, and a Send or Pass answers it.

## Feature design

**Data model sketch**: none stored. One in memory change in `main/ipc/claude.ts`: `Pending` gains `held: boolean` (the timer is off while true).

**State transitions** (a request, as in 0002) plus: pending → held (typing) → pending (box emptied and blurred, timer restarted) · held → answered or passed. Every exit clears the timer.

**API surface** (IPC only, no new HTTP):
| Channel | Direction | Purpose |
|---|---|---|
| `claude:hold` | renderer invoke | `(id, on)`: on clears the request's timer, off starts a fresh 30 second timer |

**Layout** (wireframes, widths in pixels):
```
Permission strip, 44 tall, at least 420 wide
 o  Bash  napo   npm run build --workspace app...    [Deny] [Allow]  [>_]
 dot  label     command (mono, ellipsis, click to expand)  quiet  accent  icon

Question strip, 76 tall
 o  napo  Which database should we use for sessions?          1 of 2   [v]
    [ Postgres ]  [ SQLite ]  [ +2 ]

Expanded card: the 0005 question view, same place, up to 300 tall
```

**Visual tokens** (from the notch's own look; no new palette):
- Surface: `white/[0.08]` for chips, fields and quiet buttons; command box `black/40`.
- Accent: the companion accent, used for Allow, Send and the waiting dot only. Waiting dot also amber `#fbbf24` for "waiting for you" as in 0005.
- Type: the notch's existing family. Tool and project 11 px semibold; command 11 px monospace; question 12 px semibold; chips 11 px medium; no all caps anywhere.
- Shape: pills (full radius) for buttons and chips, 8 px radius for fields and the command box.

**Value sourcing** (every shown or sent value and where it comes from):
| Action | Value produced / displayed | Source |
|---|---|---|
| Show permission strip | Tool name | `tool` on the request view (hook `tool_name`) |
| Show permission strip | Project name | `project` on the request view (basename of `cwd`) |
| Show permission strip | Command line | first line of `text` on the request view (0002 `describe`) |
| Show permission strip | "1 of N" | position and length of the in memory queue (0002) |
| Expand command | Lines shown | the rest of `text`, 6 lines then scroll |
| Show question strip | Question line | `questions[0].question` |
| Show question strip | Chips | first three `questions[0].options` labels in order; "+N" is the remaining count |
| Tap a chip | Answer | the chip's option label, sent as in 0005 |
| Strip height | 44 or 76 | `kind` of the first request and whether it is a simple question (AC-5), else the card height |
| Strip or no strip | Which request | `requests[0]` from `useClaude` (oldest first) |
| Closed notch opens to strip only | Whether it was closed | `beforePeek.current === null` in `home.tsx` (existing peek logic) |
| Timer hold | on or off | focus and content of the card's text box |
| Reduced motion | Whether to animate | the system `prefers-reduced-motion` setting |

**Key invariants**:
- Allow is sent only from a click on that exact request's Allow button (0002 invariant, unchanged). A chip tap sends only the chip's own label.
- Every request still gets exactly one reply or is dropped by Claude. Holding the timer never leaves a request without an exit: Send, Pass, a dropped connection and quitting DeskNotch all still end it.
- A strip never moves keyboard focus when it arrives.
- The strip never changes the selected tab.

**Security model**: unchanged from 0002 and 0005. No new network surface. The hold channel only affects a timer on a request the renderer already holds.

**Configuration required**: none.

**Critical test scenarios**:
- Open on Calendar, trigger a permission request: strip slides in, Calendar stays selected, dock clickable, Allow sends allow, verifies **AC-1**, **AC-3**, **AC-8**.
- Notch closed, trigger a request: opens to the strip alone and folds after answering, verifies **AC-2**.
- Long command: click to expand to 6 lines, scroll, collapse, verifies **AC-4**.
- Single select question: tap a chip, Claude gets the label; a four option question shows "+N", verifies **AC-5**.
- Multi select and a three part question open the card; type an answer and send, verifies **AC-6**.
- Type for 40 seconds: the question is still there; clear the box and click away: it ends after 30 seconds, verifies **AC-9**.
- Tab through every control, check focus rings, names and contrast; turn on reduce motion, verifies **AC-7**, **AC-8**.
- Look at the Claude tab list, verifies **AC-10**; check the notch width with and without a strip, verifies **AC-11**.
- Re run the 0002 and 0005 reply checks, verifies **AC-12**.

## Build plan

No build approach is recorded for the project, so this uses end to end thin slices (Tracer Bullet): a working thread first, then thicker.

1. Thin thread: a `ClaudeStrip` for permission requests (tool, project, first line, Deny, Allow, terminal icon) rendered above the current view's content in `home.tsx` without switching the tab, with the 44 pixel height and the 420 pixel minimum width, satisfies **AC-1**, **AC-3**, **AC-11**, **AC-12**
2. Closed notch: peek opens to the strip alone and folds when the queue empties, satisfies **AC-2**
3. Expand the command to 6 lines with scroll, and the "1 of N" count, satisfies **AC-3**, **AC-4**
4. Question strip: one line, up to three chips, "+N", and the expand control that opens the 0005 card restyled to the tokens, satisfies **AC-5**, **AC-6**
5. Typing aware timer: `claude:hold` in `main/ipc/claude.ts`, called from the card's text box on focus, input and blur, satisfies **AC-9**
6. Style, motion and access pass: the visual tokens, focus rings, accessible names, contrast, one slide in, one fade out, reduced motion, satisfies **AC-7**, **AC-8**
7. Sessions list restyle (sentence case header, no all caps) and docs lines in README and `doc/Functionality.md`, satisfies **AC-10**

## Consequences

**Positive**:
- Your tab and dock stay usable while Claude waits.
- Most requests are one tap, and the strongest button is the safest to find.
- Typing no longer races a hidden timer.

**Negative / tradeoffs**:
- Two layouts to maintain, and the strip must fit 420 pixels with a long project name (names are cut with an ellipsis).
- The notch grows by the strip height while a request waits, so content shifts down briefly.
- Pausing the timer while you type means a forgotten, half typed answer keeps the request alive until you clear the box or answer; Claude's own prompt is still available in the terminal.

**Neutral**:
- Chips show only the first three options, so a long question needs one more tap.
- No keyboard shortcuts yet (still left out as in 0002).

## Follow-up

- [ ] Installed skill to flag for `AGENTS.md` `## Agent skills`: `frontend-design` (`anthropics/skills`, `.agents/skills/frontend-design/`), design guidance for UI work. `/audit` or `/sync` owns writing it.
- [ ] The first choice, `leonxlnx/taste-skill@redesign-existing-projects`, no longer exists in its repo; only `design-taste-frontend` does. Not installed.
- [ ] Spec 0002 AC-3, AC-5 and AC-9 and spec 0005 AC-6 are changed by this spec; add a line to each pointing here once built.
- [ ] This feature has no row in `docs/scope/` (no scope folder exists). Run `/scope` to enroll it if you want it tracked.
