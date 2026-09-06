import SwiftUI

struct EditSheet: View {
    @ObservedObject var vm: TodayViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if vm.showTellTheCrew {
                        vm.backFromTellTheCrewToEdit()
                    } else {
                        vm.showEdit = false
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity)

                if vm.showTellTheCrew {
                    tellTheCrew
                } else {
                    editContent
                }
            }
            .padding(20)
            .background(TodayTheme.page, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .gesture(
                DragGesture().onEnded { value in
                    if value.translation.height > 80 {
                        if vm.showTellTheCrew {
                            // Swipe-down = back to Edit only — never skip Send / silent discard.
                            vm.backFromTellTheCrewToEdit()
                        } else {
                            vm.showEdit = false
                        }
                    }
                }
            )
        }
    }

    private var editContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit").font(.title3.weight(.semibold))
            Text(vm.hero?.title ?? "").foregroundStyle(TodayTheme.muted)

            Text("Leave-by nudges (this trip)").font(.caption.weight(.semibold)).foregroundStyle(TodayTheme.muted)
            HStack {
                ForEach([-15, -5, 5, 15], id: \.self) { m in
                    Button(m > 0 ? "+\(m)" : "\(m)") { vm.applyLeaveNudge(m) }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(TodayTheme.greenSoftBg, in: Capsule())
                }
            }

            if let leave = vm.draftLeaveBy {
                Text("Leave by \(leave.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Who’s driving").font(.caption.weight(.semibold)).foregroundStyle(TodayTheme.muted)
            HStack {
                ForEach(["dad", "mom"], id: \.self) { id in
                    let selected = vm.draftAssigneeId == id
                    Button(vm.personName(id)) { vm.setDriver(id) }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(selected ? TodayTheme.green : Color.white, in: Capsule())
                        .foregroundStyle(selected ? TodayTheme.ivory : TodayTheme.ink)
                }
            }

            Button("Done") { vm.tapDone() }
                .buttonStyle(HeroPrimaryButton())
                .padding(.top, 8)
        }
    }

    private var tellTheCrew: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tell the crew").font(.title3.weight(.semibold))
            Text("Driver or leave-by changed by ≥10 min. Send updates the shared notify path (stub).")
                .font(.subheadline)
                .foregroundStyle(TodayTheme.muted)

            Button("Send") { vm.sendToCrew() }
                .buttonStyle(HeroPrimaryButton())
            // Don’t notify is tap-only — never swipe dismissal.
            Button("Don’t notify") { vm.dontNotify() }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            Button("Back to Edit") { vm.backFromTellTheCrewToEdit() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(TodayTheme.green)
        }
    }
}

private extension TodayTheme {
    static let greenSoftBg = Color(red: 0.906, green: 0.937, blue: 0.914)
}
