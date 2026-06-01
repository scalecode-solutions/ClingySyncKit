import Foundation

/// A Codable representation of an arbitrary JSON value, used so the log
/// `payload` rides the envelope as an inline JSON object (not a base64 Data
/// blob). It bridges raw payload bytes ↔ the encoder/decoder.
enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unsupported JSON"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue {
    /// Parse raw JSON bytes into a JSONValue (empty → {}).
    init(fromJSON data: Data) {
        if data.isEmpty { self = .object([:]); return }
        self = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
    }

    /// Serialize back to raw JSON bytes.
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
