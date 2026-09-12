import Foundation

/// Minimal JSON Schema builder for OpenAI strict function schemas.
///
/// Strict mode requires that every property is listed in `required` and that
/// `additionalProperties` is false, so optionality is expressed as a nullable
/// type rather than by omitting the key. `.nullable` exists to make that
/// explicit at the call site instead of hiding it in hand-written dictionaries.
public indirect enum JSONSchema: Sendable {
    case string(description: String)
    case stringEnum(description: String, values: [String])
    case integer(description: String, minimum: Int?, maximum: Int?)
    case boolean(description: String)
    case array(description: String, items: JSONSchema, maxItems: Int?)
    case object(description: String, properties: [(String, JSONSchema)])
    case nullable(JSONSchema)

    public var json: [String: Any] {
        switch self {
        case .string(let description):
            return ["type": "string", "description": description]
        case .stringEnum(let description, let values):
            return ["type": "string", "description": description, "enum": values]
        case .integer(let description, let minimum, let maximum):
            var out: [String: Any] = ["type": "integer", "description": description]
            if let minimum { out["minimum"] = minimum }
            if let maximum { out["maximum"] = maximum }
            return out
        case .boolean(let description):
            return ["type": "boolean", "description": description]
        case .array(let description, let items, let maxItems):
            var out: [String: Any] = ["type": "array", "description": description, "items": items.json]
            if let maxItems { out["maxItems"] = maxItems }
            return out
        case .object(let description, let properties):
            var props: [String: Any] = [:]
            for (name, schema) in properties { props[name] = schema.json }
            return [
                "type": "object",
                "description": description,
                "properties": props,
                "required": properties.map(\.0),
                "additionalProperties": false
            ]
        case .nullable(let inner):
            var out = inner.json
            if let type = out["type"] as? String {
                out["type"] = [type, "null"]
            }
            return out
        }
    }
}
