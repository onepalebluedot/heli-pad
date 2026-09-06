# Today v1.4 — content pass (Nico)

## Why
John compared lab Today to heli-pad.vercel.app: ours read kit/outdated and thin on content.

## File
`today-v14-content.html` — new. Does not overwrite v1.2 / v1.3.

## Content added vs v1.3
- Caregiver switcher (Dad), brand, alerts
- Editorial headline + week strip
- Hero: leave-in countdown, buffer spare copy, kid + who takes it / backup, leave-by → arrive-by spine, View trip + Edit
- Rest of day + remaining count; denser rows (time, who, what, where)
- Product bottom nav (Go/Today/Next/Plan/Map/Family)
- Edit sheet: leave-by + who’s driving; re-picks hottest-clock hero; later = leave-by ascending
- Dual-kid: Maya pickup / Maya soccer / Leo clinic stay separate

## Still needs
- Elise: craft polish (type scale, concentric field texture, icon system — not emoji nav)
- Lena: green as product-home direction
- Avery: watch only until click feels honest on device

## Lena green (2026-09-05)
Hero must answer: leave-in/leave-by, buffer+drive, spine, caregiver+child, primary Directions/Open + secondary Edit.
Constraints: Go one-question, forest/ivory v1.3 craft, hottest Task not drive-only. No indigo, no filter double-row, no siren stack.
Samira: few-tap pressure-test. Elise: craft after content true. Avery held until John likes both.

## Lena cuts applied (pre-Elise)
1. Dropped week strip + “Your day, together.” — doorway first (date line only).
2. Caregiver pill only (removed Switch caregiver duplicate).
3. Nav = 4 tabs (Go/Today/Next/Plan), SVG line icons — no emoji Map/Family.
4. Sheet drivers = You / Mom / Dad (family names, not Alex/Jordan).

## Samira change-UX cuts (pre-Elise)
1. Notify-on-reassign checkbox (default on) + toast when driver changes.
2. Trip-local leave nudges: −15 / −5 / +5 / +15 from this trip’s leave-by (not global clock chips).
3. Rest-of-day row opens read sheet; Edit only from hero Edit or read→Edit.
4. Spine drops “Drive · N min + buffer” duplicate (buffer stays in hero support line).

## Notify path (Samira) landed
Wired into `today-v14.html` Edit sheet:
- Done one beat if no crew impact (−5/+5 same driver)
- Driver swap or leave-by ≥10 → morph to **Tell the crew** (Send / Don’t notify)
- Dual-kid overlap ±45 min → amber warn + Ask to confirm; cards stay separate
- Drivers = Dad/Mom (named). Lab stub: toast + `console.log([heli-notify])`


## Tell-the-crew on content file
Landed Samira notify morph into `today-v14-content.html` (synced from canonical `today-v14.html`: craft + Done→Tell the crew→Send, dual-kid overlap warn).
