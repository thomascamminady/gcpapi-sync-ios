import Foundation
import GCPAPISync

/// What went wrong, in terms a person can act on.
nonisolated enum Problem: Error, Equatable, Sendable {
    case emptyKey
    case keyRejected
    case offline
    case timedOut
    case rateLimited
    case garminUnavailable
    case keychain
    case unexpected(String)

    /// Classify an error thrown by the client.
    init(_ error: any Error) {
        switch error {
        case let problem as Self: self = problem
        case is AuthenticationError: self = .keyRejected
        case let failure as APIConnectionError: self = failure.isTimeout ? .timedOut : .offline
        case is RateLimitError: self = .rateLimited
        case let failure as any APIStatusError where failure.statusCode >= 500:
            self = .garminUnavailable
        case is KeychainError: self = .keychain
        case let failure as any GarminError: self = .unexpected(failure.message)
        default: self = .unexpected(error.localizedDescription)
        }
    }

    var title: String {
        switch self {
        case .emptyKey: String(localized: "Enter your API key")
        case .keyRejected: String(localized: "Garmin rejected the API key")
        case .offline: String(localized: "You're offline")
        case .timedOut: String(localized: "Garmin is not responding")
        case .rateLimited: String(localized: "Too many requests")
        case .garminUnavailable: String(localized: "Garmin is unavailable")
        case .keychain: String(localized: "The Keychain is unavailable")
        case .unexpected: String(localized: "Something went wrong")
        }
    }

    var message: String {
        switch self {
        case .emptyKey:
            String(localized: "Paste the key you created in Garmin Connect.")
        case .keyRejected:
            String(
                localized: """
                    It may have expired or been deleted. Create a new key in Garmin Connect \
                    under Settings › Personal API.
                    """
            )
        case .offline: String(localized: "Check your internet connection and try again.")
        case .timedOut: String(localized: "Garmin took too long to answer. Try again in a moment.")
        case .rateLimited: String(localized: "Garmin asked to slow down. Try again in a minute.")
        case .garminUnavailable:
            String(localized: "Garmin's servers had a problem. Try again later.")
        case .keychain:
            String(
                localized:
                    "Your key could not be stored securely. Unlock your iPhone and try again.")
        case .unexpected(let detail): detail
        }
    }

    var symbol: String {
        switch self {
        case .emptyKey, .keyRejected: "key.slash"
        case .offline: "wifi.slash"
        case .timedOut, .rateLimited: "hourglass"
        case .garminUnavailable: "exclamationmark.icloud"
        case .keychain: "lock.trianglebadge.exclamationmark"
        case .unexpected: "exclamationmark.triangle"
        }
    }
}
