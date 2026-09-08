# Heli-Pad: the warm design language (Go, Plan, Family)

This document describes the shipped visual language as of September 7, 2026. **Go** is the daily execution view, **Plan** is the assignment-first weekly companion, and **Family** handles household setup. The older **Next** and **Today** concepts remain documented below as historical experiments, but they are not navigation tabs and are not loaded by the app.

All shipped surfaces share an ivory page, forest-green tone cards, Newsreader headlines, Plus Jakarta Sans body and labels, Lucide line icons, and named caregiver/kid tags. Go presents one decision — *do I need to move, and when?* — while Plan answers *who handles what this week?* [SYSTEM.md](./SYSTEM.md) records the architecture and integration boundaries; [BUILD.md](./BUILD.md) turns those decisions into an implementation spec.

## Standing direction: graphic over text

This is the product owner's stated preference and it outranks the more specific guidance below when the two disagree. Applied first in Go; extend Next toward it as Next is revised.

- **Prefer a mark to a sentence.** A ring, a spine, a dot, a coloured bar, an avatar, an emoji — if the state can be drawn, draw it. Reach for prose only when a mark would be genuinely ambiguous.
- **Push contrast up.** Tone cards are three clearly different backgrounds (forest, olive, clay), not three shades of one. A viewer should read the state from across a kitchen before reading a single word. One highlight — `#ffd36b` — is reserved for the two states that mean *act now*.

- **A gauge must actually move.** A ring, bar, or meter pinned at full for hours is decoration, not information. If a range is too wide for a linear mapping, make the mapping piecewise so the gauge is most expressive where the decision lives.
- **One channel, one job.** Do not encode the same fact twice. In Go the card background carries *how urgent* and the ring carries *how much run-up is left* — two channels, two facts, no explanatory sentence.
- **Line work, not emoji — everywhere, no exceptions.** Emoji arrive with somebody else's colour, weight and gloss; a row of them reads as decoration rather than data and competes with the dial for attention. Every icon on this screen is one stroke weight in the current text colour: transit modes, weather, activity presets, places, children, actions, the sheet's close control. *(An earlier pass kept children as emoji, on the theory that the emoji was the identity a family already uses. It was overruled on review, and rightly — the child's **name** is the identity, and three coloured pictograms were three more things to look at.)* Where an icon adds nothing, there is no icon: rail rows name their children in the venue line rather than badging them.

- **A mark plus a name, never a mark alone.** *(Amended after review — an earlier pass put caregiver and child names in `title`/`aria-label` only, and a lone initial or emoji turned out to be a memory test.)* People are the one thing that must not be reduced to a glyph: pair the pale disc or Lucide person icon with the written name. The disc carries the colour, the word carries the identity. Every other fact on the screen still prefers the mark.
- **Swap instead of stack.** When two surfaces answer related questions, give them one slot and a visible way to switch, rather than two permanent modules. Fewer assets on screen beats more information per scroll.
- **Reduce copy to its operative words.** "min to leave" becomes "min". "Nothing left to drive · 3 stops never checked off" becomes a moon glyph, "Day is over", and "3 never checked off".
- **Keep the two exceptions.** *Leave* and *arrive* stay labelled on the route bar, because confusing those two times has a real cost. Every warning still names its next step.

## Design principles

These hold for both concepts. Go applies them with the standing direction above layered on top: the same priorities, expressed with fewer words.

- Lead with timing. The largest operational text says when to leave, whether there is time, or what needs confirmation.
- Keep responsibility visible. Put the child and caregiver beside the activity, with explicit leave-by and arrive-by labels below.
- Use warmth with restraint. Cream, sage, butter yellow, a small sun, and rounded corners establish the character. Most of the page stays flat and quiet.
- Make urgency specific. Consuming the travel buffer and arriving late are different states. Explain the consequence in words as well as color.
- Keep the day in context. The agenda retains earlier unconfirmed handoffs, and the caregiver grid shows the distribution of work.
- Reveal detail on demand. Trip details open in a bottom sheet; editing and driver comparison use the existing shared dialogs.

## Page composition (Next)

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

Go reuses these exact values; it adds no palette of its own. Forest, olive, and clay are the three tone-card backgrounds, butter is the primary action on a dark card, ochre marks the sun and needs-attention states, and sage rules divide the rail.

Caregiver identity uses pale backgrounds and dark initials. Pair each initial with a visible written name. Tooltips and accessibility labels supplement the name; they do not replace it.

| Caregiver | Badge background | Badge text |
| --- | --- | --- |
| Mom | `#e7ddc9` | M |
| Dad | `#dce7d4` | D |
| Nani | `#eadce5` | N |
| Grandma | `#dde6ea` | G |
| Family | `#eae7c5` | All |
| Unassigned | `#f0dcc6` | ? |

These pale grounds are deliberately quiet behind a dark initial, so they cannot also carry a bar on an ivory track. Charts use the same hues at chart strength: Mom `#bda170`, Dad `#7fa375`, Nani `#bc86a5`, Grandma `#7f9fad`, Family `#c2ba6b`, unassigned `#cf9a63`. Identity stays recognisable and the bar stays readable.

## Typography

The shared interface uses **Plus Jakarta Sans**, followed by system sans-serif fallbacks. Buttons inherit that family. The masthead alone uses **Georgia**, followed by Times New Roman and serif. This gives the greeting a personal voice while operational information stays compact. In Go the serif is reserved for the date line, and nothing else on that screen uses it.

The table below is Next's scale; Go's is in its own section.

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

## Component language (Next)

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

## Timing and feedback states (Next)

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

## Icons, motion, and interaction (Next)

Use small symbols with clear jobs. The masthead sun is a 40px line drawing in ochre, rotated by -12 degrees. Child icons sit in a 39px pale-yellow tile. Diagonal arrows accompany actions, initials identify caregivers, and route markers distinguish origin and destination. Decorative icons are hidden from assistive technology.

Motion is brief. The shared screen entrance fades and moves 6px over 200ms. The details sheet enters from 22px below over 200ms with ease-out. Caregiver navigation scrolls smoothly. Reduced-motion rules remove the Next screen/sheet animations and app transitions, and the caregiver jump becomes immediate.

Day, child, preview-clock, and caregiver selections expose `aria-pressed`. Next buttons use a 3px copper focus outline with a 3px offset. The details sheet has a labeled dialog role, traps Tab between its buttons, accepts Escape or a backdrop click to close, and returns focus to the trigger. The periodic render preserves focused Next buttons when their matching action remains present.

The current design includes 9–11px metadata and several controls smaller than 44px. These are prototype measurements, not a completed accessibility audit. For production, verify text contrast, text scaling, and touch targets while preserving the visual hierarchy.

## Go — the departure view

Go answers one question: *do I need to move, and when?* It is the graphic-first direction applied end to end, and it is the reference for how to extend the language.

### Composition

Nothing sits above the dial. The week strip and the filters live below it, which also satisfies the Today gesture contract in [SYSTEM.md](./SYSTEM.md) — a filter never outranks leave-in.

| Order | Element | Role |
| --- | --- | --- |
| 1 | Masthead | Today's date in serif on the left, today's weather on the right. No greeting, no scope sentence. |
| 2 | Dial card | The whole decision: countdown ring **beside** the route, then destination, who and which kids as named chips, actions. |
| 3 | Scope row | Three segments — day, caregiver, child — each showing its current value as a mark and a word. |
| 4 | Scope drawer | Whichever picker the scope row has swapped open. Empty by default. |
| 5 | Panel head | Section title, day-completion pips, and the two-icon panel swap. |
| 6 | Panel | Either the rest-of-day rail or the wheel-time chart. The rail ends with **Add a stop**. |

The floating add button is hidden in Go, as it is in Next. Go carries no create flow of its own, and the button is one more asset competing with the dial.

### Two scopes, deliberately different

The dial answers *when do **I** leave next?* That is a fact about right now and about the profile you are signed in as, and **nothing in the scope row may change it**. The list below is a browsing surface: it can show any day, any caregiver, any child.

| Surface | Shows | Moved by |
| --- | --- | --- |
| Masthead, dial, hero dots, **Live** | Today, the signed-in profile | The clock, and the topbar profile switcher |
| Rail, wheel time, panel title | The chosen day, caregiver and child | The three scope segments |

Every segment in the scope row — day, caregiver, child — is a list control. Picking Thursday is *looking ahead*, not navigating: the countdown must survive it, because it is the thing you opened the app for. The caregiver picker says so in a line beneath it, and the masthead keeps naming today so the two are never confused.

The panel title names whose day is listed — "Rest of day" when it is mine and today, "Thursday" when I have looked ahead, "Dad's day", "Everyone · Thu". Switching profile is the one action that moves both: the dial follows the new profile and the list resets to it.

### The two swaps

Swapping is how Go keeps its asset count down. Each swap replaces a module that would otherwise be permanently on screen. All three follow the lab's rule from [SWIPE-TAP-MAP-v1.md](./design-lab/SWIPE-TAP-MAP-v1.md): **swipe accelerates, never hides** — every swap has a visible tap path first.

| Swap | Replaces | Tap path | Accelerator |
| --- | --- | --- | --- |
| **Scope** | A day strip, a crew strip, and a filter row, all permanently stacked | Tap a segment to open its picker; tap it again to close | — |
| **Panel** | A wheel-time card sitting permanently below the rail | The two-icon toggle in the panel head | — |

**There was a third swap, and it was removed.** The dial used to cycle through the day's stops on a drag, with a dot rail beneath it. It put the screen's one certainty — *this is what is next* — behind a gesture, and the rail already covers browsing. The dial now shows the next stop and nothing else. Rail rows open a stop's details; nothing moves the dial but the clock and the profile switcher.

### The route, beside the dial

The two times and the count are one decision, so they are one glance. The dial and the route share the top of the card rather than stacking, which shortens it by roughly a third and brings the destination, the people and the actions above the fold.

**The dial keeps its size.** It is the reason the screen exists, so it stays at 168px beside the route — near the 172px it has alone — and the route takes only the slack on the right, about 120px. An earlier pass split the row more evenly at 158/150; the dial read as demoted, and it was.

The route is drawn vertically, in Next's idiom: a hollow origin circle, a dashed run, a filled square destination, with the time and its label beside each mark. The traveller on that line is a **bead** — the same mark that rides the countdown ring — not a vehicle. A car emoji did two things wrong: it competed with the destination square for attention, and it was the one piece of clip art on a screen otherwise drawn by hand.

A no-travel stop collapses the route to a single square and one time, labelled `together`.

**The hero does not name you.** The dial is only ever the signed-in profile's next stop, so your own name on it confirms something the whole screen already guarantees — first the parenthetical "(you)" went, then the chip itself. Somebody *else* covering a stop in your scope is real news and still shows, as does an unassigned one. On the whole-family view every driver is named, because there the question is open.

**The leg carries a traveller only while there is one.** The bead appears once the departure has passed and disappears on arrival; before you leave, a mark on the road is a second dot sitting under the origin and reads as a mistake. The dashes are drawn as a repeating background rather than a dashed border, so their rhythm does not change with the leg's height and the last dash is never a stub.

### Marks

| Fact | Mark | Words on screen |
| --- | --- | --- |
| How urgent | Card background: forest, olive, or clay | The state word in the ring, at most |
| How much run-up is left | Depleting ring, piecewise (see below) | The count in minutes |
| Who is driving | Pale disc, dark initial; hatched ochre when unassigned | **The name** — "Dad", or "You" for the signed-in profile |
| Which children | A neutral child glyph on a butter tile, identical for every child | **The name**, which is the identity |
| A stop's status | A dot ahead of its title — forest and flashing for the live one, ochre when a driver is missing, sage once done | None |
| Where, and how far | Hollow origin dot, dashed line, filled square destination, bead by elapsed run-up | `leave`, `arrive`, and the ETA |
| How you get there | A line glyph — car, walker, two figures, bus, house | None |
| When a stop starts | The rail's time column | The clock time |
| When to leave for it | — (it is derived, not scheduled) | `Leave 2:51 PM` inside the row |
| Day completion | Pips in the panel head | None |
| How heavy a day is | The dot under each day, deeper and larger with load | None (the detail is in the label) |
| Driving split | One bar per caregiver at chart strength | The minutes |
| Position in the day | Spine behind the rail markers | None |

### The countdown

The centre of the dial is a count, never a clock face — a clock time makes the reader do the subtraction themselves. The unit follows what the reader actually thinks in:

- **60 minutes or fewer:** the minute count, with `min` on the unit line. Three-digit counts step down from 56px to 46px.
- **More than 60 minutes:** hours and minutes — `3h 21m`, or `2h` on the hour. The units ride small and light, in the same treatment Next gives the AM/PM suffix on its trip card. The unit line drops `min` and reads just `to leave`.

The dial always counts today, so there is no future-day fallback to name a departure time.

The ring is the same count drawn as an arc, and it is **piecewise** — one linear window cannot serve both "four hours out" and "eleven minutes out". Stretched wide, the final hour becomes an invisible sliver; kept narrow, the ring sits pinned full all morning, which is the failure this replaced.

- The **final 60 minutes own 60% of the circle** — the range where the decision actually lives gets most of the resolution.
- **Everything earlier shares the remaining 40%**, measured across the gap you really have: from the end of your previous stop, or from 6:00 AM when there is no earlier stop.

So 411 minutes out reads 90%, 56 minutes reads 56%, 11 minutes reads 11%, and the arc is always moving. It reads full in only two situations: you have swapped the dial forward to a stop whose gap has not begun yet, or the departure has passed and there is nothing left to count.

**The dial is drawn as an instrument, not a progress bar.** Three pieces of craft carry that, and they are the licence this screen has for a bit of delight — it is the thing a parent looks at most, and a flat arc on a flat card had none:

- **A gradient along the sweep.** Each tone is a pair, deep to bright, and the gradient axis is recomputed every render to point at the leading edge — so the arc always gains light toward the end that is moving. A gradient fixed in space would brighten the wrong side half the time.
- **A bead on the leading edge.** A glowing disc with a white centre, sitting exactly where the arc ends, breathing on a three-second cycle and easing to its new position as the count falls. It is the one element here that is plainly *moving*, which is what makes a countdown read as a countdown rather than as a filled shape. It is hidden at the two moments it would have nothing to point at: an empty arc, and a full one.
- **Twelve hour ticks** inside the track, every third one heavier. They give the ring the character of a dial and let you read roughly how much is left without reading the number at all.

A wash of the active tone sits behind the numeral so the middle is not a flat hole. Under `prefers-reduced-motion` the breathing, the alarm pulse and the bead's easing all stop; the ring still depletes.

Tones are pairs — the first value is the deep end of the gradient, the second the bright end and the bead.

| Situation | Card tone | Ring | Centre |
| --- | --- | --- | --- |
| More than 60 minutes before departure | Forest | Depleting, `#7cae5f` → `#caeaa4` | `3h 21m`, then `to leave` |
| 16–60 minutes | Forest | Depleting, `#7cae5f` → `#caeaa4` | Minutes, then `min · to leave` |
| 15 minutes or fewer | Olive | Depleting, `#cfa250` → `#f7dc9a` | Minutes, then `min · to leave` |
| Departure reached | Clay | Full, `#e39d33` → **highlight `#ffd36b`**, pulsing | `NOW`, then `leave` |
| Scheduled start reached | Clay | Full, `#e39d33` → **highlight `#ffd36b`**, pulsing | `LATE`, then `*n* min ago` (or `1h 5m ago`) |
| Driver unassigned | Tone as above; hatched driver mark | As above | As above; the only action is "Assign a driver" |
| At-home or no-travel stop | Counts down to the start, not a departure | As above | The count, then `be there`; the route bar collapses to a home mark and the only action is "✓ Done" |
| A completed stop, reached by swapping | Forest | Full | A drawn check, then `done`; the action is "Reopen" |
| Nothing left today, all confirmed | Forest | Full | A drawn check · "All clear" |
| Nothing left today, unconfirmed stops | Forest | Full | A drawn crescent · "Day is over" · "*n* never checked off" |

The dial's two resting states are line glyphs in the tone's bright colour, 44px, at the same stroke as the weather and transit icons. They were emoji until review: an emoji arrives in another designer's colour and gloss, and it broke the one surface that should feel most considered. There is no glow behind the numeral either — a soft radial wash sat there briefly and read as dated.

The highlight is the one colour on this screen that means *act, not wait*, and it appears nowhere else. Stops more than 20 minutes past their start roll off the dial and stay flagged on the rail, so a phone opened at 11 PM shows "Day is over" rather than a four-hundred-minute alarm.

## Settings

Reached from the topbar, where the notifications bell used to sit, and it replaced it rather than joining it — the bell reported conflicts the Go screen already shows on the rail, so it was a second, weaker answer to a question already answered.

It is a screen, not a tab. You go there occasionally and come straight back, so it carries a back arrow and takes no room in the bottom nav.

People are split from the address, and caregivers from children: the two rosters are edited for different reasons — one is who can drive, the other is who is being driven — and a single section holding both lists was the only one that needed scrolling once open. **Settings is the native home for all three** — nothing links out to another screen to do it.

**Eight sections, collapsed on arrival.** Settings opens as eight titles and nothing else — they fit on a phone with no scrolling at all, so the first thing you see is the whole map of what is here rather than the top of one section. Six sections' worth of controls at once is a wall to scroll past to reach the one you came for.

One opens at a time, the same swap the scope row uses on Go: the page never grows past a screenful, and the other seven titles stay in reach. Opening a section scrolls it to the top so its first control is under your thumb. Leaving Settings and coming back collapses everything again — the list of titles is the resting state, not a position you have to restore.

| Section | Holds |
| --- | --- |
| Home | The home address, typed here. Travel is estimated from it. |
| Caregivers | Each caregiver's name and relationship, edited in place. |
| Children | Each child's name and relationship, edited in place. |
| Connections | Google and Apple calendars. |
| Alerts & device | Leave-by, driver-needed and crew alerts; time zone. |
| Travel & timing | The arrival buffer, traffic-aware estimates, dinner protection. |
| Account | Who is signed in, sign out, delete. |
| Your data | Copy the day's brief, reset the sample schedule. |

**Every control is wired to real state**, and where the lab cannot honour one, the section says so at the top instead of offering a toggle that does nothing — calendar connection changes nothing real, and only the leave-by alert can actually be delivered. That is the "escalate, never silently approximate" rule from [SYSTEM.md](./SYSTEM.md) applied to a settings screen.

Destructive actions stay reachable without being inviting: underlined clay text, no fill, and a confirm that names exactly what goes. "Delete account" is honest that there is no server account yet — it clears this browser and nothing else.

Icons are Lucide, like the rest of the shell, rendered from `data-lucide` and initialised after each render.

**The family is state, not a constant.** `state.people` holds `{name, relationship, kind, color}`; the caregiver and child lists, the profile cycle, the driver table and the colour palette all read from it, so adding a person makes them assignable everywhere at once. Events store people by **name**, so a rename is a schedule edit as much as a roster one — `goRenamePerson()` sweeps `owner`, `lead`, `kid`, `kids`, the origin table and the active profile. Duplicate names are refused rather than silently merged, and removing someone tells you how many stops they are on before it unassigns them.

### Not yet built

Recorded here so the next pass does not re-derive them.

- **Arrival auto-completes a stop.** When the device reaches the destination inside the activity's window, mark it done rather than waiting for a tap. Completion is the one action a parent is least likely to perform — they are already at the field, with a child. Needs a geofence or significant-location port and an explicit, revocable permission; the manual tap stays as the fallback, since a stop can be handed off without the phone arriving.

### Weather

One icon, top right of the masthead, for today. It is the only ambient fact on this screen: it changes nothing about the plan, but it changes what you put on the kid before you leave. It sits where Next's decorative sun sat and keeps that drawing style — 38px, ochre `#ad722d`, 1.5px line, rotated -12 degrees — so the masthead reads the same whether the sky is clear or not.

Five sky tokens are drawn: `sun`, `partly`, `cloud`, `rain`, `storm`. The forecast description and temperature live in `title` and `aria-label`; only the icon is on the canvas. There is no temperature text, no second row, no forecast strip — a weather module would compete with the dial, and the dial is the reason the screen exists.

`goWeather(dayIdx)` is a stub over sample data. Production reads a **WeatherProvider** port keyed by date and the family's home coordinates (WeatherKit on iOS), cached with a TTL like `TravelEstimator` — see [SYSTEM.md](./SYSTEM.md). Keep the return shape: one `sky` token that maps to an icon, one human `label` for the tooltip, so the view never has to know about a forecast payload.

### The week strip

Seven soft cards — off-white `#fbfaf3` over a hairline `#e8e9dd`, with the selected day filled forest. Uppercase day label, tabular numeral, and a dot beneath.

**The dot is a load gauge, not a yes/no.** A binary "has something on it" answers the wrong question, because by Wednesday every day has something on it. What a caregiver scans for is *which day is heavy*, so the dot carries weight through four steps of depth and size — and it does so **for whoever the list is scoped to**, so switching from Mom to Nani repaints the whole week.

Weight blends two things, because neither alone would say it: the number of stops, and the minutes behind the wheel. Four short hops and one long haul are both a heavy day. Twenty minutes of driving weighs about the same as one more stop.

The scale is **relative to the busiest day of that person's own week**, not to a fixed number of stops. "Busy" only means anything comparatively: four stops is a heavy Tuesday for Nani and an ordinary one for the whole family, and one absolute scale saturates the family view to solid dots that say nothing. The peak is floored, so a week holding a single stop does not paint that day as the heaviest thing imaginable.

| Level | Unselected | On the selected forest pill |
| --- | --- | --- |
| 0 — nothing on | Transparent, space kept | Transparent |
| 1 | `#d3dac6`, 5px | `#ffffff4d` |
| 2 | `#b0bf9a`, 6px | `#ffffff85` |
| 3 | `#7f9a68`, 7px | `#dbe8b0` |
| 4 — the week's peak | Forest, 8px | `#e7df93` |

The precise figures live in the label — "Thursday, August 6 — 3 stops, 47 min driving for Dad" — so the mark is a glance and the detail is one press away. The new-stop sheet uses the same button, so you can see which day is already heavy before you schedule another stop into it.

### Rail and wheel time

A rail row is time, marker, title, and lead, with a meta line of mode icon and venue, and a departure line beneath it.

**The title carries a status dot.** Forest and gently flashing for the stop the dial is counting to, ochre when a driver is missing or a stop has gone stale, sage once it is done. It is the cheapest way to answer *which one is happening now* while scanning, and it costs one 7px mark. The title itself is 13.5px at weight 800 — the rail is a list of names, and the names should be the loudest thing in it.

**Children are named, not badged.** They read as `North Athletic Field (Maya)` in the muted line under the title, rather than as a row of pictograms competing with it.

**An unassigned stop tints.** A warm `#fcf6ec` panel behind the row, an `Unassigned` pill beside the title in warning clay, an ochre dot and marker, and a hatched disc where the caregiver would be. Nothing is written under that disc — the pill has already said it, and the word truncated in a 46px column.

**The time column is the arrival — when the thing actually starts.** That is the schedule, and the schedule is what a column of times down the left edge is for. The departure is *derived* from it (arrival minus travel minus buffer), so it belongs with the other derived detail inside the row: a `Leave 2:51 PM` line in forest under the venue. Two times of different kinds must never share one column; the row would stop being scannable and the reader would have to remember which one they were looking at.

The lead is a pale disc with the name beneath it — "You" for the signed-in profile, nothing at all when unassigned. The title owns the whole flexible column and never truncates; only the venue may ellipsize. Tapping the marker completes the stop; tapping the row opens its details. Completed rows drop to 57% opacity with a struck-through title and a filled forest marker. The row matching the dial's current stop keeps the thick forest marker, so you can see where the hero sits in the day. Stops hidden by the active scope are never silently dropped — a single underlined action restores the whole day.

The rail ends with **Add a stop**, so creation sits beside the day it affects rather than on a floating button. It is a filled panel in the suggestion idiom Next uses — `#eeecd6` inside a `#dddcbc` hairline, with the plus in a pale disc — because the dashed outline it replaced was invisible against ivory. A create action should look like an invitation, not like a placeholder.

Wheel time is whole-family by design: it is a load-balance read, not a filter. One row per caregiver who drove, sorted longest first, each a named disc and a chart-strength bar scaled against the busiest caregiver.

### New stop, and editing one

**One sheet does both.** Adding a stop and opening an existing one land in the same surface, seeded differently: the title reads "New stop" or "Edit stop", the primary action reads "Add stop" or "Save changes", and editing adds a quiet "Remove this stop". Two different forms for *describe an event* would be two things to learn and two things to keep in step; Go has one. In the rail, on the hero's destination block, and from the add action, the same sheet opens.

Creation reuses the screen's own parts rather than inventing a form. The preview is a small tone card, the field rows are the scope row turned vertical, and the pickers are the same chips, day buttons and caregiver discs used elsewhere. Nothing here is a new visual language, which is why it needs no explaining.

**The target is two taps.** Nothing is a blank field, because a blank field is work the app could have done:

| Field | Default |
| --- | --- |
| What | Pickup. The preset also supplies the venue, the travel mode and the duration. |
| Who | The child the list is filtered to, else the first child. |
| Where | The preset's usual venue — school for a drop-off, the sports complex for practice, home for dinner. |
| When | The day the list was showing, at the first half hour that is both ahead of you and not already spoken for. "After everything else on the day" would land every new stop at bedtime. The end follows from the preset's usual length. |
| Driver | You. |

The title composes itself: one child puts their name on it ("Noah Practice"), several leave it as the preset ("Playdate"). A written title always wins, and it survives switching presets — editing must never quietly rename somebody's event.

**Every value has an escape hatch, and they all look the same.** A tile or chip marked ✎ reveals exactly one input beneath its picker:

| Field | Preset path | ✎ Custom path |
| --- | --- | --- |
| What | Eight activity tiles | A free-text name, always available under the grid |
| Where | The saved places | "Somewhere else" → a text field |
| When | Whole hours, 7 AM to 9 PM, ± 15 stepper | "Exact" → a native time input |

Those inputs are the only things on this screen that open a keyboard. Everything else is a tap.

**A range, never a length.** The drawer shows a start and an end — `2:30 PM → 2:50 PM` — with the duration stated beneath as the one number derived *for* you. Asking for a length instead makes the parent do arithmetic to answer a question they already know the answer to ("it finishes at three"), and then makes them do it again to check.

Both ends stay on screen. Tapping one aims the stepper, the hour chips and the exact input at it — the scope row's swap again, so there is one control set rather than two stacked ones. Moving the start carries the end along, preserving the length you already chose, which is why most stops never need the end tapped at all. An end at or before its start is not a shorter stop, it is a mistake: those hours are disabled, and the stepper floors at start + 5 minutes.

**Presets are whole hours.** Seven AM to nine PM, and the ± stepper takes it from there in quarter hours. An arbitrary handful of oddly specific times — 3:15, 5:30 — reads as somebody else's schedule; a run of hours reads as a scale you find your place on. The labels drop the `:00`, because it is noise on a whole hour and fifteen chips need the width.

**No leave-by, on purpose.** The sheet shows when the stop *starts* and when it *ends*, and no departure at all. A departure is only meaningful once we know where the caregiver will be coming from, and at composition time we do not — the stop before it may not exist yet, and a custom place has no route at all. Inventing one here would put a number on screen that the rail would then quietly contradict. The rail is the only place a leave-by is honest, because by then there is a finished day to compute it from. An earlier pass explained the absence in a line of copy beneath the preview; it was answering a question nobody had asked, and it is gone.

**Structure.** Five rows, each showing its value as a mark and a word, with one picker open at a time in a drawer beneath the row that owns it — the scope row's swap, applied to composing an event. The preview above updates on every tap. Typing repaints the preview and the collapsed row value only, never the field holding the caret.

**Google Calendar.** A second outcome, not a second form: "Add to Google Calendar" saves the stop *and* marks it for the calendar, and the flag shows as a small 📅 on the row so the button has a visible consequence. Calendar is read-only in v1 (see [SYSTEM.md](./SYSTEM.md)), so the lab records the intent rather than pretending to have written — an outlined secondary under the primary, never a third equal action.

**Craft.** The sheet rises over a green scrim from Next's sheet vocabulary: warm white, 26px top corners, a grip, a circular close, a body that scrolls under a fixed foot. The primary action is forest-filled rather than butter — butter is for a dark card, and on ivory it loses its contrast. Removal is underlined clay text with no fill, because destructive actions should be reachable without being inviting. Escape and a backdrop tap close it; the first field takes focus on open.

| Component | Geometry |
| --- | --- |
| Sheet | 26px top corners; max height 92%; 20px side padding |
| Preview card | 20px radius; 15px padding; the screen's own facepile and route bar |
| Field row | `54px / flexible / 16px` columns; 56px minimum height |
| Preset / place tile | 14px radius; 72px minimum height; four columns for presets, three for places |
| Time range | Two halves plus an arrow; 58px minimum height; 17px numerals |
| Time stepper | `46px / flexible / 46px`; 46px targets; 21px clock |
| Primary action | Full width, forest-filled, 46px minimum height |
| Secondary action | Full width, outlined, 44px minimum height |
| Destructive action | Underlined clay text, 40px minimum height, no fill |

### Geometry

| Component | Geometry |
| --- | --- |
| Dial card | 26px radius; 18px padding; 172px ring wrap alone, 168px beside a route |
| Route column | `10px / flexible` rows; 44px leg; 14.5px times, 8.5px labels; 20px from the dial |
| Resting glyph | 44px line drawing in the tone's bright colour |
| Transit glyph | 15px in the hero, 13px in the rail; 1.6px stroke |
| Hour ticks | 12 lines between r74.5 and r79; 1.5px, every third 2px |
| Leading bead | r8.5 core, r3.2 white centre, r21 radial glow |
| Timing numeral | 56px, weight 650, tracking `-0.055em`; 30px when it is a word |
| Dial unit | 9px, weight 800, uppercase, tracking `0.2em` |
| Destination title | 21px, weight 650 |
| Named chip on the card | 26px disc in a translucent pill; 12.5px label |
| Mark (driver, child) | 26–30px circle on the card; 27px in the scope row; 40px in the crew picker; 35px in the rail with a 9.5px name below |
| Weather icon | 38px, ochre line, rotated -12 degrees |
| Hours numeral | 44px, with 24px weight-500 unit letters |
| Card actions | 12px radius; minimum height 46px; wide primary plus an icon-only secondary; **weight 650**, not bold — the hero already has one heavy element and it is the number |
| Hero dot | 22px target around a 5px dot; the active dot becomes a 17px bar |
| Scope row | 16px radius; 44px minimum segment height |
| Day button | 14px radius; 62px minimum height; hairline card, 5px grid gap |
| Day load dot | 5–8px, four steps of depth and size |
| Rail row | `52px / 22px / flexible / 46px` columns; 12px vertical padding; spine at 72px |
| Rail title | 13.5px, weight 800, with a 7px status dot |
| Add a stop | 15px radius; 52px minimum height; filled panel, 24px icon disc |
| Icon | 15px, 1.6px stroke, current colour — one set for the whole screen |
| Wheel-time row | `46px / flexible / 46px` columns; 10px track |

Below 370px the masthead drops to 24px, the ring to 156px, the numeral to 50px, the day cards to 58px, and the rail becomes `48px / 20px / flexible / 42px` with a 12.5px time and the spine at 64px. The sheet tightens to 15px gutters and its tiles to 66px.

## Responsive behavior

The desktop prototype centers a phone frame with a maximum width of 490px and 36px corners. At viewport widths of 520px or less, the frame fills the viewport and loses its decorative border, shadow, and rounded corners. The screen keeps one content column; the caregiver grid keeps two.

At 370px or less, Next reduces side gutters to 15px, the greeting to 28px, the hero heading to 29px, and the sun to 34px. Hero padding becomes 17px. Agenda columns become `44px / flexible / 34px` with 7px gaps. Route text and filter padding tighten as well. Child filters wrap instead of requiring horizontal scrolling.

Bottom navigation and sheet padding account for the bottom safe area. The outer desktop page retains the shared prototype's cool background; it is separate from the ivory in-app palette.

Both concepts take over the shared chrome while they are active — `next-mode` and `go-mode` on `.app` repaint the topbar, bottom navigation, and modals in ivory and forest. Neither leaves those overrides in place when another tab is selected.

## Copy and prototype boundaries

Write as a caregiver coordinating a day. Use familiar words such as "handoff", "take this one", "leave", "arrive", and "together". Give each warning a next step: confirm the handoff, compare caregivers, or edit the plan. Keep reassurance tied to an actual state or time estimate.

Next's preview clock defaults to 2:40 PM and offers 3:00 PM, 3:15 PM, and Live. It is local to that concept and is not persisted. Go reads the shared simulation clock in the Today scaffolding instead and has no clock control of its own. The date strips use sample August dates. Travel estimates, driver suggestions, and family data come from the prototype. Keep those facts explicit in design reviews; neither "Live" nor the route presentation establishes a live routing or calendar integration.

Go's "Live" control is unrelated to either clock. It means *follow the live stop* and only appears when the hero is pinned to a stop the parent chose.

When extending either concept, preserve the ivory canvas, the serif masthead, the dark tone card, the aligned rows, and the pale caregiver identities. Put additional information at the point where it helps a decision, and keep secondary operations in the details or comparison flows. Use the existing component dimensions and semantic colors before introducing new visual treatments.

Before adding a module, check whether it can swap into a slot that already exists. Before writing a sentence, check whether a mark would say it. Those two questions are the standing direction, and they are why Go carries the same reach as its predecessor on noticeably less screen.


## Plan: the weekly companion to Go

Plan uses Go's ivory canvas, forest card, serif date heading, pale named caregiver marks, chart-strength colors, and bottom-sheet interactions. Its primary job is action: assign the person responsible for repeated handoffs, resolve items that need a decision, and only then inspect the resulting week. Go remains the active viewer's daily execution screen.

The implementation is split into [plan.css](./plan.css), [plan.js](./plan.js), and [plan-core.js](./plan-core.js). Both HTML entry points load the same files. Open `index.html#plan`.

### Assignment desk first

The opening Plan view is an assignment desk, not a second event list. A decision queue calls out unassigned or tentative work, and routine cards group repeated drop-offs, pick-ups, and practices so one caregiver choice applies to every occurrence in the current week. A visible day strip supports choosing a day without making the full schedule the first thing on screen.

### One overview, one expandable schedule

The masthead shows the selected week with previous, date-picker, and next controls. The forest card shows seven columns of event marks. Green means ready, amber means review, and a hatched clay mark means unassigned. The ready fraction is computed from events, not a manually checked checklist. A ready event has an assignee, is not tentative, and has no detected scheduling or route risk. An empty week reads 0 / 0 with an invitation to plan, never 100% ready.

Tap a column to browse that day. Swipe the card to change weeks; the visible arrows do the same thing. Date arithmetic crosses month and year boundaries. The sample data is explicitly dated August 3–9, 2026; future weeks start empty unless events have been added to them.

The schedule is collapsed by default. Expanding a day reveals morning and afternoon sections using Go's timeline rows, including arrival time, leave-by, location, caregiver, kid tags, and status markers. The expanded view includes the same **Add an event** action and opens the same Go-style event sheet. Calendar review and family priorities stay secondary; caregiver filtering affects the schedule only and leaves Go's viewer and countdown unchanged.

### Review without hiding unfinished work

The review sheet groups missing caregivers, timing conflicts, unknown routes, long drives, and tentative assignments. An assignment sheet compares all four caregivers and checks the previous and next commitments. The user can save a tentative driver, keep an event unassigned, or lock an assignment against rebalancing.

Saving a weekly review records that the user has looked at the week. It does not clear flags or inflate readiness. Changing schedule, ownership, priorities, or buffer invalidates that review marker.

Rebalancing opens a proposed set of changes with names, dates, estimated travel, and a reason for each change. Applying is explicit. Locked, tentative, and completed events are excluded. The current suggestions use deterministic schedule rules and sample routes; no AI service is connected. Unknown routes stay unknown instead of receiving a fabricated ETA.

### Creation, repeated work, and priorities

The event sheet matches Go and supports a specific date, start and end, place, caregiver, task kind, children, notes, and a calendar queue flag. Repetition is prominent for recurring handoffs, with weekly occurrences bounded to 1–52. A routine assignment sheet can apply one caregiver to all occurrences in the current week; each occurrence still has its own identity and can be edited or removed independently. Private task fields stay separate from calendar schedule fields.

Family priorities live in a separate sheet: optional dinner days and a 45-minute window, one weekly priority, and meal ideas. Dinner protection detects conflicts; it does not move events or insert dinners into the calendar.

### Calendar review

Pull and push share a sheet with a visible two-way toggle. Incoming sample events arrive flagged as unassigned; updating a linked event preserves app-owned assignment, completion, and notes. Outgoing review contains schedule fields only. Changing a queued event's schedule puts it back in the outgoing queue.

The current adapter is a labeled local preview. Success says what happened in the preview and explicitly says that nothing was sent to Google. Live OAuth, calendar selection, conflict resolution against remote versions, and a backend write adapter remain integration work.

### Geometry and accessibility

Plan uses 18px content gutters, 26px hero and sheet corners, and 12–15px control radii. Its date heading is 29px Georgia; the hero heading is 24px sans-serif. Schedule rows use `49px / 15px / flexible / 49px` columns. Person names remain visible below their badges.

Sheets have a grip, a scrollable body, and a fixed action footer. The background becomes inert while a sheet is open. Tab stays inside the sheet, Escape moves back or closes, and closing restores focus. The focus ring is the shared 3px copper outline. Reduced-motion preferences disable the entrance animation. At 370px and below, gutters shrink to 14px and the date heading to 25px.

## Family refinement, September 7

Family uses Go's existing Newsreader headline font, ivory and warm-white surfaces, forest-green accents, caregiver colors, line icons, and rounded bottom sheets. The masthead has a settings button. The workload chart is read-only and yields its space when Locations or Templates is selected. Swap Next and rebalance actions are removed, including Plan's rebalance entry points.

Locations opens with a forest card summarizing home and caregiver starting bases. Settings is the only place to change those defaults. Regular places use compact rows with a name, address, icon, and edit button. There are no fixed drive-time badges or inputs. Address search shows labeled sample completions in the local prototype and supports arrow keys and Enter. Google Places can replace those completions when configured.

Templates use small cards with a serif title, time window, location, child tags, and Use in Plan action. The editor puts name, time, place, and multiple-child selection first; caregiver and activity type sit in a disclosure. Plan reduces each template to a title, start time, and child names. Full details open only when the user chooses a shortcut.

A separate AI preview area identifies repeated handoffs in the schedule, explains the number of matching items, and opens an editable template draft. Saving requires user action. Empty and already-saved states are explicit.
