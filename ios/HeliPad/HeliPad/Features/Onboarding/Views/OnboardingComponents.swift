import SwiftUI

// MARK: - Shared setup chrome
//
// Small pieces the setup steps share, so each step reads as a list of
// questions rather than a pile of layout.

struct OnboardingEyebrow: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(HeliTypography.eyebrow(10.5))
            .tracking(1.8)
            .foregroundColor(HeliColors.forestGreen.opacity(0.75))
    }
}

struct OnboardingHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingEyebrow(text: eyebrow)
            Text(title)
                .font(HeliTypography.serifTitle(28))
                .foregroundColor(HeliColors.greenInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(HeliTypography.body(13.5))
                .foregroundColor(HeliColors.mutedGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingProgressRule: View {
    var step: Int
    var total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? HeliColors.forestGreen : HeliColors.sageRule)
                    .frame(height: 3)
            }
        }
    }
}

struct OnboardingField: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var autocapitalization: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(HeliTypography.railTitle(11.5))
                .foregroundColor(HeliColors.mutedGray)
            TextField(placeholder, text: $text)
                .font(HeliTypography.body(15))
                .foregroundColor(HeliColors.greenInk)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 0.9)
                )
        }
    }
}

struct OnboardingChip: View {
    var label: String
    var isSelected: Bool
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    HeliIcon(icon, size: 12)
                }
                Text(label)
                    .font(HeliTypography.actionButton(12.5))
            }
            .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.mutedGray)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(isSelected ? HeliColors.forestTint : HeliColors.cardWarmWhite)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? HeliColors.forestGreen : HeliColors.sageRule,
                    lineWidth: isSelected ? 1.3 : 0.9
                )
            )
        }
        .buttonStyle(.plain)
    }
}

/// A wrapping row of chips. `FlowLayout` is overkill here — setup never shows
/// more than a dozen — so this chunks into rows of a fixed width instead.
struct OnboardingChipWrap<Item: Hashable>: View {
    var items: [Item]
    var perRow: Int = 3
    var content: (Item) -> OnboardingChip

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: perRow).map { start in
            Array(items[start..<min(start + perRow, items.count)])
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct OnboardingCardRow<Content: View>: View {
    var onDelete: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    HeliIcon("trash", size: 14)
                        .foregroundColor(HeliColors.warningClay)
                        .frame(width: 30, height: 30)
                        .background(HeliColors.clayWash)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.9)
        )
    }
}

struct OnboardingAddButton: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                HeliIcon("plus", size: 13)
                Text(label)
                    .font(HeliTypography.actionButton(13.5))
            }
            .foregroundColor(HeliColors.forestGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(HeliColors.forestTint.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(HeliColors.forestGreen.opacity(0.45))
            )
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingWeekdayPicker: View {
    @Binding var weekdays: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Days")
                .font(HeliTypography.railTitle(11.5))
                .foregroundColor(HeliColors.mutedGray)
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { day in
                    let isOn = weekdays.contains(day)
                    Button(action: { toggle(day) }) {
                        Text(OnboardingDraft.weekdayNames[day].prefix(1))
                            .font(HeliTypography.actionButton(12))
                            .foregroundColor(isOn ? HeliColors.cardWarmWhite : HeliColors.mutedGray)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(isOn ? HeliColors.forestGreen : HeliColors.canvasIvory)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(HeliColors.sageRule, lineWidth: isOn ? 0 : 0.9)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ day: Int) {
        if let index = weekdays.firstIndex(of: day) {
            weekdays.remove(at: index)
        } else {
            weekdays.append(day)
            weekdays.sort()
        }
    }
}

struct OnboardingTimeField: View {
    var label: String
    @Binding var time: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(HeliTypography.railTitle(11.5))
                .foregroundColor(HeliColors.mutedGray)
            DatePicker(
                "",
                selection: Binding(
                    get: { OnboardingTime.date(from: time) },
                    set: { time = OnboardingTime.string(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
    }
}

enum OnboardingTime {
    static func date(from hhmm: String) -> Date {
        let minutes = PlanCore.mins(hhmm)
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    static func string(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
