import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testExcludeFromBackupCreatesDirectoryAndSetsFlag() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("backup-exclusion-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent(
      BackupExclusion.workspaceDirectoryName,
      isDirectory: true
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    XCTAssertTrue(BackupExclusion.excludeFromBackup(at: target))

    var isDirectory: ObjCBool = false
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
    )
    XCTAssertTrue(isDirectory.boolValue)
    let values = try target.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  func testExcludeFromBackupIsIdempotentForExistingDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("backup-exclusion-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent(
      BackupExclusion.workspaceDirectoryName,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let marker = target.appendingPathComponent("existing-artifact.txt")
    try "artifact".write(to: marker, atomically: true, encoding: .utf8)

    XCTAssertTrue(BackupExclusion.excludeFromBackup(at: target))
    XCTAssertTrue(BackupExclusion.excludeFromBackup(at: target))

    // 已有内容不能因为打标记而丢失。
    XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "artifact")
    let values = try target.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

}
