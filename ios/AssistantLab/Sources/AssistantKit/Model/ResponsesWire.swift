import Foundation

/// The OpenAI Responses request body and reply parsing, in one place.
///
/// Two clients need it: `RelayLunaClient`, which sends it to the household's
/// own authenticated service, and the development-only direct client in
/// `AssistantDevRelay`. Sharing this means a fix to the wire format cannot land
/// in one and not the other, and that what you exercise against a real key is
/// the same request the relay will forward.
public enum ResponsesWire {

    /// Builds the request body.
    ///
    /// Nothing here enables a hosted tool. There is no web search, code
    /// interpreter, file search or MCP entry, and `store` is false. The relay
    /// re-validates all of that server-side, because a client-side convention
    /// is not a control.
    public static func body(
        model: String,
        request: LunaRequest
    ) throws -> [String: Any] {
        [
            "model": model,
            "instructions": request.instructions,
            "input": request.items.map(item),
            "tools": try JSONSerialization.jsonObject(with: ToolCatalog.wireFormatJSON()),
            "tool_choice": "auto",
            "parallel_tool_calls": true,
            "text": ["format": FinalDecision.responseSchema],
            "max_output_tokens": request.maxOutputTokens,
            "store": false
        ]
    }

    public static func item(_ item: ConversationItem) -> [String: Any] {
        switch item {
        case .userMessage(let text):
            return ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]
        case .toolCall(let call):
            return ["type": "function_call", "call_id": call.callID, "name": call.name, "arguments": call.argumentsJSON]
        case .toolResult(let callID, let payload):
            return ["type": "function_call_output", "call_id": callID, "output": payload]
        case .toolRejected(let callID, let reason):
            // The reason is app-authored text, but it still goes through JSON
            // encoding rather than string interpolation so it cannot break the
            // payload if the wording ever changes.
            let output = (try? JSONSerialization.data(withJSONObject: ["error": "refused", "detail": reason]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"error\":\"refused\"}"
            return ["type": "function_call_output", "call_id": callID, "output": output]
        case .assistantDecision(let json):
            return ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": json]]]
        }
    }

    /// Reads the output array.
    ///
    /// Tool calls take precedence: if the model both called tools and emitted
    /// text, the tools are what happens next and the text is discarded rather
    /// than shown.
    public static func parse(_ data: Data) throws -> LunaReply {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LunaError.invalidResponse("body was not a JSON object")
        }
        if let status = root["status"] as? String, status == "incomplete" {
            let reason = ((root["incomplete_details"] as? [String: Any])?["reason"] as? String) ?? "incomplete"
            // A truncated turn is a failure, not a partial answer to display.
            throw LunaError.invalidResponse("response \(reason)")
        }
        guard let output = root["output"] as? [[String: Any]] else {
            throw LunaError.invalidResponse("missing output array")
        }

        var calls: [RawToolCall] = []
        var decisionJSON: String?

        for item in output {
            switch item["type"] as? String {
            case "function_call":
                guard let callID = item["call_id"] as? String,
                      let name = item["name"] as? String,
                      let args = item["arguments"] as? String else {
                    throw LunaError.invalidResponse("malformed function_call")
                }
                calls.append(RawToolCall(callID: callID, name: name, argumentsJSON: args))
            case "message":
                let content = item["content"] as? [[String: Any]] ?? []
                if let text = content.compactMap({ $0["text"] as? String }).first {
                    decisionJSON = text
                }
            default:
                continue
            }
        }

        if !calls.isEmpty { return .toolCalls(calls) }
        guard let decisionJSON else {
            throw LunaError.invalidResponse("no tool call and no decision")
        }
        return .final(try FinalDecision.decode(decisionJSON))
    }

    /// Maps a `URLError` onto the assistant's own failure vocabulary.
    public static func lunaError(from error: URLError) -> LunaError {
        switch error.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        default:
            return .service(status: error.code.rawValue, detail: error.localizedDescription)
        }
    }
}
