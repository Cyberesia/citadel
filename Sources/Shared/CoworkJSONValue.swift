import Foundation

/// Lightweight JSON value for flexible CoworkCore message payloads.
enum CoworkJSONValue: Decodable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CoworkJSONValue])
    case array([CoworkJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: CoworkJSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([CoworkJSONValue].self) { self = .array(value); return }
        self = .null
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var objectValue: [String: CoworkJSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [CoworkJSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    func prettyPrinted(maxLength: Int = 4000) -> String {
        let obj = self.asFoundationObject()
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              var text = String(data: data, encoding: .utf8) else {
            return stringValue ?? ""
        }
        if text.count > maxLength { text = String(text.prefix(maxLength)) + "…" }
        return text
    }

    func asFoundationObject() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues { $0.asFoundationObject() }
        case .array(let a): return a.map { $0.asFoundationObject() }
        case .null: return NSNull()
        }
    }
}

extension CoworkJSONValue: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}
