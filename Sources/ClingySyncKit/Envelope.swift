import Foundation

/// Structured wire error — mirrors clingy2_api's proto.ErrorDetail. Thrown by
/// the EnvelopeClient when a response comes back `ok:false`.
public struct EnvelopeError: Error, Decodable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String
    public var description: String { "\(code): \(message)" }
}

/// The shared error-code vocabulary (mirrors wire-format-spec.md §3).
public enum WireCode {
    public static let validation = "VALIDATION_ERROR"
    public static let unauthorized = "UNAUTHORIZED"
    public static let forbidden = "FORBIDDEN"
    public static let notFound = "NOT_FOUND"
    public static let internalError = "INTERNAL_ERROR"
}

/// Request envelope: { type, data }.
struct WireRequest<T: Encodable>: Encodable {
    let type: String
    let data: T
}

/// Response envelope: { ok, data?, error? } — success or error, never both.
struct WireResponse<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: EnvelopeError?
}

extension JSONEncoder {
    /// Encoder matching the server contract (RFC3339 timestamps).
    static var envelope: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    /// Decoder tolerant of RFC3339 with or without fractional seconds.
    static var envelope: JSONDecoder {
        let d = JSONDecoder()
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let dt = frac.date(from: s) ?? plain.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date: \(s)"))
        }
        return d
    }
}
