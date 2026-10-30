import Foundation
import GCPAPISync
import SwiftUI
import Testing
import UIKit

@testable import GCPAPISyncApp

/// Helpers shared by the black-box suites.
enum BlackBox {
    /// The en dash the app shows without a value.
    static let dash = "\u{2013}"

    /// Only the decimal digits of `text`, to compare numbers whatever their separators.
    nonisolated static func digits(_ text: String) -> String {
        String(text.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init))
    }

    /// Whether `name` is an SF Symbol of this system.
    static func isSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }

    /// Whether `text` is eight hexadecimal digits.
    nonisolated static func isHex8(_ text: String) -> Bool {
        text.count == 8 && text.allSatisfy(\.isHexDigit) && text.allSatisfy(\.isASCII)
    }

    /// `m:ss` for a number of seconds, rounded to the nearest second.
    nonisolated static func minutesSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let tail = total % 60 < 10 ? "0\(total % 60)" : "\(total % 60)"
        return "\(total / 60):\(tail)"
    }

    /// Today, as the app's date functions see it.
    nonisolated static var today: GarminDate { GarminDate.today() }

    /// Every color role, built from the enums rather than from the settings groups.
    static var expectedRoles: [ColorRole] {
        var roles: [ColorRole] = [.accent, .fitness, .fatigue]
        roles += Metric.allCases.map(ColorRole.metric)
        roles += SleepStage.allCases.map(ColorRole.sleepStage)
        roles += ColorRole.StressLevel.allCases.map(ColorRole.stress)
        roles += ColorRole.Status.allCases.map(ColorRole.status)
        roles += Sport.allCases.map(ColorRole.sport)
        roles += (0...6).map(ColorRole.zone)
        roles += FormZone.allCases.map(ColorRole.form)
        roles += TrackMeasure.allCases.map(ColorRole.measure)
        return roles
    }

    /// Every color role the settings list.
    static var listedRoles: [ColorRole] {
        ColorRole.Group.allCases.flatMap(\.roles)
    }

    /// A client whose token exchange works and whose data requests answer `status`.
    static func failing(status: Int, body: String = "{}") throws -> GarminClient {
        let transport = StubTransport { request in
            request.path == tokenPath ? (200, "blackbox-token") : (status, body)
        }
        return try client(transport, apiKey: "blackbox-key")
    }

    /// A client whose every request fails at the transport level.
    static func unreachable(timeout: Bool) throws -> GarminClient {
        let error = TransportError("blackbox: no network", isTimeout: timeout)
        return try client(ThrowingTransport(error: error), apiKey: "blackbox-key")
    }

    /// The error `operation` throws, if any.
    static func error(of operation: () async throws -> Void) async -> (any Error)? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }
}

/// A transport that never obtains a response.
nonisolated struct ThrowingTransport: HTTPTransport {
    let error: TransportError

    func send(_: HTTPRequest) throws -> HTTPResponse {
        throw error
    }
}

/// An error the client never throws.
nonisolated struct BlackBoxStrangeError: Error, Equatable {
    let code: Int
}

/// A throwaway `UserDefaults` suite, removed when released.
final class BlackBoxDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "dev.camminady.blackbox.presentation.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// The keys this suite holds, without the global domain's.
    var storedKeys: Set<String> {
        Set(defaults.persistentDomain(forName: suiteName).map { Array($0.keys) } ?? [])
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
