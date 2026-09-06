# Notify path v1 — Edit / reassignment (Samira)

Quality bar: no silent rewrite. Change that affects another caregiver must answer “who got told” in one extra beat, not a modal essay.

## When notify fires
Notify step appears **only if** Done would change:
- who’s driving, or
- leave-by by ≥10 min (crew timing assumption breaks)

Pure −5/+5 leave tweak with same driver → Done closes, no notify beat.

## Sheet sequence (few taps)
1. **Edit handoff** — leave-by (stepper only; trip-local ±5 / ±15) + who’s driving (named caregivers, not “You”).
2. **Tap Done** → if notify triggers, sheet morphs in place (not a second modal):
   - Title: `Tell the crew`
   - One line: what changed (`Alex drives Maya · Soccer · leave 4:40`)
   - Default **on**: chips for who to ping — prior driver (if swapped), new driver, anyone on an overlapping trip
   - Optional off: `Don’t notify` (small, not primary)
3. **Send** (or **Done · silent** if they opted out) → sheet closes; hero / rest re-rank.

Tap count for happy path reassignment: Edit → pick driver → Done → Send = **4**. Silent opt-out adds one.

## Dual-kid conflict
If new driver already owns another trip within ±45 min (e.g. Alex on Leo clinic, now also Maya soccer):
- Show one amber line under the change summary: `Alex also has Leo · Dr. Patel · leave 4:55`
- Do **not** block. Offer chip `Ask Alex to confirm` (selected by default) vs notify-only.
- Cards stay separate — never merge into one drive.

## Who’s informed (defaults)
| Change | Default notify |
|--------|----------------|
| Driver A → B | A and B |
| Leave-by ±≥10, same driver | Other caregivers on that kid’s day (not whole family) |
| Driver change + overlap | Prior, new, + overlapping trip’s other caregivers |

Backup flip (you become backup): status craft is Elise’s; this path only guarantees the ping happened.

## Out of scope v1
- Full chat thread
- AI suggested reassignment
- Editing destination / kid

## Hand to
- @Nico Park — land in Edit sheet after cuts 2–5
- @Elise Brandt — backup / informed weight after this path is wired
- @Devon Okonkwo — lab can stub notify as toast + log; native later
