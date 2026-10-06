import Foundation

/// The relay carries the guest's serial back to the host, so the host's
/// report arrives on its own instead of being typed in (see `relay/worker.js`).
/// It holds host serial → guest serial for 24 h — and, when both sides have
/// the pair photo on, each one's heat grid for the other, handed out only for
/// a key (see `HeatGrid`).
///
/// Every call can fail quietly: typing the serial in on 02 still works.
enum Relay {
    private static let base = URL(string: "https://soul-match-relay.momoopsoops.workers.dev")!

    /// What became of a reply sent to the relay.
    enum Sent {
        /// Filed, or refused for good; either way there is nothing to retry.
        case settled
        /// Offline, rate-limited or the relay is down: worth another try.
        case retry
    }

    /// A reply waiting at the relay.
    struct Reply: Decodable {
        let guest: String?
        /// When the relay filed it, in milliseconds since 1970.
        let at: Double?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// What the relay is sent. Fields left nil are left out.
    private struct Body: Encodable {
        let host: String
        var guest: String? = nil
        var key: String? = nil
        var heat: String? = nil
    }

    private struct Heat: Decodable {
        let heat: String?
    }

    /// Posts to the relay. Nil when it never answered.
    private static func post(_ path: String, _ body: Body) async -> (status: Int, data: Data)? {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, data)
    }

    /// 2xx filed it; other 4xx (bad serial, already replied) won't change.
    private static func sent(_ status: Int?) -> Sent {
        guard let status else { return .retry }
        return status == 429 || status >= 500 ? .retry : .settled
    }

    /// The guest finished measuring: file their serial under the host's. With
    /// a `key`, the guest's grid goes along and `heat` is the host's, when
    /// there is one.
    static func send(
        host: String, guest: String, key: String? = nil, heat: String? = nil
    ) async -> (sent: Sent, heat: String?) {
        let answer = await post("reply", Body(host: host, guest: guest, key: key, heat: key == nil ? nil : heat))
        let theirs = answer.flatMap { try? JSONDecoder().decode(Heat.self, from: $0.data) }?.heat
        return (sent(answer?.status), key == nil ? nil : theirs)
    }

    /// The host handed their serial out: file the key their guest's grid will
    /// be fetched with, and their own grid if they have one.
    static func file(host: String, key: String, heat: String?) async -> Sent {
        sent(await post("host", Body(host: host, key: key, heat: heat))?.status)
    }

    /// What became of asking for the guest's grid.
    enum PeerHeat {
        /// The grid, or nil when there is none to be had.
        case settled(String?)
        /// Worth asking again.
        case retry
    }

    /// The guest's grid, for the host's key.
    static func peerHeat(host: String, key: String) async -> PeerHeat {
        guard let answer = await post("heat", Body(host: host, key: key)), sent(answer.status) == .settled else {
            return .retry
        }
        guard answer.status == 200 else { return .settled(nil) }
        return .settled((try? JSONDecoder().decode(Heat.self, from: answer.data))?.heat)
    }

    /// Whether anything has come back for this host serial.
    static func reply(for host: String) async -> Reply? {
        let digits = String(host.dropFirst(SerialCodec.prefix.count))
        guard let (data, response) = try? await session.data(from: base.appending(path: "reply/\(digits)")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.guest != nil else { return nil }
        return reply
    }
}
