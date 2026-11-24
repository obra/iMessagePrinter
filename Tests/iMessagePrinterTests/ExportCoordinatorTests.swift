import XCTest
@testable import iMessagePrinter

final class ExportCoordinatorTests: XCTestCase {
    func testOnlyOneExportCanBegin() {
        let coordinator = ExportCoordinator()
        XCTAssertTrue(coordinator.begin())
        XCTAssertFalse(coordinator.begin())
        coordinator.end()
        XCTAssertTrue(coordinator.begin())
    }
}
