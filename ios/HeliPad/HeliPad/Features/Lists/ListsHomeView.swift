#if os(iOS)
import SwiftUI

// MARK: - Root

/// The Lists tab. Two lists, nothing to navigate between them beyond the two
/// cards themselves.
public struct ListsView: View {
    @ObservedObject private var appStore: AppStore
    @ObservedObject private var presentation: ListsPresentation

    public init(appStore: AppStore, presentation: ListsPresentation) {
        self.appStore = appStore
        self.presentation = presentation
    }

    public var body: some View {
        let lists = appStore.lists
        Group {
            switch presentation.screen {
            case .home:
                ListsHomeView(appStore: appStore, presentation: presentation, lists: lists)
            case .detail(let listID):
                ListDetailView(appStore: appStore, presentation: presentation, listID: listID)
            }
        }
        .background(HeliColors.canvasIvory)
    }
}

// MARK: - Card

/// One list, as a card: the supplied artwork above the list's name, what is left
/// in it, and the action that opens it.
///
/// The artwork is line art drawn with `currentColor`, so it takes the card's
/// white along with the text rather than sitting on the fill as a black plate.
struct ListsTile: View {
    private let kind: ListKind
    private let name: String
    private let remaining: Int
    private let action: () -> Void

    init(kind: ListKind, name: String, remaining: Int, action: @escaping () -> Void) {
        self.kind = kind
        self.name = name
        self.remaining = remaining
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Spacer(minLength: 4)

                Image(artwork)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 240)
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                VStack(spacing: 6) {
                    Text(name)
                        .font(.largeTitle)
                        .fontDesign(.serif)
                        .multilineTextAlignment(.center)
                    Text("\(remaining) \(kind.remainingTitle)")
                        .font(.body.weight(.medium))
                        .opacity(0.95)
                }

                Spacer(minLength: 16)

                openList

                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .foregroundStyle(.white)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(remaining) \(kind.remainingTitle)")
        .accessibilityHint("Opens the \(name) list")
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        kind == .todos ? HeliColors.tileForest : HeliColors.harvestGold
    }

    private var artwork: String {
        kind == .todos ? "ListsTodoArtwork" : "ListsGroceryArtwork"
    }

    private var openList: some View {
        HStack(spacing: 6) {
            Text("Open list")
                .font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
    }
}

// MARK: - Undo bar

/// The one-batch undo for the latest destructive action. It sits on the home
/// screen, where the household lands after clearing or removing something.
struct ListsUndoBar: View {
    private let label: String
    private let onUndo: () -> Void
    private let onDismiss: () -> Void

    init(label: String, onUndo: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.label = label
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(HeliColors.greenInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeliColors.forestGreen)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HeliColors.mutedGray)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss undo")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }
}

// MARK: - Home

private struct ListsHomeView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var presentation: ListsPresentation
    @ObservedObject var lists: HouseholdListsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            advisories
            pager
            undoBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, ContentView.bottomBarInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HeliColors.canvasIvory)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HELIPAD")
                .tracking(2)
                .font(.caption.weight(.bold))
                .foregroundStyle(HeliColors.forestGreen)
            Text("Lists")
                .font(.largeTitle)
                .fontDesign(.serif)
                .foregroundStyle(HeliColors.greenInk)
        }
    }

    // MARK: Advisories

    @ViewBuilder
    private var advisories: some View {
        if lists.recoveryNeeded {
            recoveryCard
        }
        if let saveError = lists.saveError {
            saveErrorLine(saveError)
        }
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("An older lists file could not be read")
                .font(.headline)
                .foregroundStyle(HeliColors.greenInk)
            Text("These lists are starting fresh. The unreadable file was left alone, and you decide what happens to it.")
                .font(.subheadline)
                .foregroundStyle(HeliColors.greenInk.opacity(0.8))

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    lists.resolveRecovery(keepingCopy: true)
                } label: {
                    Text("Keep the old copy for a later version")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HeliColors.forestGreen)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    lists.resolveRecovery(keepingCopy: false)
                } label: {
                    Text("Discard the unreadable file")
                        .font(.subheadline)
                        .foregroundStyle(HeliColors.mutedGray)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.butterYellow)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    private func saveErrorLine(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(HeliColors.forestGreen)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HeliColors.greenInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.butterYellow)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    // MARK: Cards

    /// One card at a time, swiped between, with the page control underneath.
    /// `homeKind` holds the choice, so going into a list — or off to another tab
    /// — and coming back lands on the same card.
    private var pager: some View {
        TabView(selection: $presentation.homeKind) {
            ForEach(ListKind.allCases, id: \.self) { kind in
                card(for: kind)
                    .tag(kind)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your lists")
    }

    @ViewBuilder
    private func card(for kind: ListKind) -> some View {
        if let list = lists.defaultList(kind) {
            ListsTile(
                kind: kind,
                name: list.name,
                remaining: lists.remainingCount(of: list.id),
                action: { presentation.screen = .detail(listID: list.id) }
            )
            // Clear of the page control, which sits over the bottom of the pager.
            .padding(.bottom, 38)
        }
    }

    // MARK: Undo

    @ViewBuilder
    private var undoBar: some View {
        if let undo = lists.pendingUndo {
            ListsUndoBar(
                label: undo.label,
                onUndo: { lists.undo() },
                onDismiss: { lists.dismissUndo() }
            )
        }
    }
}

#endif