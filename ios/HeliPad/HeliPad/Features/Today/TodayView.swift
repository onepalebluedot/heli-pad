import SwiftUI

struct TodayView: View {
    @StateObject private var vm = TodayViewModel()
    @State private var heroDrag: CGFloat = 0

    var body: some View {
        ZStack {
            TodayTheme.page.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        dateLine
                        if let hero = vm.hero {
                            heroCard(hero)
                                .offset(x: heroDrag)
                                .gesture(heroSwipe)
                        }
                        restOfDay
                        // Week/filters only under scroll — never above leave-in dial.
                        weekStrip
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 88)
                }
                tabBar
            }

            if vm.showEdit {
                EditSheet(vm: vm)
            }

            if let toast = vm.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 96)
                        .onTapGesture { vm.toast = nil }
                        .gesture(DragGesture().onEnded { _ in vm.toast = nil })
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Heli-Pad").font(.headline)
            Spacer()
            Button(action: { vm.switchViewer() }) {
                HStack(spacing: 6) {
                    Text(String(vm.viewerName.prefix(1)))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(TodayTheme.green, in: Circle())
                    Text(vm.viewerName).font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!vm.isLabMode)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var dateLine: some View {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(TodayTheme.muted)
            .tracking(0.6)
    }

    private func heroCard(_ task: TaskItem) -> some View {
        let plan = vm.plan
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(task.kind == .dinner ? "Dinner" : "Hottest task")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .opacity(0.72)
                Spacer()
                Text(toneLabel(plan?.tone))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }

            leaveDial(plan)

            Text(task.title)
                .font(.title3.weight(.semibold))
            Text("\(vm.childNames(task.children)) · \(vm.personName(task.assigneeId)) takes it")
                .font(.subheadline)
                .opacity(0.85)

            if let plan {
                HStack(spacing: 8) {
                    Label(plan.departBy.formatted(date: .omitted, time: .shortened), systemImage: "arrow.right.circle")
                    Text("→")
                    Text(plan.arriveBy.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text("+\(task.bufferMinutes)m buffer")
                        .font(.caption)
                        .opacity(0.75)
                }
                .font(.caption.weight(.semibold))
            }

            HStack(spacing: 10) {
                Button("Directions") { /* MapsLauncher stub */ }
                    .buttonStyle(HeroPrimaryButton())
                Button("Edit") { vm.openEdit() }
                    .buttonStyle(HeroSecondaryButton())
                Menu {
                    Button("Complete") { vm.completeHero() }
                    Button("Snooze +10") { vm.snoozeHero(by: 10) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
            }
        }
        .padding(18)
        .foregroundStyle(TodayTheme.ivory)
        .background(
            LinearGradient(colors: [TodayTheme.greenMid, TodayTheme.green], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: TodayTheme.green.opacity(0.28), radius: 18, y: 10)
    }

    private func leaveDial(_ plan: TripPlan?) -> some View {
        let minutes = plan?.leaveInMinutes ?? 0
        let tone = plan?.tone ?? .later
        return HStack {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: dialProgress(tone))
                    .stroke(dialColor(tone), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(minutes)")
                        .font(.system(size: 44, weight: .semibold, design: .serif))
                    Text("MIN")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .opacity(0.75)
                }
            }
            .frame(width: 148, height: 148)
            Spacer()
        }
    }

    private var restOfDay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rest of day")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TodayTheme.ink)
            ForEach(vm.restGroups, id: \.0) { group, rows in
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupTitle(group))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(group == "dinner" ? TodayTheme.ochre : TodayTheme.muted)
                        .textCase(.uppercase)
                    ForEach(rows) { row in
                        restRow(row, group: group)
                    }
                }
            }
        }
    }

    private func restRow(_ task: TaskItem, group: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(task.start.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TodayTheme.muted)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline.weight(.semibold))
                Text("\(vm.childNames(task.children)) · \(vm.personName(task.assigneeId))")
                    .font(.caption)
                    .foregroundStyle(TodayTheme.muted)
            }
            Spacer()
            stampView(task, group: group)
        }
        .padding(12)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button("Complete") { vm.completeTask(id: task.id) }
            Button("Snooze +10") { vm.snoozeTask(id: task.id, by: 10) }
        }
    }

    /// Dinner uses plate mark — never a letter (“D” reads as Dad).
    @ViewBuilder
    private func stampView(_ task: TaskItem, group: String) -> some View {
        if group == "dinner" {
            Image(systemName: "fork.knife.circle.fill")
                .foregroundStyle(TodayTheme.ochre)
                .accessibilityLabel("Dinner")
        } else if let stamp = task.stamp {
            Text(stamp)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(TodayTheme.green, in: Circle())
        }
    }

    private var weekStrip: some View {
        // Below dial / under scroll only (SWIPE-TAP-MAP).
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let day = Calendar.current.date(byAdding: .day, value: i - Calendar.current.component(.weekday, from: .now) + 1, to: .now) ?? .now
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                    Text(day.formatted(.dateTime.day()))
                        .font(.body.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.white : TodayTheme.ink)
                .background(Calendar.current.isDateInToday(day) ? TodayTheme.green : Color.clear, in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private var tabBar: some View {
        HStack {
            ForEach(["Go", "Today", "Next", "Plan"], id: \.self) { tab in
                VStack(spacing: 4) {
                    Image(systemName: tabIcon(tab))
                    Text(tab).font(.caption2.weight(.semibold))
                }
                .foregroundStyle(tab == "Today" ? TodayTheme.green : TodayTheme.muted)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
    }

    private var heroSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { heroDrag = $0.translation.width }
            .onEnded { value in
                defer { withAnimation { heroDrag = 0 } }
                if value.translation.width > 80 {
                    vm.completeHero() // swipe right → complete
                } else if value.translation.width < -80 {
                    vm.snoozeHero(by: 10) // swipe left → snooze (+ Tell-the-crew if ≥10)
                }
            }
    }

    private func groupTitle(_ g: String) -> String {
        switch g {
        case "dinner": return "Dinner plan"
        case "home": return "Home"
        default: return "On the go"
        }
    }

    private func toneLabel(_ tone: UrgencyTone?) -> String {
        switch tone {
        case .later: return "Later"
        case .soon: return "Soon"
        case .now: return "Leave now"
        case .late: return "Late"
        default: return "On track"
        }
    }

    private func dialColor(_ tone: UrgencyTone) -> Color {
        switch tone {
        case .later, .ontrack: return TodayTheme.cream
        case .soon: return TodayTheme.ochre
        case .now, .late: return TodayTheme.terracotta
        default: return TodayTheme.cream
        }
    }

    private func dialProgress(_ tone: UrgencyTone) -> CGFloat {
        switch tone {
        case .later: return 0.35
        case .soon: return 0.62
        case .now, .late: return 1.0
        default: return 0.5
        }
    }

    private func tabIcon(_ tab: String) -> String {
        switch tab {
        case "Go": return "location.circle"
        case "Today": return "sun.max"
        case "Next": return "list.bullet"
        default: return "calendar"
        }
    }
}

struct HeroPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TodayTheme.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(TodayTheme.creamBtn, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct HeroSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TodayTheme.ivory)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
