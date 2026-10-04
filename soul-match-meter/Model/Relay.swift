import Foundation

/// The relay carries the guest's serial back to the host, so the host's
/// report arrives on its own instead of being typed in (see `relay/worker.js`).
/// It holds host serial → guest serial for 24 h and nothing else.
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

    /// The guest finished measuring: file their serial under the host's.
    static func send(host: String, guest: String) async -> Sent {
        var request = URLRequest(url: base.appending(path: "reply"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["host": host, "guest": guest])
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .retry }
        // 2xx filed it; other 4xx (bad serial, already replied) won't change.
        return status == 429 || status >= 500 ? .retry : .settled
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
