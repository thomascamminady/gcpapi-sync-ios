import Foundation
import Testing

@testable import GCPAPISyncApp

/// The string catalogs as checked in: every string the app shows is in German too, with the
/// same placeholders. `Scripts/check-translations.sh` checks that the catalogs hold every
/// string the compiler finds.
@Suite("Localization")
struct LocalizationTests {
    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let shouldTranslate: Bool?
        let localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        let stringUnit: StringUnit?
    }

    private struct StringUnit: Decodable {
        let state: String
        let value: String
    }

    /// The catalogs in the source tree, which the simulator can read.
    private static let resources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources")

    private static func catalog(_ name: String) throws -> Catalog {
        let data = try Data(contentsOf: resources.appending(path: name))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// The kinds of a format string's placeholders, in order of kind: `%@`, `%lld`, `%%`.
    static func placeholders(_ text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(lld|@|%)/).map { String($0.output.1) }.sorted()
    }

    @Test(arguments: ["Localizable.xcstrings", "InfoPlist.xcstrings"])
    func everyStringIsInGerman(file: String) throws {
        let catalog = try Self.catalog(file)
        #expect(catalog.sourceLanguage == "en")
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            let german = entry.localizations?["de"]?.stringUnit
            #expect(german?.state == "translated", "\(key)")
            #expect(german?.value.isEmpty == false, "\(key)")
        }
    }

    @Test func translationsKeepThePlaceholders() throws {
        for (key, entry) in try Self.catalog("Localizable.xcstrings").strings {
            guard let german = entry.localizations?["de"]?.stringUnit?.value else { continue }
            #expect(Self.placeholders(german) == Self.placeholders(key), "\(key)")
        }
    }

    /// A key with a backslash comes from a literal the compiler did not resolve, such as an
    /// escaped line break: it never matches the string the app looks up.
    @Test func keysAreResolvedText() throws {
        for key in try Self.catalog("Localizable.xcstrings").strings.keys {
            #expect(!key.contains("\\"), "\(key)")
            #expect(!key.isEmpty)
            #expect(key == key.trimmingCharacters(in: .whitespacesAndNewlines), "\(key)")
        }
    }

    @Test func placeholdersAreFoundByKind() {
        #expect(Self.placeholders("%1$@ · %2$lld-week average %3$@") == ["@", "@", "lld"])
        #expect(Self.placeholders("%lld%%") == ["%", "lld"])
        #expect(Self.placeholders("No placeholders").isEmpty)
    }

    @Test func theAppShipsInGerman() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        #expect(
            german.localizedString(forKey: "Settings", value: nil, table: nil) == "Einstellungen")
        #expect(Bundle.main.localizations.contains("de"))
        #expect(Bundle.main.localizations.contains("en"))
    }
}
