import Foundation
import AssistantKit

/// Replays a fixed sequence of replies.
///
/// Used to drive the cases a well-behaved planner would never produce: an
/// unknown tool name, a field that is not in the schema, another household's
/// ids, a claimed result with nothing behind it. The point is that the engine
/// stops these, so they have to be injectable.
public final class ProgrammedLunaClient: LunaClient, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<LunaReply, LunaError>]
    public private(set) var requests: [LunaRequest] = []

    public init(_ replies: [Result<LunaReply, LunaError>]) {
        self.queue = replies
    }

    public convenience init(replies: [LunaReply]) {
        self.init(replies.map { .success($0) })
    }

    public convenience init(error: LunaError) {
        self.init([.failure(error)])
    }

    public func send(_ request: LunaRequest) async throws -> LunaReply {
        let next: Result<LunaReply, LunaError>? = lock.withLock {
            requests.append(request)
            return queue.isEmpty ? nil : queue.removeFirst()
        }

        guard let next else {
            throw LunaError.invalidResponse("programmed client ran out of replies")
        }
        switch next {
        case .success(let reply): return reply
        case .failure(let error): throw error
        }
    }

    /// Convenience for building a raw call with arbitrary arguments.
    public static func toolCall(_ name: String, _ arguments: [String: Any]) -> LunaReply {
        let data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .toolCalls([RawToolCall(
            callID: "call-\(UUID().uuidString.prefix(8))",
            name: name,
            argumentsJSON: String(data: data, encoding: .utf8) ?? "{}"
        )])
    }
}
