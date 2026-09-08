import SwiftUI

public struct PlanPrioritiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore

    @State private var dinnerProtected: Bool = true
    @State private var dinnerTime: String = "18:00"
    @State private var bufferMinutes: Int = 10
    @State private var peakTraffic: Bool = true
    @State private var notes: String = ""

    public init(store: AppStore) {
        self.store = store
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
                        saveSettings()
                        dismiss()
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.forestGreen)
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }

    private func loadCurrentSettings() {
        if let buf = store.settings["bufferMinutes"] as? Int {
            bufferMinutes = buf
        }
        if let peak = store.settings["peakTraffic"] as? Bool {
            peakTraffic = peak
        }
        if let dTime = store.settings["dinnerTime"] as? String {
            dinnerTime = dTime
        }
        if let dProt = store.settings["dinnerProtected"] as? Bool {
            dinnerProtected = dProt
        }
    }

    private func saveSettings() {
        var s = store.settings
        s["bufferMinutes"] = bufferMinutes
        s["peakTraffic"] = peakTraffic
        s["dinnerTime"] = dinnerTime
        s["dinnerProtected"] = dinnerProtected
        store.settings = s
    }
}
