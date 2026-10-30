import UIKit
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
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // A wide window has the dashboard in place of the summary.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let names = [
            isPad ? "dashboard" : "summary", "activities", "training", "routes", "settings",
        ]
        // Tabs are buttons named after their symbols: in the tab bar on the iPhone, at the top
        // on the iPad.
        let tabs = [
            isPad ? "rectangle.split.3x1" : "heart.text.square", "figure.run",
            "chart.line.uptrend.xyaxis", "point.topleft.down.to.point.bottomright.curvepath",
            "gearshape",
        ]
        let first = isPad ? app.buttons[tabs[0]].firstMatch : app.tabBars.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30), "The app shows its tabs")
        for (index, name) in names.enumerated() {
            select(index, symbol: tabs[index], in: app)
            let prefix = "\(language)-\(index + 1)-\(name)"
            pages(of: app, named: prefix)
            switch name {
            case "summary":
                open(app.buttons["tile.sleep"], in: app, named: "\(prefix)-sleep")
                select(index, symbol: tabs[index], in: app)
            case "dashboard":
                open(app.buttons["log.running"].firstMatch, in: app, named: "\(prefix)-run")
                select(index, symbol: tabs[index], in: app)
            case "activities":
                open(app.buttons["workout.running"].firstMatch, in: app, named: "\(prefix)-run")
                select(index, symbol: tabs[index], in: app)
            default:
                break
            }
        }
        if isPad {
            // Landscape puts the figures beside the tables.
            XCUIDevice.shared.orientation = .landscapeLeft
            select(0, symbol: tabs[0], in: app)
            pages(of: app, named: "\(language)-0-dashboard-landscape")
            XCUIDevice.shared.orientation = .portrait
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

    /// Taps a tab. On the iPhone, a tab bar button, whose others the bar hides while scrolling
    /// until a swipe back down. On the iPad, a button named `symbol` at the top, or a cell in
    /// the sidebar, which shows in landscape and opens with a button in portrait.
    @MainActor
    private func select(_ index: Int, symbol: String, in app: XCUIApplication) {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            let button = app.tabBars.firstMatch.buttons.element(boundBy: index)
            if !button.exists {
                app.swipeDown()
            }
            button.tap()
            return
        }
        let cell = app.cells[symbol].firstMatch
        if cell.exists {
            cell.tap()
            return
        }
        let button = app.buttons[symbol].firstMatch
        if button.exists, button.isHittable {
            button.tap()
            return
        }
        app.buttons.matching(NSPredicate(format: "identifier ==[c] 'togglesidebar'")).firstMatch
            .tap()
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "The sidebar lists \(symbol)")
        cell.tap()
    }

    @MainActor
    private func keep(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
