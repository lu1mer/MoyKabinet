import XCTest

final class MoyKabinetUITests: XCTestCase {
    func testDailyWorkflowAndPersistence() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-data", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.buttons["Посмотреть пример"].waitForExistence(timeout: 15))
        app.buttons["Посмотреть пример"].tap()
        XCTAssertTrue(app.staticTexts["Анна Смирнова"].firstMatch.waitForExistence(timeout: 5))
        capture("01-today", app)
        app.tabBars.buttons["Календарь"].tap()
        XCTAssertTrue(app.staticTexts["Расписание"].exists)
        capture("02-calendar", app)
        app.tabBars.buttons["Клиенты"].tap()
        XCTAssertTrue(app.staticTexts["София Ким"].waitForExistence(timeout: 5))
        capture("03-clients", app)
        app.tabBars.buttons["Кабинет"].tap()
        XCTAssertTrue(app.staticTexts["Бьюти-мастер"].exists)
        capture("04-cabinet", app)
        app.tabBars.buttons["Сегодня"].tap()
        app.buttons["Новая запись"].tap()
        XCTAssertTrue(app.buttons["newClient"].waitForExistence(timeout: 5))
        app.buttons["newClient"].tap()
        let name = app.textFields["clientName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Тестовый клиент")
        app.buttons["saveClient"].tap()
        XCTAssertTrue(app.buttons["saveBooking"].waitForExistence(timeout: 5))
        if !app.buttons["saveBooking"].isEnabled {
            let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Выбрать свободное время:")).firstMatch
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            suggestion.tap()
        }
        XCTAssertTrue(app.buttons["saveBooking"].isEnabled)
        capture("05-booking", app)
        app.buttons["saveBooking"].tap()
        app.tabBars.buttons["Клиенты"].tap()
        XCTAssertTrue(app.staticTexts["Тестовый клиент"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Тестовый клиент"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Маникюр с покрытием"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Маникюр с покрытием"].firstMatch.tap()
        XCTAssertTrue(app.buttons["markPaid"].waitForExistence(timeout: 5))
        app.buttons["markPaid"].tap()
        XCTAssertTrue(app.buttons["Убрать отметку об оплате"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        let clientsTab = app.tabBars.buttons["Клиенты"]
        XCTAssertTrue(clientsTab.waitForExistence(timeout: 15))
        // LaunchView intentionally covers the tabs during its short brand animation.
        sleep(2)
        clientsTab.tap()
        XCTAssertTrue(app.staticTexts["Тестовый клиент"].waitForExistence(timeout: 5))
        app.staticTexts["Тестовый клиент"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Оплачено")).firstMatch.waitForExistence(timeout: 5))
    }

    func testAuthenticationIsRequiredAtLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--auth-ui-testing", "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()
        XCTAssertTrue(app.textFields["authEmail"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.secureTextFields["authPassword"].exists)
        XCTAssertFalse(app.tabBars.buttons["Сегодня"].exists)
        capture("06-account", app)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
