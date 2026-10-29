import Foundation
import GCPAPISync

@testable import GCPAPISyncApp

/// Answers every request through `respond`, recording the requests.
nonisolated final class StubTransport: HTTPTransport {
    private let respond: @Sendable (HTTPRequest) -> (status: Int, body: String)
    private let recorder = Recorder()

    init(_ respond: @escaping @Sendable (HTTPRequest) -> (status: Int, body: String)) {
        self.respond = respond
    }

    func send(_ request: HTTPRequest) async -> HTTPResponse {
        await recorder.append(request)
        let (status, body) = respond(request)
        return HTTPResponse(statusCode: status, body: Data(body.utf8), request: request)
    }

    var requests: [HTTPRequest] {
        get async { await recorder.requests }
    }

    private actor Recorder {
        var requests: [HTTPRequest] = []

        func append(_ request: HTTPRequest) {
            requests.append(request)
        }
    }
}

/// A Keychain store of its own, emptied when the test is done.
nonisolated final class ScratchKeychain {
    let store = KeychainStore(service: "dev.camminady.gcpapi-sync.tests.\(UUID().uuidString)")

    deinit {
        for account in [Session.keyAccount, KeychainTokenCache.account] {
            try? store.remove(account)
        }
    }
}

nonisolated let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"

/// A stub Garmin that accepts `goodKey` and serves the demo data.
func garmin(accepting goodKey: String = "good-key") -> StubTransport {
    StubTransport { request in
        if request.path == tokenPath {
            return request.header("Authorization") == "ApiKey \(goodKey)"
                ? (200, "issued-token") : (401, "")
        }
        return (404, "")
    }
}

/// A client whose requests go to `transport`, without retries.
func client(_ transport: any HTTPTransport, apiKey: String = "good-key") throws -> GarminClient {
    try GarminClient(
        apiKey: apiKey, retry: RetryConfig(maxRetries: 0), transport: transport,
        environment: ProcessEnvironment(variables: [:], homeDirectory: .temporaryDirectory))
}

extension GarminDate {
    /// A date from a literal known to be valid.
    static func day(_ text: String) -> GarminDate {
        (try? GarminDate(text)) ?? .today()
    }
}
