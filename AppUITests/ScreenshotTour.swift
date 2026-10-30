import XCTest

/// Walks through every tab of the demo in English and in German and keeps a screenshot of each
/// screen: a smoke test of the whole app, and pictures to check its layout by eye.
///
/// `Scripts/tour.sh` runs it on a fresh simulator and saves the screenshots.
final class ScreenshotTour: XCTestCase {
    @MainActor
    func testEnglish() {
        tour(language: "en", region: "US")
    }

    @MainActor
    func testGerman() {
        tour(language: "de", region: "DE")
    }

    @MainActor
    private func tour(language: String, region: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demo", "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_\(region)",
        ]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 30), "The app shows its tabs")
        let names = ["summary", "activities", "training", "routes", "settings"]
        XCTAssertEqual(tabs.buttons.count, names.count)
        for (index, name) in names.enumerated() {
            select(tab: index, in: tabs, of: app)
            let prefix = "\(language)-\(index + 1)-\(name)"
            pages(of: app, named: prefix)
            switch name {
            case "summary":
                open(app.buttons["tile.sleep"], in: app, named: "\(prefix)-sleep")
                select(tab: index, in: tabs, of: app)
            case "activities":
                open(app.buttons["workout.running"].firstMatch, in: app, named: "\(prefix)-run")
                select(tab: index, in: tabs, of: app)
            default:
                break
            }
        }
    }

    /// The screen from the top and after each of two swipes up, then scrolled back.
    @MainActor
    private func pages(of app: XCUIApplication, named name: String) {
        keep(app, named: "\(name)-a")
        app.swipeUp()
        keep(app, named: "\(name)-b")
        app.swipeUp()
        keep(app, named: "\(name)-c")
        app.swipeDown()
        app.swipeDown()
    }

    @MainActor
    private func open(_ element: XCUIElement, in app: XCUIApplication, named name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name) can be opened")
        element.tap()
        XCTAssertTrue(
            app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10), "\(name) opens")
        pages(of: app, named: name)
    }

    /// Taps a tab; the tab bar shrinks to the selected tab while scrolling, and a swipe back
    /// down brings the others back.
    @MainActor
    private func select(tab index: Int, in tabs: XCUIElement, of app: XCUIApplication) {
        let button = tabs.buttons.element(boundBy: index)
        if !button.exists {
            app.swipeDown()
        }
        button.tap()
    }

    @MainActor
    private func keep(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
