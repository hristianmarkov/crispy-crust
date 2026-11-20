import Foundation

public struct TaskSnapshot: Codable, Equatable {
  public let schemaVersion: Int
  public let bakeId: String
  public let stepId: String
  public let title: String
  public let action: String
  public let revision: Int
  public let dueAt: Date
  public let generatedAt: Date
  public func isStale(at now: Date) -> Bool { now.timeIntervalSince(generatedAt) > 15 * 60 }
  public static func decode(_ data: Data) throws -> TaskSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { value in
      let text = try value.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: text) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: text) else {
        throw DecodingError.dataCorrupted(.init(codingPath: value.codingPath, debugDescription: "Invalid UTC instant"))
      }
      return date
    }
    let value = try decoder.decode(TaskSnapshot.self, from: data)
    guard value.schemaVersion == 1, value.revision > 0,
      !value.bakeId.isEmpty, !value.stepId.isEmpty else { throw SnapshotError.invalid }
    return value
  }
}
public enum SnapshotError: Error { case invalid }

public struct CompanionAction: Codable {
  public let operationId: String
  public let bakeId: String
  public let stepId: String
  public let expectedRevision: Int
  public let type: String
  public init(task: TaskSnapshot, type: String = "acknowledge") {
    operationId = UUID().uuidString; bakeId = task.bakeId
    stepId = task.stepId; expectedRevision = task.revision; self.type = type
  }
}
