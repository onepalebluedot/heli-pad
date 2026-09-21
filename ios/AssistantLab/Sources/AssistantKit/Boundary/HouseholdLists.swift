import Foundation

public enum AssistantListKind: String, Codable, CaseIterable, Sendable {
    case todos, groceries
    public var title: String { self == .todos ? "To-do" : "Grocery" }
}

public struct AssistantListItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var quantity: String
    public var section: String
    public var isCompleted: Bool
    public init(id: String, text: String, quantity: String = "", section: String = "General", isCompleted: Bool = false) {
        self.id = id; self.text = text; self.quantity = quantity
        self.section = section; self.isCompleted = isCompleted
    }
}

public struct AssistantHouseholdList: Codable, Hashable, Sendable {
    public var kind: AssistantListKind
    public var sections: [String]
    public var items: [AssistantListItem]
    /// Describes the freshness of this device's snapshot, not a promise that
    /// another phone has received it.
    public var syncLabel: String
    public init(kind: AssistantListKind, sections: [String], items: [AssistantListItem], syncLabel: String) {
        self.kind = kind; self.sections = sections; self.items = items; self.syncLabel = syncLabel
    }
}

/// App-minted identity survives confirmation retries. No date or child needed.
public struct ListItemAddition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: AssistantListKind
    public var section: String
    public var text: String
    public var quantity: String
    public init(id: String = UUID().uuidString, kind: AssistantListKind, section: String, text: String, quantity: String = "") {
        self.id = id; self.kind = kind; self.section = section; self.text = text; self.quantity = quantity
    }
    public var displayText: String { quantity.isEmpty ? text : "\(text) · \(quantity)" }
}
