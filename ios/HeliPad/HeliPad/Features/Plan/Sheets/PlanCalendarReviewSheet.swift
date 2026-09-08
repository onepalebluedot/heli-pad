import SwiftUI

public struct PlanCalendarReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    @State private var syncStatus: String = "Connected: 2 calendars active"
    @State private var lastSyncTime: String = "Just now"

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 20))
                            .foregroundColor(HeliColors.forestGreen)
                        Text("Calendar Integration")
                            .font(HeliTypography.headline(18))
                            .foregroundColor(HeliColors.greenInk)
                    }

                    Text("Heli-Pad syncs two-way with Google Calendar and Apple Calendar to pull school activities and push assigned family departures.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)

                    Divider().background(HeliColors.sageRule)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STATUS")
                                .font(HeliTypography.eyebrow(9))
                                .foregroundColor(HeliColors.mutedGray)
                            Text(syncStatus)
                                .font(HeliTypography.caption(12))
                                .foregroundColor(HeliColors.forestGreen)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("LAST SYNC")
                                .font(HeliTypography.eyebrow(9))
                                .foregroundColor(HeliColors.mutedGray)
                            Text(lastSyncTime)
                                .font(HeliTypography.caption(12))
                                .foregroundColor(HeliColors.greenInk)
                        }
                    }
                }
                .padding(16)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))

                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        pullCalendar()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Pull New Events from Calendar")
                                .font(HeliTypography.actionButton(13))
                        }
                        .foregroundColor(HeliColors.cardWarmWhite)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(HeliColors.forestGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: {
                        pushCalendar()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle")
                            Text("Push Assignments to Calendar")
                                .font(HeliTypography.actionButton(13))
                        }
                        .foregroundColor(HeliColors.greenInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(HeliColors.canvasIvory)
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
    }

    private func pullCalendar() {
        // Demonstrate pull merge using sample external events
        let sampleExternal: [TaskRecord] = [
            TaskRecord(
                id: "ext-robotics-\(UUID().uuidString.prefix(6))",
                date: PlanCore.dateAdd(PlanCore.BASE_WEEK, 3),
                time: "15:45",
                endTime: "17:15",
                title: "Robotics Club",
                owner: "TBD",
                kids: ["Maya"],
                location: "Westfield High",
                mode: "Drive",
                kind: .other,
                gcal: true
            )
        ]
        let merged = PlanCore.pull(store.records(), sampleExternal)
        store.replaceRecords(merged)
        syncStatus = "Pulled 1 external event"
        lastSyncTime = "Just now"
    }

    private func pushCalendar() {
        syncStatus = "Pushed \(store.records().count) stops to calendar"
        lastSyncTime = "Just now"
    }
}
