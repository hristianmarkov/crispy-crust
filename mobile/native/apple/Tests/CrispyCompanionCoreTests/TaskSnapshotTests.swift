import XCTest
@testable import CrispyCompanionCore
final class TaskSnapshotTests: XCTestCase {
  func testDecodeAndStale() throws {
    let json = #"{"schemaVersion":1,"bakeId":"b1","stepId":"fold2","title":"Country loaf","action":"Check rise","revision":2,"dueAt":"2026-11-11T14:00:00.000Z","generatedAt":"2026-11-11T13:45:00Z"}"#
    let task = try TaskSnapshot.decode(Data(json.utf8))
    XCTAssertEqual(task.revision, 2)
    XCTAssertFalse(task.isStale(at: task.generatedAt))
    XCTAssertTrue(task.isStale(at: task.generatedAt.addingTimeInterval(901)))
    XCTAssertEqual(CompanionAction(task: task).expectedRevision, 2)
  }
  func testRejectUnsupportedSchema() {
    let json = #"{"schemaVersion":2,"bakeId":"b1","stepId":"fold2","title":"Country loaf","action":"Check rise","revision":2,"dueAt":"2026-11-11T14:00:00Z","generatedAt":"2026-11-11T13:45:00Z"}"#
    XCTAssertThrowsError(try TaskSnapshot.decode(Data(json.utf8)))
  }
}
