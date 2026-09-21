import Foundation

/// One entry in the visible conversation.
public struct ChatMessage: Hashable, Sendable, Identifiable, Codable {
    public enum Author: String, Hashable, Sendable, Codable {
        case user
        case assistant
    }

    public var id: String
    public var author: Author
    public var date: Date
    /// User messages only. Assistant turns carry no prose \u{2014} they are cards.
    public var text: String?
    public var cards: [AssistantCard]

    public init(id: String = UUID().uuidString, author: Author, date: Date, text: String? = nil, cards: [AssistantCard] = []) {
        self.id = id
        self.author = author
        self.date = date
        self.text = text
        self.cards = cards
    }
}

/// Device-local chat history, partitioned by authenticated user and household
/// (A06), and persisted so a conversation survives quitting the app.
///
/// The partition key is what stops a household switch from showing the
/// previous family's conversation: history is looked up by key, and a key that
/// is not the current session's is never read.
///
/// On disk this is one JSON file per key under `storageDirectory`, written
/// with complete file protection - it contains the household's schedule, so it
/// should be unreadable while the device is locked. Pass a nil directory for
/// memory-only behaviour, which is what the tests and the harness use.
public final class ChatTranscript: @unchecked Sendable {
    /// Keeps the file, the decode cost and the SwiftUI diff bounded. Older
    /// turns fall off the top; the model's own context window is trimmed
    /// separately by `AssistantEngine`.
    public static let maxStoredMessages = 100

    private let lock = NSLock()
    private let storageDirectory: URL?
    private var storage: [String: [ChatMessage]] = [:]
    /// Keys already read from disk, so a miss is not retried on every access.
    private var loaded: Set<String> = []

    public init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
        if let storageDirectory {
            // File protection is an iOS feature. Requesting it on macOS - where
            // the tests and the CLI harness run - makes the write fail, which
            // `try?` would then hide as "nothing was saved".
            var attributes: [FileAttributeKey: Any] = [:]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.complete
            #endif
            try? FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: attributes
            )
        }
    }

    public static func key(for session: AssistantSession) -> String {
        "\(session.userID)|\(session.householdID)"
    }

    public func messages(for session: AssistantSession) -> [ChatMessage] {
        lock.withLock {
            let key = Self.key(for: session)
            loadIfNeeded(key)
            return storage[key] ?? []
        }
    }

    public func append(_ message: ChatMessage, for session: AssistantSession) {
        lock.withLock {
            let key = Self.key(for: session)
            loadIfNeeded(key)
            var messages = storage[key] ?? []
            messages.append(message)
            if messages.count > Self.maxStoredMessages {
                messages.removeFirst(messages.count - Self.maxStoredMessages)
            }
            storage[key] = messages
            persist(key, messages)
        }
    }

    /// Replaces one existing message after an app-owned card is edited. The
    /// message id is stable, so this cannot append a duplicate chat turn.
    public func replace(_ message: ChatMessage, for session: AssistantSession) {
        lock.withLock {
            let key = Self.key(for: session)
            loadIfNeeded(key)
            guard var messages = storage[key],
                  let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
            messages[index] = message
            storage[key] = messages
            persist(key, messages)
        }
    }

    /// "Clear conversation" for the household in front of the user.
    public func clear(for session: AssistantSession) {
        lock.withLock {
            let key = Self.key(for: session)
            storage.removeValue(forKey: key)
            loaded.insert(key) // Cleared is a known-empty state, not a cache miss.
            removeFile(key)
        }
    }

    /// Sign-out. Everything goes, on disk as well as in memory - a later
    /// sign-in must not surface the previous account's conversation.
    public func clearAll() {
        lock.withLock {
            storage.removeAll()
            loaded.removeAll()
            guard let storageDirectory else { return }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: storageDirectory, includingPropertiesForKeys: nil
            )) ?? []
            for file in files where file.pathExtension == "json" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Disk
    //
    // Called with the lock already held.

    private func fileURL(_ key: String) -> URL? {
        guard let storageDirectory else { return nil }
        // The key contains a user id and a household id, neither of which is
        // guaranteed to be path-safe, so it is hashed rather than used raw.
        var hash: UInt64 = 5381
        for byte in Array(key.utf8) { hash = hash &* 33 &+ UInt64(byte) }
        return storageDirectory.appendingPathComponent("chat-\(String(hash, radix: 36)).json")
    }

    private func loadIfNeeded(_ key: String) {
        guard !loaded.contains(key) else { return }
        loaded.insert(key)
        guard let url = fileURL(key), let data = try? Data(contentsOf: url) else { return }
        // A transcript that will not decode is discarded rather than crashing
        // the sheet: the card shapes can change between app versions, and an
        // old history is not worth a launch failure.
        guard let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        storage[key] = messages
    }

    private func persist(_ key: String, _ messages: [ChatMessage]) {
        guard let url = fileURL(key), let data = try? JSONEncoder().encode(messages) else { return }
        #if os(iOS)
        // Household schedule data: unreadable while the device is locked.
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        do {
            try data.write(to: url, options: options)
        } catch {
            lastWriteError = error
        }
    }

    /// Set when a write failed. Nothing reads it in production - it exists so
    /// a silent "history did not save" shows up in a test rather than looking
    /// like an empty conversation.
    public private(set) var lastWriteError: Error?

    private func removeFile(_ key: String) {
        guard let url = fileURL(key) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
