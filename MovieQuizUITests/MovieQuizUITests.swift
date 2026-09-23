//
//  MovieQuizUITests.swift
//  MovieQuizUITests
//
//  Created by Дмитрий Макеев on 23.09.2026.
//

import XCTest

final class MovieQuizUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        
        app.terminate()
        app = nil
    }
    
    func testYesButton() {
        waitForFirstQuestion()
        
        let firstPosterData = app.images["Poster"].screenshot().pngRepresentation
        let indexLabel = app.staticTexts["Index"]
        
        XCTAssertEqual(indexLabel.label, "1/10")
        
        app.buttons["Yes"].tap()
        waitForIndex("2/10")
        
        let secondPosterData = app.images["Poster"].screenshot().pngRepresentation
        
        XCTAssertNotEqual(firstPosterData, secondPosterData)
        XCTAssertEqual(indexLabel.label, "2/10")
    }
    
    func testNoButton() {
        waitForFirstQuestion()
        
        let firstPosterData = app.images["Poster"].screenshot().pngRepresentation
        let indexLabel = app.staticTexts["Index"]
        
        XCTAssertEqual(indexLabel.label, "1/10")
        
        app.buttons["No"].tap()
        waitForIndex("2/10")
        
        let secondPosterData = app.images["Poster"].screenshot().pngRepresentation
        
        XCTAssertNotEqual(firstPosterData, secondPosterData)
        XCTAssertEqual(indexLabel.label, "2/10")
    }
    
    func testGameFinish() {
        waitForFirstQuestion()
        answerAllQuestions()
        
        let alert = app.alerts["Game results"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertEqual(alert.label, "Этот раунд окончен!")
        XCTAssertEqual(alert.buttons.firstMatch.label, "Сыграть ещё раз")
    }
    
    func testAlertDismiss() {
        waitForFirstQuestion()
        answerAllQuestions()
        
        let alert = app.alerts["Game results"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        alert.buttons.firstMatch.tap()
        
        waitForIndex("1/10")
        
        XCTAssertFalse(alert.exists)
        XCTAssertEqual(app.staticTexts["Index"].label, "1/10")
    }
    
    private func waitForFirstQuestion() {
        XCTAssertTrue(app.staticTexts["Рейтинг этого фильма больше чем 7?"].waitForExistence(timeout: 25))
        waitForIndex("1/10")
    }
    
    private func waitForIndex(_ text: String, timeout: TimeInterval = 20) {
        let indexLabel = app.staticTexts["Index"]
        XCTAssertTrue(indexLabel.waitForExistence(timeout: timeout))
        
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", text),
            object: indexLabel
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed)
    }
    
    private func answerAllQuestions() {
        for number in 1...10 {
            app.buttons["No"].tap()
            if number < 10 {
                waitForIndex("\(number + 1)/10")
            }
        }
    }
}
