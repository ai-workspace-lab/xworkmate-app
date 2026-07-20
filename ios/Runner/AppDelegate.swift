import Flutter
import UIKit

/// iOS Data Storage Guidelines: 线程工作区里的制品都能从 bridge 重新拉取，
/// 不应计入 iCloud/iTunes 备份，否则 Documents 会随制品增长撑大用户备份，
/// 这是 App Review 的经典驳回点。会话历史（Application Support 下的
/// threads.json）保持默认备份不受影响——重装后经 iCloud 恢复仍可找回。
/// 目录级排除覆盖整个子树，Dart 侧之后在该目录下新建的线程目录无需单独处理。
enum BackupExclusion {
  static let workspaceDirectoryName = ".xworkmate"

  @discardableResult
  static func excludeFromBackup(at url: URL) -> Bool {
    do {
      try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
      )
      var target = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try target.setResourceValues(values)
      return true
    } catch {
      NSLog("xworkmate: backup exclusion failed for \(url.path): \(error)")
      return false
    }
  }

  static func excludeThreadWorkspaces() {
    guard
      let documents = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      ).first
    else {
      return
    }
    excludeFromBackup(
      at: documents.appendingPathComponent(
        workspaceDirectoryName,
        isDirectory: true
      )
    )
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BackupExclusion.excludeThreadWorkspaces()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
