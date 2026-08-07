import Foundation

/// Provider-specific JSON Schema lowering for MCP tool definitions (Codex / OpenCode style).
enum CoworkMcpToolSchemaSanitizer {
    private static let allowedTypes: Set<String> = [
        "string", "number", "boolean", "integer", "object", "array", "null",
    ]
    private static let compositionKeys = ["anyOf", "oneOf", "allOf"]
    private static let schemaIntentKeys = [
        "type", "properties", "items", "prefixItems", "enum", "const", "$ref",
        "additionalProperties", "patternProperties", "required", "not", "if", "then", "else",
    ]

    /// Lower an MCP `inputSchema` to a provider-safe subset. Returns nil when the schema cannot be made usable.
    static func sanitize(_ schema: CoworkJSONValue, profile: CoworkMcpToolProfile) -> CoworkJSONValue? {
        let enveloped = aisanceEnvelope(schema)
        switch profile {
        case .openAICompatible:
            return sanitizeOpenAI(enveloped)
        case .anthropic:
            return sanitizeOpenAI(enveloped)
        case .gemini:
            return sanitizeGemini(enveloped)
        case .localPermissive:
            return enveloped
        }
    }

    /// Aisance/Polaris: force object root, empty properties default, additionalProperties false before provider send.
    static func aisanceEnvelope(_ schema: CoworkJSONValue) -> CoworkJSONValue {
        guard case .object(var object) = schema else {
            return .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false),
            ])
        }
        if object["properties"] == nil {
            object["properties"] = .object([:])
        }
        object["additionalProperties"] = .bool(false)
        if object["type"] == nil {
            object["type"] = .string("object")
        }
        return .object(object)
    }

    /// Returns false when a tool should be excluded from cloud sessions.
    static func isUsableAfterSanitization(_ schema: CoworkJSONValue?, profile: CoworkMcpToolProfile) -> Bool {
        guard profile != .localPermissive else { return true }
        guard let schema else { return true }
        guard let sanitized = sanitize(schema, profile: profile) else { return false }
        return !isEmptySchema(sanitized)
    }

    private static func isEmptySchema(_ value: CoworkJSONValue) -> Bool {
        guard let object = value.objectValue else { return false }
        return object.isEmpty
    }

    // MARK: - OpenAI / Anthropic (OpenCode `sanitizeOpenAISchema`)

    private static func sanitizeOpenAI(_ value: CoworkJSONValue) -> CoworkJSONValue? {
        switch value {
        case .bool(true):
            return .object(["type": .string("string")])
        case .bool(false):
            return .object(["type": .string("string")])
        case .array(let items):
            return .array(items.compactMap { sanitizeOpenAI($0) })
        case .object:
            break
        default:
            return value
        }

        guard case .object(let object) = value else { return value }

        var result: [String: CoworkJSONValue] = [:]

        if let ref = object["$ref"]?.stringValue {
            result["$ref"] = .string(ref)
        }
        if let description = object["description"]?.stringValue {
            result["description"] = .string(description)
        }
        if let constValue = object["const"] {
            result["enum"] = .array([constValue])
        } else if let enumValues = object["enum"]?.arrayValue {
            result["enum"] = .array(enumValues)
        }

        if let properties = object["properties"]?.objectValue {
            var sanitizedProperties: [String: CoworkJSONValue] = [:]
            for (key, item) in properties {
                if let sanitized = sanitizeOpenAI(item) {
                    sanitizedProperties[key] = sanitized
                }
            }
            result["properties"] = .object(sanitizedProperties)
        }

        if let required = object["required"]?.arrayValue {
            let names = required.compactMap(\.stringValue)
            if !names.isEmpty {
                result["required"] = .array(names.map(CoworkJSONValue.string))
            }
        }

        if let items = object["items"] {
            if let sanitized = sanitizeOpenAI(items) {
                result["items"] = sanitized
            }
        }

        if let additional = object["additionalProperties"] {
            switch additional {
            case .bool(let flag):
                result["additionalProperties"] = .bool(flag)
            default:
                if let sanitized = sanitizeOpenAI(additional) {
                    result["additionalProperties"] = sanitized
                }
            }
        }

        for key in compositionKeys {
            if let branch = object[key]?.arrayValue {
                let sanitized = branch.compactMap { sanitizeOpenAI($0) }
                if !sanitized.isEmpty {
                    result[key] = .array(sanitized)
                }
            }
        }

        for key in ["$defs", "definitions"] {
            if let defs = object[key]?.objectValue {
                var sanitizedDefs: [String: CoworkJSONValue] = [:]
                for (name, item) in defs {
                    if let sanitized = sanitizeOpenAI(item) {
                        sanitizedDefs[name] = sanitized
                    }
                }
                if !sanitizedDefs.isEmpty {
                    result[key] = .object(sanitizedDefs)
                }
            }
        }

        let schemaTypes = normalizedTypes(from: object["type"])
        if schemaTypes.isEmpty,
           result["$ref"] != nil || compositionKeys.contains(where: { result[$0] != nil }) {
            return finalizeOpenAIObject(result, inferredTypes: [])
        }

        let inferredTypes: [String]
        if !schemaTypes.isEmpty {
            inferredTypes = schemaTypes
        } else if ["properties", "required", "additionalProperties"].contains(where: { object[$0] != nil }) {
            inferredTypes = ["object"]
        } else if object["items"] != nil || object["prefixItems"] != nil {
            inferredTypes = ["array"]
        } else if result["enum"] != nil || object["format"] != nil {
            inferredTypes = ["string"]
        } else if ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"]
            .contains(where: { object[$0] != nil }) {
            inferredTypes = ["number"]
        } else if object["description"] != nil {
            inferredTypes = ["string"]
        } else {
            inferredTypes = []
        }

        return finalizeOpenAIObject(result, inferredTypes: inferredTypes)
    }

    private static func finalizeOpenAIObject(
        _ result: [String: CoworkJSONValue],
        inferredTypes: [String]
    ) -> CoworkJSONValue? {
        guard !inferredTypes.isEmpty else { return nil }
        var output = result
        output["type"] = inferredTypes.count == 1
            ? .string(inferredTypes[0])
            : .array(inferredTypes.map(CoworkJSONValue.string))
        if inferredTypes.contains("object"), output["properties"] == nil {
            output["properties"] = .object([:])
        }
        if inferredTypes.contains("object"), output["additionalProperties"] == nil {
            output["additionalProperties"] = .bool(false)
        }
        if inferredTypes.contains("array"), output["items"] == nil {
            output["items"] = .object(["type": .string("string")])
        }
        return .object(output)
    }

    private static func normalizedTypes(from value: CoworkJSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .string(let type):
            return allowedTypes.contains(type) ? [type] : []
        case .array(let types):
            return types.compactMap(\.stringValue).filter { allowedTypes.contains($0) }
        default:
            return []
        }
    }

    // MARK: - Gemini

    private static func sanitizeGemini(_ value: CoworkJSONValue) -> CoworkJSONValue? {
        guard let openAI = sanitizeOpenAI(value), case .object(var object) = openAI else {
            return sanitizeOpenAI(value)
        }

        if let typeArray = object["type"]?.arrayValue, typeArray.count > 1 {
            let nonNull = typeArray.compactMap(\.stringValue).filter { $0 != "null" }
            if nonNull.count == 1 {
                object["type"] = .string(nonNull[0])
            } else if nonNull.count > 1 {
                object.removeValue(forKey: "type")
                object["anyOf"] = .array(nonNull.map { .object(["type": .string($0)]) })
            }
        }

        if let enumValues = object["enum"]?.arrayValue {
            object["enum"] = .array(enumValues.map { item in
                if let string = item.stringValue { return .string(string) }
                return .string(String(describing: item.asFoundationObject()))
            })
            if object["type"]?.stringValue == "integer" || object["type"]?.stringValue == "number" {
                object["type"] = .string("string")
            }
        }

        return .object(object)
    }

    /// Rough serialized size budget for one tool schema (Codex compacts above ~4 KB).
    static func serializedByteCount(_ schema: CoworkJSONValue) -> Int {
        let object = schema.asFoundationObject()
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return Int.max
        }
        return data.count
    }

    static func hasSchemaIntent(_ value: CoworkJSONValue) -> Bool {
        guard let object = value.objectValue else { return false }
        if compositionKeys.contains(where: { object[$0]?.arrayValue?.isEmpty == false }) {
            return true
        }
        return schemaIntentKeys.contains(where: { object[$0] != nil })
    }
}
