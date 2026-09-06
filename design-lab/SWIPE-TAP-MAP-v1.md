# Today — swipe vs tap map v1 (Samira + Nico)

Rule from John/Lena: **swipe accelerates, never hides.** Critical path stays visible as a tap. Lab may expose extra swipe for testing; native ports must not depend on undiscoverable gestures.

**Leaders contract amended 2026-09-05** (Lena → Marcus) per pressure-test — items below match that amend.

## Feature contracts (eng must support)
| Contract | Ship bar | Lab-only? |
|----------|----------|-----------|
| Hottest Task hero (any kind — not drive-only) | Shared ranking / leave clock | No |
| Tell-the-crew + role stamps | Shared backend change/notify | No |
| Sticky active caregiver + clean viewer switch | Sticky across cold start; tap pill primary | Swipe accelerate = lab OK |
| Forest/ivory + few-tap bar | Design system | No |
| Leave-now dial tones (later → late) | Urgency states | No |

## Action map

### Doorway / hero
| Action | Primary | Swipe (accelerate) | Notes |
|--------|---------|-------------------|--------|
| Open Directions | **Tap** primary CTA | — | Critical — never swipe-only |
| Open Edit | **Tap** secondary | — | Critical |
| Complete handoff / trip | **Tap overflow** on hero | **Swipe right** on hero → Complete | Peek “Complete”; undo toast 5s |
| Snooze leave-by (+10 / +15) | Tap in Edit (± chips) + overflow | **Swipe left** on hero → Snooze | Peek “+10 min”; **≥10 still runs Tell-the-crew** |
| Cycle to next agenda item | Tap rest-of-day row (read) | **Swipe up** on hero (or edge) → next Task | Dual-kid must not merge |

### Caregiver viewer
| Action | Primary | Swipe | Notes |
|--------|---------|-------|--------|
| Switch sticky caregiver | **Tap** topbar caregiver pill | Horizontal swipe accelerate | Sticky cold-start = eng; swipe ≠ only path |

### Week / filters
| Action | Primary | Swipe | Notes |
|--------|---------|-------|--------|
| Week / filters | Tap — **under scroll / below dial only** | Week cycle swipe OK once below dial | Never above leave-in |

### Edit / Tell-the-crew sheet
| Action | Primary | Swipe | Notes |
|--------|---------|-------|--------|
| Adjust leave-by | Tap stepper / ± chips | — | No swipe on time |
| Pick driver | Tap driver chip | — | |
| Done → Send | Tap Done, Tap Send | — | 4-tap happy path |
| Don’t notify | **Tap only** | — | Never swipe dismissal |
| Ask X to confirm (overlap) | **Tap only** | — | Never swipe |
| Back from Tell-the-crew → Edit | Escape | **Swipe down** = back to Edit only | Never skip Send / never silent discard mid-notify |
| Dismiss toast | — | Swipe away OK | Distinct from sheet |
| Discard Edit | Scrim / Close | Swipe down on Edit | Does not advance into notify |

### Rest-of-day / agenda
| Action | Primary | Swipe | Notes |
|--------|---------|-------|--------|
| Inspect trip | **Tap** row | — | Critical |
| Complete / snooze | Overflow / edit | **Swipe right / left** on row | Same peeks as hero; cards stay separate |

## Discoverability
- One calm coach mark on hero; peek labels during drag; ~40% threshold
- Reduce-motion / assistive: swipe actions remain as tappable overflow
