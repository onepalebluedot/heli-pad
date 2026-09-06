# HeliPad iOS (Today scaffold)

SwiftUI port of the forest-green **Today** playground from `design-lab/today-v14.html`.

## Open in Xcode
1. Open `ios/HeliPad/HeliPad.xcodeproj`
2. Select an iPhone simulator
3. Run (⌘R)

## Contracts honored
- `SYSTEM.md` — Task model, active viewer, TripPlan only when travel needed
- `design-lab/SWIPE-TAP-MAP-v1.md` — swipe accelerates, tap primary for critical actions
- Lab proof: `design-lab/today-v14.html` (incl. dinner plate mark)

## Stubs / gaps
- Notify → `Notifier` protocol (toast stub); no fake multi-device sync
- Calendar / travel ports stubbed with sample day data
- Cook/lead/placeholder kinds exist in domain; Today chrome still drive/dinner/home shaped per lab
- Lab sim clock not wired into production paths
