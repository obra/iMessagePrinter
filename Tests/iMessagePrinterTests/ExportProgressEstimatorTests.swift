import XCTest
@testable import iMessagePrinter

final class ExportProgressEstimatorTests: XCTestCase {
    func testFractionUsesMessageAndImageWeights() {
        var now: TimeInterval = 0
        var e = ExportProgressEstimator(totalMessages: 10, totalImages: 2, now: { now })
        for _ in 0..<5 { e.messageCompleted() }
        e.imageCompleted()
        XCTAssertEqual(e.snapshot.fraction, (5.0 + 3.0) / 16.0, accuracy: 0.0001)
        XCTAssertEqual(e.snapshot.processedMessages, 5)
        XCTAssertEqual(e.snapshot.processedImages, 1)
    }

    func testEstimateAppearsAfterTenPercent() throws {
        var now: TimeInterval = 0
        var e = ExportProgressEstimator(totalMessages: 100, totalImages: 0, now: { now })
        for _ in 0..<5 { e.messageCompleted() }
        now = 10
        XCTAssertNil(e.snapshot.estimatedRemaining)

        now = 20
        for _ in 0..<45 { e.messageCompleted() }
        let remaining = try XCTUnwrap(e.snapshot.estimatedRemaining)
        XCTAssertEqual(remaining, 20, accuracy: 1.0)
    }

    func testFractionNeverExceedsOne() {
        var e = ExportProgressEstimator(totalMessages: 2, totalImages: 0)
        for _ in 0..<5 { e.messageCompleted() }
        XCTAssertEqual(e.snapshot.fraction, 1.0, accuracy: 0.0001)
    }
}
