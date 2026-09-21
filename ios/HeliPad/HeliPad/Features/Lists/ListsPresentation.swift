import SwiftUI
import Combine

#if os(iOS)

/// Where the Lists tab is, and what the household left open in it.
///
/// This lives above `ContentView`'s destination switch on purpose. That switch
/// builds a fresh view on every tab change, so anything held inside a Lists
/// screen would be lost the moment someone looked at the calendar and came
/// back. Keyed by household and list id, and cleared when the household
/// changes, so one household's half-typed grocery item never appears in
/// another's.
@MainActor
public final class ListsPresentation: ObservableObject {

    public enum Screen: Equatable {
        case home
        case detail(listID: String)
    }

    @Published public var screen: Screen = .home
    @Published public var homeKind: ListKind = .todos
    @Published public private(set) var householdID: String = ""

    /// Capture-bar text, per list.
    @Published public var drafts: [String: String] = [:]
    /// The section new items are added to, per list. Defaults to General.
    @Published public var targetGroups: [String: String] = [:]
    @Published public var expandedGroups: Set<String> = []
    /// Lists whose Completed/Purchased section is open.
    @Published public var completedOpen: Set<String> = []
    /// Scroll anchor per list, so returning lands where it was left.
    @Published public var scrollAnchors: [String: String] = [:]

    public init() {}

    /// Points presentation state at a household. Anything from another
    /// household is dropped rather than shown.
    public func bind(householdID: String) {
        guard self.householdID != householdID else { return }
        reset()
        self.householdID = householdID
    }

    public func reset() {
        screen = .home
        homeKind = .todos
        drafts = [:]
        targetGroups = [:]
        expandedGroups = []
        completedOpen = []
        scrollAnchors = [:]
    }

    // MARK: - Drafts

    public func draft(_ listID: String) -> String { drafts[listID] ?? "" }

    public func setDraft(_ listID: String, _ text: String) { drafts[listID] = text }

    public func clearDraft(_ listID: String) { drafts.removeValue(forKey: listID) }

    // MARK: - Sections

    public func isExpanded(_ groupID: String) -> Bool { expandedGroups.contains(groupID) }

    public func setExpanded(_ groupID: String, _ expanded: Bool) {
        if expanded { expandedGroups.insert(groupID) } else { expandedGroups.remove(groupID) }
    }

    public func showsCompleted(_ listID: String) -> Bool { completedOpen.contains(listID) }

    public func setShowsCompleted(_ listID: String, _ open: Bool) {
        if open { completedOpen.insert(listID) } else { completedOpen.remove(listID) }
    }

    /// Where a new item in this list goes. Falls back to the list's first
    /// section, which is General.
    public func targetGroup(_ listID: String, in groups: [HouseholdListGroup]) -> String? {
        if let chosen = targetGroups[listID], groups.contains(where: { $0.id == chosen }) { return chosen }
        return groups.first?.id
    }

    public func setTargetGroup(_ listID: String, _ groupID: String) { targetGroups[listID] = groupID }

    // MARK: - Scroll

    /// Native scroll anchoring, so a list reopens where it was left.
    public func scrollAnchor(_ listID: String) -> Binding<String?> {
        Binding(
            get: { [weak self] in self?.scrollAnchors[listID] },
            set: { [weak self] value in
                guard let self else { return }
                if let value { self.scrollAnchors[listID] = value } else { self.scrollAnchors.removeValue(forKey: listID) }
            }
        )
    }
}

#endif
