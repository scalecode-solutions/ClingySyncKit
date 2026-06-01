import Foundation

/// The logs.* message DTOs — shared by the real transport (JSON over the wire)
/// and the fake transport (in-memory). Field names match clingy2_api's
/// envelope `data` shapes exactly.

public struct UpsertItem: Codable, Sendable {
    public var clientId: UUID
    public var type: String
    public var schemaVersion: Int
    public var occurredAt: Date
    public var payload: Data        // raw JSON payload bytes
    public var deleted: Bool

    public init(clientId: UUID, type: String, schemaVersion: Int, occurredAt: Date, payload: Data, deleted: Bool) {
        self.clientId = clientId
        self.type = type
        self.schemaVersion = schemaVersion
        self.occurredAt = occurredAt
        self.payload = payload
        self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey { case clientId, type, schemaVersion, occurredAt, payload, deleted }

    // payload is raw JSON — encode/decode it as an inline JSON value, not a
    // base64 Data blob.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try c.decode(UUID.self, forKey: .clientId)
        type = try c.decode(String.self, forKey: .type)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        occurredAt = try c.decode(Date.self, forKey: .occurredAt)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        let raw = try c.decode(JSONValue.self, forKey: .payload)
        payload = try raw.encoded()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(type, forKey: .type)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(occurredAt, forKey: .occurredAt)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(JSONValue(fromJSON: payload), forKey: .payload)
    }
}

public struct UpsertReq: Codable, Sendable {
    public var subjectId: UUID
    public var logs: [UpsertItem]
    public init(subjectId: UUID, logs: [UpsertItem]) { self.subjectId = subjectId; self.logs = logs }
}

public struct UpsertResult: Codable, Sendable {
    public var clientId: UUID
    public var serverSeq: Int64
    public var updatedAt: Date
    public init(clientId: UUID, serverSeq: Int64, updatedAt: Date) {
        self.clientId = clientId; self.serverSeq = serverSeq; self.updatedAt = updatedAt
    }
}

public struct UpsertRes: Codable, Sendable {
    public var results: [UpsertResult]
    public var cursor: Int64
    public init(results: [UpsertResult], cursor: Int64) { self.results = results; self.cursor = cursor }
}

public struct PullReq: Codable, Sendable {
    public var subjectId: UUID
    public var since: Int64
    public init(subjectId: UUID, since: Int64) { self.subjectId = subjectId; self.since = since }
}

public struct LogRow: Codable, Sendable {
    public var clientId: UUID
    public var subjectId: UUID
    public var type: String
    public var schemaVersion: Int
    public var occurredAt: Date
    public var payload: Data
    public var deletedAt: Date?
    public var serverSeq: Int64
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case clientId, subjectId, type, schemaVersion, occurredAt, payload, deletedAt, serverSeq, updatedAt
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try c.decode(UUID.self, forKey: .clientId)
        subjectId = try c.decode(UUID.self, forKey: .subjectId)
        type = try c.decode(String.self, forKey: .type)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        occurredAt = try c.decode(Date.self, forKey: .occurredAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        serverSeq = try c.decode(Int64.self, forKey: .serverSeq)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        payload = try c.decode(JSONValue.self, forKey: .payload).encoded()
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(subjectId, forKey: .subjectId)
        try c.encode(type, forKey: .type)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(occurredAt, forKey: .occurredAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(serverSeq, forKey: .serverSeq)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(JSONValue(fromJSON: payload), forKey: .payload)
    }
    public init(clientId: UUID, subjectId: UUID, type: String, schemaVersion: Int, occurredAt: Date, payload: Data, deletedAt: Date?, serverSeq: Int64, updatedAt: Date) {
        self.clientId = clientId; self.subjectId = subjectId; self.type = type
        self.schemaVersion = schemaVersion; self.occurredAt = occurredAt; self.payload = payload
        self.deletedAt = deletedAt; self.serverSeq = serverSeq; self.updatedAt = updatedAt
    }
}

public struct PullRes: Codable, Sendable {
    public var logs: [LogRow]
    public var cursor: Int64
    public init(logs: [LogRow], cursor: Int64) { self.logs = logs; self.cursor = cursor }
}
