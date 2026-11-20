import XCTest

@MainActor
final class AccessibilityTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ screen: String, palette: String = "system", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-readingPalette", palette, "-readingFontSize", "18"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["MARGIN_TEST_SCREEN"] = screen
        app.launch()
        return app
    }

    // Drag in the scroll view's margin, clear of selectable Markdown and the
    // keyboard. An application-wide swipe can hit either instead of scrolling.
    private func scrollDown(_ app: XCUIApplication) {
        let bounds = app.frame
        let keyboard = app.keyboards.firstMatch
        let assistant = app.otherElements["SystemInputAssistantView"].firstMatch
        var bottom = bounds.maxY - 34
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
        if assistant.exists { bottom = min(bottom, assistant.frame.minY) }
        let navigation = app.navigationBars.firstMatch
        let top = navigation.exists ? navigation.frame.maxY : bounds.minY + 60
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: bounds.width * 0.94, dy: bottom - bounds.minY - 20))
        let end = origin.withOffset(CGVector(dx: bounds.width * 0.94, dy: top - bounds.minY + 20))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    private func audit(_ app: XCUIApplication, name: String) throws {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        // Collect all findings, with the documented exceptions below.
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        try app.performAccessibilityAudit { issue in
            print("ACCESSIBILITY [\(name)]: \(issue.compactDescription) — \(issue.element?.debugDescription ?? "no element")")
            // Native disabled controls are intentionally dimmed. WCAG 1.4.3
            // exempts inactive controls; enabled controls remain fully audited.
            if issue.auditType == .contrast, let element = issue.element, !element.isEnabled { return true }
            // iOS 27.2 reports these Form labels as non-scaling even though
            // testTextScaling verifies >1.4x growth using their actual frames.
            let scalingVerified = ["appearance-help", "offline-heading", "offline-count", "offline-help"]
            let os = ProcessInfo.processInfo.operatingSystemVersion
            if os.majorVersion == 27, os.minorVersion == 2, issue.auditType == .dynamicType, let element = issue.element,
               element.elementType == .staticText, scalingVerified.contains(element.identifier) { return true }
            if issue.element == nil { print("AUDIT HIERARCHY [\(name)]: \(app.debugDescription)") }
            return false
        }
    }

    func testTextScaling() throws {
        let screens = [
            ("settings", ["appearance-help", "offline-heading", "offline-count", "offline-help"]),
            ("library", ["collection-title-getting-started", "collection-title-ideas"]),
            ("empty", ["empty-title", "empty-help"])
        ]
        for (screen, identifiers) in screens {
            var heights: [String: CGFloat] = [:]
            for large in [false, true] {
                let app = launch(screen, largeText: large)
                for identifier in identifiers {
                    let element = app.descendants(matching: .any)[identifier].firstMatch
                    for _ in 0..<10 {
                        if element.exists && element.isHittable { break }
                        scrollDown(app)
                    }
                    XCTAssertTrue(element.exists, "Missing scaling fixture: \(identifier)")
                    if large {
                        XCTAssertGreaterThan(element.frame.height, try XCTUnwrap(heights[identifier]) * 1.4,
                                             "Text must grow at the largest accessibility size: \(identifier)")
                    } else { heights[identifier] = element.frame.height }
                }
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Scaling \(screen) large=\(large)"; screenshot.lifetime = .keepAlways; add(screenshot)
                app.terminate()
            }
        }
    }

    func testOnboarding() throws {
        let app = launch("connect")
        XCTAssertTrue(app.textFields["Workspace address"].waitForExistence(timeout: 10))
        try audit(app, name: "Onboarding")
        let footer = app.staticTexts["MARGIN · An independent Outline companion"]
        if !footer.isHittable || footer.frame.maxY > app.frame.maxY - 34 {
            scrollDown(app)
            try audit(app, name: "Onboarding lower controls")
        }
    }

    func testLibraryAndSearch() throws {
        let app = launch("library")
        XCTAssertTrue(app.buttons["A little more room to think"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["Children of A little more room to think"].value as? String, "Collapsed")
        app.buttons["Children of A little more room to think"].tap()
        XCTAssertTrue(app.buttons["A quieter reading space"].exists)
        try audit(app, name: "Expanded library")
        app.terminate()
        let search = launch("search")
        XCTAssertTrue(search.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Field notes")).firstMatch.waitForExistence(timeout: 10))
        try audit(search, name: "Search results")
        search.terminate()
        let empty = launch("empty")
        XCTAssertTrue(empty.staticTexts["No documents"].waitForExistence(timeout: 10))
        try audit(empty, name: "Empty search")
    }

    func testReaderPalettes() throws {
        for palette in ["system", "paper", "sepia", "night"] {
            let app = launch("reader", palette: palette)
            XCTAssertTrue(app.staticTexts["document-heading"].waitForExistence(timeout: 10))
            try audit(app, name: "Reader \(palette)")
            scrollDown(app)
            try audit(app, name: "Markdown \(palette)")
            app.terminate()
        }
    }

    func testReferenceAndEditor() throws {
        let app = launch("reference")
        XCTAssertTrue(app.staticTexts.matching(identifier: "document-heading").firstMatch.waitForExistence(timeout: 10))
        if app.buttons["Reference"].exists { app.buttons["Reference"].tap() }
        else { XCTAssertEqual(app.staticTexts.matching(identifier: "document-heading").count, 2) }
        XCTAssertTrue(app.buttons["Close reference"].exists)
        try audit(app, name: "Reference pane")
        app.buttons["Close reference"].tap()
        XCTAssertTrue(app.buttons["Edit document"].waitForExistence(timeout: 5))
        app.buttons["Edit document"].tap()
        XCTAssertTrue(app.textViews["Document content"].waitForExistence(timeout: 5))
        try audit(app, name: "Editor")
        app.buttons["Preview"].tap()
        XCTAssertTrue(app.buttons["Write"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["Document content"].exists)
        XCTAssertTrue(app.staticTexts["A useful heading"].exists)
        app.terminate()
        // Audit the same preview in a fresh process: iOS 27.2's auditor retains
        // the removed UITextView's text frames after the transition above.
        let preview = launch("preview")
        XCTAssertTrue(preview.buttons["Write"].waitForExistence(timeout: 10))
        try audit(preview, name: "Preview")
    }

    func testSettingsAndCompose() throws {
        let settings = launch("settings")
        XCTAssertTrue(settings.staticTexts["Settings"].waitForExistence(timeout: 10))
        try audit(settings, name: "Settings")
        scrollDown(settings)
        try audit(settings, name: "Offline settings")
        settings.terminate()
        let compose = launch("compose")
        XCTAssertTrue(compose.descendants(matching: .any)["Document title"].firstMatch.waitForExistence(timeout: 10))
        try audit(compose, name: "Compose")
    }

    func testKeyboardCreateAndEdit() throws {
        let app = launch("reader")
        XCTAssertTrue(app.buttons["New document"].waitForExistence(timeout: 10))
        app.typeKey("n", modifierFlags: .command)
        let title = app.descendants(matching: .any)["Document title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Keyboard draft")
        app.buttons["Create draft"].tap()
        XCTAssertTrue(app.staticTexts["document-heading"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["document-heading"].label, "Keyboard draft")
        app.buttons["Edit document"].tap()
        let content = app.textViews["Document content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap(); content.typeText("A keyboard note")
        content.typeKey("a", modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(content.value as? String, "**A keyboard note**")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["A keyboard note"].waitForExistence(timeout: 5))
    }

    func testReaderStates() throws {
        for screen in ["error", "loading", "offline"] {
            let app = launch(screen)
            let label = screen == "error" ? "Try again" : screen == "offline" ? "Saved copy" : "Loading document"
            XCTAssertTrue(app.descendants(matching: .any)[label].firstMatch.waitForExistence(timeout: 10))
            try audit(app, name: screen)
            app.terminate()
        }
    }

    private func auditLargestText(_ screen: String) throws {
        let app = launch(screen, largeText: true)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try audit(app, name: "Largest text \(screen)")
        scrollDown(app)
        try audit(app, name: "Largest text scrolled \(screen)")
        if screen == "editor" {
            let content = app.textViews["Document content"]
            XCTAssertTrue(content.isHittable)
            content.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let visibleHeight = min(content.frame.maxY, app.keyboards.firstMatch.frame.minY) - content.frame.minY
            XCTAssertGreaterThanOrEqual(visibleHeight, 44, "The keyboard must leave room to edit")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Largest editor with keyboard"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
    }

    func testLargestTextOnboarding() throws { try auditLargestText("connect") }
    func testLargestTextLibrary() throws { try auditLargestText("library") }
    func testLargestTextReader() throws { try auditLargestText("reader") }
    func testLargestTextReference() throws { try auditLargestText("reference") }
    func testLargestTextEditor() throws { try auditLargestText("editor") }
    func testLargestTextSettings() throws { try auditLargestText("settings") }
    func testLargestTextCompose() throws { try auditLargestText("compose") }
}
