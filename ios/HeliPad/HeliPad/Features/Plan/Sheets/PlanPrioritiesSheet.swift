import SwiftUI

public struct PlanPrioritiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var week: String

    @State private var dinnerProtected: Bool = true
    @State private var dinnerTime: String = "18:00"
    @State private var bufferMinutes: Int = 10
    @State private var peakTraffic: Bool = true
    @State private var notes: String = ""
    @State private var errorMessage: String? = nil

    public init(store: AppStore, week: String = PlanCore.currentMonday()) {
        self.store = store
        self.week = week
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("DINNER PROTECTION").font(HeliTypography.eyebrow(11))) {
                    Toggle("Protect Family Dinner", isOn: $dinnerProtected)
                        .tint(HeliColors.forestGreen)

                    if dinnerProtected {
                        HStack {
                            Text("Target Dinner Time")
                                .font(HeliTypography.body(14))
                                .foregroundColor(HeliColors.greenInk)
                            Spacer()
                            TextField("18:00", text: $dinnerTime)
                                .font(HeliTypography.monoTime(14))
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(HeliColors.greenInk)
                        }
                    }
                }

                Section(header: Text("TRAVEL & TIMING").font(HeliTypography.eyebrow(11))) {
                    Stepper("Buffer Between Stops: \(bufferMinutes)m", value: $bufferMinutes, in: 0...30, step: 5)
                        .font(HeliTypography.body(14))

                    Toggle("1.15x Peak Traffic Factor", isOn: $peakTraffic)
                        .tint(HeliColors.forestGreen)
                }

                Section(header: Text("WEEKLY FOCUS & NOTES").font(HeliTypography.eyebrow(11))) {
                    TextField("E.g., Grandma in town Wed; Mom leads Friday practices", text: $notes, axis: .vertical)
                        .font(HeliTypography.body(14))
                        .lineLimit(3...5)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HeliColors.canvasIvory)
            .navigationTitle("Planning Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(HeliColors.mutedGray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if saveSettings() { dismiss() }
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.forestGreen)
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
            .alert("Couldn’t Save Planning Rules", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please check the values and try again.")
            }
        }
    }

    private func loadCurrentSettings() {
        let rules = store.planningRules(for: week)
        bufferMinutes = store.buffer
        peakTraffic = store.trafficMode
        dinnerTime = rules.time
        dinnerProtected = rules.enabled
        notes = store.weeklyPlanningNotes(for: week)
    }

    private func saveSettings() -> Bool {
        do {
            try store.updatePlanningRules(
                for: week,
                dinnerProtected: dinnerProtected,
                dinnerTime: dinnerTime,
                bufferMinutes: bufferMinutes,
                peakTraffic: peakTraffic,
                notes: notes
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
