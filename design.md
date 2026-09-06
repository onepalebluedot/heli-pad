# Heli-Pad: the "Next" design language

This document describes the existing "Next" tab, Concept 03, as of September 5, 2026. The reference implementation is [next-concept.css](./next-concept.css) and [next-concept.js](./next-concept.js), with the shared shell in [index.html](./index.html). Open `index.html#next` to view the concept.

"Next" is a warm family handoff sheet. An ivory page, forest-green trip card, and serif greeting give the schedule a domestic, personal character. Compact sans-serif labels keep times, children, places, and responsibilities easy to scan. The strongest visual emphasis belongs to the next decision a caregiver needs to make.

The concept remains an experiment within the UX lab. [SYSTEM.md](./SYSTEM.md) defines the broader product direction and the unresolved choice of home screen. This document records the current design and gives guidance for extending it. Values and behavior were checked against source; local-file browser access was blocked, so this pass does not include rendered visual verification.

## Design principles

- Lead with timing. The largest operational text says when to leave, whether there is time, or what needs confirmation.
- Keep responsibility visible. Put the child and caregiver beside the activity, with explicit leave-by and arrive-by labels below.
- Use warmth with restraint. Cream, sage, butter yellow, a small sun, and rounded corners establish the character. Most of the page stays flat and quiet.
- Make urgency specific. Consuming the travel buffer and arriving late are different states. Explain the consequence in words as well as color.
- Keep the day in context. The agenda retains earlier unconfirmed handoffs, and the caregiver grid shows the distribution of work.
- Reveal detail on demand. Trip details open in a bottom sheet; editing and driver comparison use the existing shared dialogs.

## Page composition

The screen is one vertical column inside a mobile app shell. Its reading order is deliberate.

| Order | Element | Role |
| --- | --- | --- |
| 1 | Heli-Pad header and profile controls | Establish the app and active caregiver. The header shares the ivory page background. |
| 2 | Date eyebrow, "Your day, together.", sun | Introduce the day with a small editorial masthead. The eyebrow identifies preview or live time. |
| 3 | Seven-day selector | Choose today or one of the next six days. Each button stacks a day label, date, and small dot. |
| 4 | Caregiver scope and "Switch caregiver" | State whose handoffs the hero and agenda show. |
| 5 | Next handoff card | Present the timing decision, child, caregiver, route, and actions. |
| 6 | Earlier-handoff notice, when needed | Keep unconfirmed past activity visible while a future trip occupies the hero. |
| 7 | Daily agenda and child filters | Show the remaining schedule as compact rows with aligned times. |
| 8 | Add appointment and optional suggestion | Place creation and driver-review actions beside the schedule they affect. |
| 9 | "Who's got what?" | Show four caregiver cards in a two-column grid. |
| 10 | Design preview clock | Keep the sample-time controls at the foot of the concept. |

The floating bottom navigation remains visible over the scrolling content. It has six equal columns, a warm white background, and a pale sage selection behind "Next". The floating add button is hidden in this mode; the agenda has its own full-width add action.

## Color

Use muted green and warm neutrals throughout the Next content. Forest green is the main emphasis color. Pale yellow marks the primary action within the dark hero. Thin sage rules divide content without enclosing every row in a card.

| Role | Value | Current use |
| --- | --- | --- |
| Page ivory | `#f6f4ed` | App background and topbar |
| Warm white | `#fffef8` | Bottom navigation, details sheet, text on dark cards |
| Forest | `#235746` | Default hero, selected day, sheet primary action; `--nx-green` |
| Green ink | `#233d33` | Main text; `--nx-ink` |
| Muted green-gray | `#687469` | Supporting text; `--nx-muted` |
| Sage rule | `#dfe2d6` | Agenda separators and card outlines; `--nx-line` |
| Butter | `#e9e7bc` | Primary action on the hero, with `#283e2d` text |
| Selected navigation | `#e7eedf` | Active bottom-tab fill |
| Selected child filter | `#e6e9db` | Pressed chip, with `#cbd3bd` border |
| Caregiver card | `#fdfcf6` | Resting crew-card background |
| Selected caregiver | `#e8ecdf` | Selected crew card, with `#9daa8c` border |
| Suggestion wash | `#eeecd6` | Review notice, with `#dddcbc` border |
| Sun ochre | `#ad722d` | Masthead sun |
| Warning text | `#9a482c` | Unconfirmed, unassigned, or overlapping agenda entries |
| Focus copper | `#af612d` | Keyboard focus outline |

Caregiver identity uses pale backgrounds and dark initials. Preserve the written name or initial alongside the color.

| Caregiver | Badge background | Badge text |
| --- | --- | --- |
| Mom | `#e7ddc9` | M |
| Dad | `#dce7d4` | D |
| Nani | `#eadce5` | N |
| Grandma | `#dde6ea` | G |
| Family | `#eae7c5` | All |
| Unassigned | `#f0dcc6` | ? |

## Typography

The shared interface uses **Plus Jakarta Sans**, followed by system sans-serif fallbacks. Buttons inherit that family. The masthead alone uses **Georgia**, followed by Times New Roman and serif. This gives the greeting a personal voice while operational information stays compact.

| Element | Size | Weight and treatment |
| --- | --- | --- |
| Masthead greeting | 32px | Georgia, 400; line-height 1.08; tracking `-0.045em` |
| Hero timing heading | 31px | Sans-serif, 650; line-height 1.13; tracking `-0.055em` |
| AM/PM suffix in applicable hero headings | 18px | 500; tracking `-0.03em` |
| Details-sheet title | 22px | Inherited heading weight; line-height 1.3; tracking `-0.04em` |
| Section heading | 17px | 700; tracking `-0.04em` |
| Date numeral | 17px | 700 |
| Child name in hero | 15px | Bold |
| Agenda time | 14px | 750; line-height 1.25 |
| Caregiver scope | 13px | 750 |
| Agenda title and route labels | 12px | 650–750 depending on role |
| Supporting text | 10–12px | Muted color; line-height usually 1.5–1.7 |
| Eyebrow | 10px, 9px in hero | 800; uppercase; tracking `0.14em` |

Use sentence case for headings and actions. Uppercase is reserved for short eyebrows and the design-preview label. Keep the timing heading visually dominant when it wraps.

## Spacing, shape, and depth

The standard content gutter is 22px. Content has 4px of top padding and 110px of bottom padding to clear navigation. Major section headings have 23px of space above and 10px below. Related controls use smaller gaps of 4–10px.

| Component | Geometry |
| --- | --- |
| Hero | 22px radius; 18px padding |
| Day button | 13px radius; minimum height 52px; 4px grid gap |
| Hero actions | 10px radius; minimum height 44px; 8px gap |
| Child filter | 30px radius; minimum height 36px; 5px wrapping gap |
| Agenda row | `48px / flexible / 38px` columns; 9px gaps; 14px vertical padding |
| Agenda caregiver badge | 35px circle |
| Add appointment | 10px radius; minimum height 44px; dashed outline |
| Suggestion | 15px radius; 15px padding; 18px top margin |
| Caregiver grid | Two equal columns; 8px gap |
| Caregiver card | 13px radius; 12px padding; 26px badge |
| Workload indicator | 3px-high rounded track |
| Bottom navigation | 66px high; 22px outer radius; 16px active-tab radius |
| Details sheet | 26px top corners; 22px top and 24px side padding; maximum height 86% |

Keep elevation slight. The hero uses `0 7px 12px -9px #203f3350`; navigation uses `0 4px 24px #253e3310`. Agenda rows sit directly on the page with a single bottom rule. The sheet uses a larger upward shadow and a translucent green backdrop, `#15362955`, to establish its modal position.

## Component language

### Handoff card

The card has a fixed information sequence: ownership eyebrow and status badge, large timing heading, short explanation, child and activity, route, then actions. Its dark background gives this entire group priority over the agenda.

The route has a hollow circular origin and a pale square destination connected by a dashed vertical line. Place names occupy the middle column; departure and arrival times align on the right. Always retain "leave by" and "arrive by" labels so the two times cannot be confused.

The primary action stretches across the available width and uses a butter fill. "Edit" is a smaller outlined button beside it. The primary label follows the situation: "View trip", "View appointment", "Find a driver", or "Review handoff".

Thin, low-opacity concentric circles extend beyond the right edge of the card. They are background decoration and must not compete with the route or timing text.

### Agenda

Rows align time, activity, and caregiver in three columns. The activity contains child names and a shortened title, then venue and a departure or status line. Let titles wrap within the flexible column.

The activity text opens details. The caregiver circle opens driver comparison. Completion happens inside the details sheet. Completed rows are hidden initially; revealing them shows 57% opacity, a struck-through title, and a "Completed" label. The hero's corresponding row receives a green time label.

Child filters are outlined pills. Selection adds a sage fill, stronger border, and heavier text. The remaining count and hero follow the selected day, caregiver, and child. The add action is a full-width dashed outline immediately below the agenda.

### Suggestions and caregiver workload

Suggestions use a pale yellow panel with a small star or return symbol, a short question, supporting evidence, and an underlined review action. For example, "A little less driving for Mom?" invites comparison. Selecting it opens the existing driver dialog; the suggestion itself does not reassign anyone.

Crew cards show name and initial, handoff count, driving minutes, and the next child/time. The thin bar represents that caregiver's share of the day's total calculated driving minutes. It is a relative workload indicator, not completion progress or remaining capacity. Crew cards summarize the whole selected day even when the agenda has a child filter.

Selecting a caregiver updates the shared profile, clears the child filter, and returns to the top. "View everyone" selects the whole family. "Switch caregiver" scrolls to this grid.

### Details sheet

Trip details rise from the bottom of the app over a green-tinted scrim. The warm white sheet repeats the child/day eyebrow and gives the activity a larger title. Location, activity window, travel estimate, buffer, and assigned caregiver appear as readable paragraphs.

Actions stack vertically. Completion is forest-filled; editing and caregiver comparison use light backgrounds. Buttons have an 11px radius and minimum height of 46px. A circular close button sits beside the title.

The sheet is specific to Next. Appointment editing and driver assignment reuse shared prototype dialogs; their styling is only partly adapted by Next's modal background and primary-color overrides.

## Timing and feedback states

Color reinforces the status label and explanation. The same warm palette carries urgency through olive and clay.

| Situation | Card treatment | Message pattern |
| --- | --- | --- |
| More than 10 minutes before departure | Forest `#235746` | "You have time" and "Leave in …" |
| Within 10 minutes of departure | Olive `#55532e`; pale amber badge `#f5e0a3` | "Get ready" |
| Departure reached, estimated arrival still on time | Olive | "Time to go" and "Leave now", with estimated arrival and remaining margin |
| Leaving now would miss arrival, before scheduled start | Clay `#814d3c`; peach badge `#f7d9bb` | "Running behind" and "… min late if you leave now" |
| Scheduled start reached without completion | Clay | "Check status" and "Did this handoff happen?" |
| Driver unassigned, before scheduled start | Olive | "Driver needed" and "Who can take this one?" |
| Future day with an assigned caregiver | Forest | "Planned" and an absolute "Leave at" or "Be there at" time |
| At-home activity before its start | Forest | "At home" and "Together at …" |
| No remaining handoffs in the current view | Forest | "You're all caught up." or "Nothing on your list." for a future day |

The code checks elapsed start time before the other conditions. A past, unfinished handoff therefore requests confirmation, including when its driver is unassigned. Future unfinished trips take priority in the hero; earlier unconfirmed activity remains in a notice and the agenda. Once no future trip remains, an unconfirmed handoff can occupy the hero.

The all-clear message is scoped to the current filters. Its supporting copy says "in this view" so it does not imply that the entire family has finished the day.

## Icons, motion, and interaction

Use small symbols with clear jobs. The masthead sun is a 40px line drawing in ochre, rotated by -12 degrees. Child icons sit in a 39px pale-yellow tile. Diagonal arrows accompany actions, initials identify caregivers, and route markers distinguish origin and destination. Decorative icons are hidden from assistive technology.

Motion is brief. The shared screen entrance fades and moves 6px over 200ms. The details sheet enters from 22px below over 200ms with ease-out. Caregiver navigation scrolls smoothly. Reduced-motion rules remove the Next screen/sheet animations and app transitions, and the caregiver jump becomes immediate.

Day, child, preview-clock, and caregiver selections expose `aria-pressed`. Next buttons use a 3px copper focus outline with a 3px offset. The details sheet has a labeled dialog role, traps Tab between its buttons, accepts Escape or a backdrop click to close, and returns focus to the trigger. The periodic render preserves focused Next buttons when their matching action remains present.

The current design includes 9–11px metadata and several controls smaller than 44px. These are prototype measurements, not a completed accessibility audit. For production, verify text contrast, text scaling, and touch targets while preserving the visual hierarchy.

## Responsive behavior

The desktop prototype centers a phone frame with a maximum width of 490px and 36px corners. At viewport widths of 520px or less, the frame fills the viewport and loses its decorative border, shadow, and rounded corners. The screen keeps one content column; the caregiver grid keeps two.

At 370px or less, Next reduces side gutters to 15px, the greeting to 28px, the hero heading to 29px, and the sun to 34px. Hero padding becomes 17px. Agenda columns become `44px / flexible / 34px` with 7px gaps. Route text and filter padding tighten as well. Child filters wrap instead of requiring horizontal scrolling.

Bottom navigation and sheet padding account for the bottom safe area. The outer desktop page retains the shared prototype's cool background; it is separate from Next's ivory in-app palette.

## Copy and prototype boundaries

Write as a caregiver coordinating a day. Use familiar words such as "handoff", "take this one", "leave", "arrive", and "together". Give each warning a next step: confirm the handoff, compare caregivers, or edit the plan. Keep reassurance tied to an actual state or time estimate.

The preview clock defaults to 2:40 PM and offers 3:00 PM, 3:15 PM, and Live. It is local to this concept and is not persisted. The date strip uses sample August dates. Travel estimates, driver suggestions, and family data come from the prototype. Keep those facts explicit in design reviews; neither "Live" nor the route presentation establishes a live routing or calendar integration.

When extending Next, preserve its serif greeting, ivory canvas, dark timing card, aligned agenda, and pale caregiver identities. Put additional information at the point where it helps a decision, and keep secondary operations in the details or comparison flows. Use the existing component dimensions and semantic colors before introducing new visual treatments.
