import Foundation

/// Sends the push server a token and a list of times.
///
/// Deliberately the only thing in the app that talks to a network. It is given
/// a `PushRegistration`, which holds a token and numbers, and it cannot reach
/// anything else — there is no path from here to an item's title.
///
/// Push is off until the user fills in an endpoint, so the default build makes
/// no network calls at all.
nonisolated struct PushRegistrar: Sendable {
    var endpoint: URL
    var key: String
    var session: URLSession

    init(endpoint: URL, key: String, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.key = key
        self.session = session
    }

    /// Built from what the user typed in Settings, or `nil` when push is off.
    static func configured(session: URLSession = .shared) -> PushRegistrar? {
        guard let raw = SharedDefaults.pushEndpoint,
              let url = URL(string: raw),
              url.scheme == "https",
              let key = SharedDefaults.pushKey,
              !key.isEmpty
        else { return nil }
        return PushRegistrar(endpoint: url, key: key, session: session)
    }

    func send(_ registration: PushRegistration) async throws {
        var request = URLRequest(url: endpoint.appending(path: "register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-daybook-key")
        request.httpBody = try JSONEncoder().encode(registration)
        request.timeoutInterval = 15

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PushRegistrarError.refused(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
    }
}

nonisolated enum PushRegistrarError: Error, Sendable {
    case refused(Int)
}

nonisolated extension SharedDefaults {
    enum PushKey {
        static let endpoint = "pushEndpoint"
        static let key = "pushKey"
    }

    /// The Worker's base URL. Empty means push updates are off, which is the
    /// default and a perfectly good way to run the app.
    static var pushEndpoint: String? {
        get { store.string(forKey: PushKey.endpoint) }
        set { store.set(newValue, forKey: PushKey.endpoint) }
    }

    static var pushKey: String? {
        get { store.string(forKey: PushKey.key) }
        set { store.set(newValue, forKey: PushKey.key) }
    }

    static var isPushConfigured: Bool {
        pushEndpoint?.isEmpty == false && pushKey?.isEmpty == false
    }
}
