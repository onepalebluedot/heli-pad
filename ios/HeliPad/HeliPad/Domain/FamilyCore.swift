import Foundation

public struct TemplateSuggestion: Identifiable {
    public var key: String
    public var count: Int
    public var draft: TemplateItem

    public var id: String { key }

    public init(key: String, count: Int, draft: TemplateItem) {
        self.key = key
        self.count = count
        self.draft = draft
    }
}

public enum FamilyCore {
    private static var _childNames: () -> [String] = { ["Soni", "Maya", "Noah"] }

    public static var KIDS: [String] {
        return _childNames()
    }

    public static func configure(children: @escaping () -> [String]) {
        _childNames = children
    }

    public static func minutes(_ t: String) -> Int? {
        let pattern = try! NSRegularExpression(pattern: "^\\d{2}:\\d{2}$")
        let range = NSRange(t.startIndex..<t.endIndex, in: t)
        guard pattern.firstMatch(in: t, range: range) != nil else { return nil }
        let h = Int(t.prefix(2)) ?? 0
        let m = Int(t.suffix(2)) ?? 0
        return h * 60 + m
    }

    public static func timeString(_ n: Int) -> String {
        let h = n / 60
        let m = n % 60
        return String(format: "%02d:%02d", h, m)
    }

    public static func resolveChildren(kids: [String]?, kid: String?) -> [String] {
        let list: [String]
        if let kids = kids, !kids.isEmpty {
            list = kids
        } else if let kid = kid, !kid.isEmpty {
            list = kid.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            list = ["All"]
        }

        if list.contains("All") {
            return KIDS
        }
        return KIDS.filter { list.contains($0) }
    }

    public static func normalize(_ t: TemplateItem) -> TemplateItem {
        let defaults = [
            "tpl_1": "07:35",
            "tpl_2": "17:15",
            "tpl_3": "15:20",
            "tpl_4": "16:00",
            "tpl_5": "13:40",
            "tpl_6": "18:30"
        ]
        let start = !t.time.isEmpty ? t.time : (defaults[t.id] ?? "16:00")
        let startM = minutes(start) ?? 960
        let endM = min(1439, startM + (t.duration > 0 ? t.duration : 60))
        let end = !t.endTime.isEmpty ? t.endTime : timeString(endM)

        let kids = resolveChildren(kids: t.kids, kid: t.kid)
        let owner = t.owner.isEmpty ? "TBD" : t.owner
        let mode = !t.mode.isEmpty ? t.mode : (t.location == "Home" ? "Home" : "Drive")
        let duration = (minutes(end) ?? 0) - (minutes(start) ?? 0)

        return TemplateItem(
            id: t.id,
            title: t.title,
            time: start,
            endTime: end,
            kids: kids,
            kid: kids.joined(separator: ", "),
            owner: owner,
            location: t.location,
            mode: mode,
            duration: duration,
            notes: t.notes,
            category: t.category
        )
    }

    public static func validate(_ t: TemplateItem) throws -> TemplateItem {
        guard !t.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "FamilyCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Give this template a name."])
        }
        guard !t.location.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "FamilyCore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose a saved location."])
        }
        guard !t.kids.isEmpty else {
            throw NSError(domain: "FamilyCore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Choose at least one child."])
        }

        guard let a = minutes(t.time), let b = minutes(t.endTime) else {
            throw NSError(domain: "FamilyCore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Choose an end time after the start time on the same day."])
        }
        let startMinPart = Int(t.time.suffix(2)) ?? 0
        let endMinPart = Int(t.endTime.suffix(2)) ?? 0
        if a < 0 || b >= 1440 || b <= a || startMinPart > 59 || endMinPart > 59 {
            throw NSError(domain: "FamilyCore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Choose an end time after the start time on the same day."])
        }

        let normalized = normalize(t)
        guard !normalized.kids.isEmpty else {
            throw NSError(domain: "FamilyCore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Choose at least one current child."])
        }
        return normalized
    }

    public static func signature(_ t: TemplateItem) -> String {
        let n = normalize(t)
        let array: [Any] = [
            n.title.trimmingCharacters(in: .whitespaces).lowercased(),
            n.location,
            n.time,
            n.endTime,
            n.kids.sorted(),
            n.mode
        ]
        let json = try? JSONSerialization.data(withJSONObject: array, options: [])
        return json.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func eventSignature(_ e: TaskRecord) -> String {
        let title = e.title.trimmingCharacters(in: .whitespaces).lowercased()
        let kids = resolveChildren(kids: e.kids, kid: e.kid).sorted()
        let array: [Any] = [
            title,
            e.location,
            e.time,
            e.endTime,
            kids,
            e.mode
        ]
        let json = try? JSONSerialization.data(withJSONObject: array, options: [])
        return json.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func suggestions(events: [TaskRecord], templates: [TemplateItem]) -> [TemplateSuggestion] {
        let saved = Set(templates.map { signature($0) })
        var groups: [String: [TaskRecord]] = [:]

        for event in events {
            if event.allDay || event.time.isEmpty || event.endTime.isEmpty { continue }
            let key = eventSignature(event)
            if saved.contains(key) { continue }
            groups[key, default: []].append(event)
        }

        let eligible = groups.filter { $0.value.count >= 2 }
        var result: [TemplateSuggestion] = []

        for (key, list) in eligible {
            let owners = Array(Set(list.map { $0.owner }))
            let chosenOwner = owners.count == 1 ? owners[0] : "TBD"
            let first = list[0]
            let item = TemplateItem(
                id: "",
                title: first.title,
                time: first.time,
                endTime: first.endTime,
                kids: first.kids,
                kid: first.kid ?? first.kids.joined(separator: ", "),
                owner: chosenOwner,
                location: first.location,
                mode: first.mode,
                duration: (minutes(first.endTime) ?? 60) - (minutes(first.time) ?? 0)
            )
            result.append(TemplateSuggestion(
                key: key,
                count: list.count,
                draft: normalize(item)
            ))
        }

        result.sort { a, b in
            if a.count != b.count {
                return a.count > b.count
            }
            return a.draft.title.localizedCompare(b.draft.title) == .orderedAscending
        }

        return Array(result.prefix(3))
    }

    public static func eventDraft(template: TemplateItem, date: String) -> TaskRecord {
        let t = normalize(template)
        return TaskRecord(
            id: UUID().uuidString,
            date: date,
            time: t.time,
            endTime: t.endTime,
            title: t.title,
            owner: t.owner,
            lead: t.owner,
            kids: t.kids,
            kid: t.kid,
            location: t.location,
            mode: t.mode,
            kind: t.mode == "Home" ? .lead : .drive,
            done: false,
            tentative: false,
            locked: false,
            gcal: false,
            notes: t.notes ?? "",
            allDay: false
        )
    }
}
