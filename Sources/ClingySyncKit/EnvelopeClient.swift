import Foundation

/// Generic, transport-agnostic typed-envelope client over HTTP.
///
/// This is the reusable primitive: send a typed `Req` for a `type`, get a typed
/// `Res` back, or throw a structured `EnvelopeError`. It imports nothing
/// app-specific — the auth token comes through an injected `tokenProvider`
/// (the decoy-blind seam). Clingy and (eventually) chat run the same client.
public final class EnvelopeClient: @unchecked Sendable {
    private let endpoint: URL
    private let tokenProvider: () -> String?
    private let session: URLSession

    /// - Parameters:
    ///   - endpoint: the `/v1/rpc` URL.
    ///   - tokenProvider: returns the current bearer token (or nil for anonymous).
    public init(endpoint: URL, tokenProvider: @escaping () -> String? = { nil }, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Sends `{type, data}` and decodes the success payload, or throws the
    /// structured error on `ok:false`.
    public func send<Req: Encodable, Res: Decodable>(_ type: String, _ data: Req) async throws -> Res {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder.envelope.encode(WireRequest(type: type, data: data))

        let (body, _) = try await session.data(for: req)
        let wire = try JSONDecoder.envelope.decode(WireResponse<Res>.self, from: body)
        if !wire.ok {
            throw wire.error ?? EnvelopeError(code: WireCode.internalError, message: "ok:false with no error")
        }
        guard let data = wire.data else {
            throw EnvelopeError(code: WireCode.internalError, message: "ok:true with no data")
        }
        return data
    }
}
