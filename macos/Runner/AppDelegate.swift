import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let skillDirectoryChannelName = "plus.svc.xworkmate/skill_directory_access"
  private var directoryAccessSessions: [String: URL] = [:]
  private var skillDirectoryChannel: FlutterMethodChannel?
  private var skillDirectoryMessengerId: ObjectIdentifier?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    registerSkillDirectoryChannel(for: controller)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    for (_, url) in directoryAccessSessions {
      url.stopAccessingSecurityScopedResource()
    }
    directoryAccessSessions.removeAll()
    super.applicationWillTerminate(notification)
  }

  func registerSkillDirectoryChannel(for controller: FlutterViewController) {
    let messengerObject = controller.engine.binaryMessenger as AnyObject
    let messengerId = ObjectIdentifier(messengerObject)
    if skillDirectoryMessengerId == messengerId {
      return
    }
    let channel = FlutterMethodChannel(
      name: skillDirectoryChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleSkillDirectoryCall(call, result: result)
    }
    skillDirectoryChannel = channel
    skillDirectoryMessengerId = messengerId
  }

  private func handleSkillDirectoryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "resolveUserHomeDirectory":
      result(resolveUserHomeDirectoryPath())
    case "authorizeDirectory":
      authorizeDirectory(call, result: result)
    case "startDirectoryAccess":
      startDirectoryAccess(call, result: result)
    case "stopDirectoryAccess":
      stopDirectoryAccess(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func authorizeDirectory(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let suggestedPath = (arguments?["suggestedPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let panel = NSOpenPanel()
    panel.title = "授权技能目录"
    panel.message = "请选择要授予 XWorkmate 只读访问权限的技能目录。"
    panel.prompt = "授权"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.showsHiddenFiles = true
    if let initialURL = initialDirectoryURL(for: suggestedPath) {
      panel.directoryURL = initialURL
    }

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      result(nil)
      return
    }

    do {
      let resolvedURL = selectedURL.standardizedFileURL
      let bookmarkData = try resolvedURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      result([
        "path": resolvedURL.path,
        "bookmark": bookmarkData.base64EncodedString(),
      ])
    } catch {
      result(
        FlutterError(
          code: "bookmark_create_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func startDirectoryAccess(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let bookmark = (arguments?["bookmark"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bookmark.isEmpty, let bookmarkData = Data(base64Encoded: bookmark) else {
      result(
        FlutterError(
          code: "invalid_bookmark",
          message: "Missing directory bookmark.",
          details: nil
        )
      )
      return
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      guard url.startAccessingSecurityScopedResource() else {
        result(
          FlutterError(
            code: "directory_access_denied",
            message: "Failed to start security-scoped access.",
            details: nil
          )
        )
        return
      }

      let accessId = UUID().uuidString
      directoryAccessSessions[accessId] = url
      var payload: [String: Any] = [
        "accessId": accessId,
        "path": url.standardizedFileURL.path,
      ]
      if isStale,
         let refreshedBookmark = try? url.bookmarkData(
           options: [.withSecurityScope],
           includingResourceValuesForKeys: nil,
           relativeTo: nil
         ) {
        payload["bookmark"] = refreshedBookmark.base64EncodedString()
      }
      result(payload)
    } catch {
      result(
        FlutterError(
          code: "directory_access_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func stopDirectoryAccess(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let accessId = (arguments?["accessId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !accessId.isEmpty else {
      result(nil)
      return
    }
    if let url = directoryAccessSessions.removeValue(forKey: accessId) {
      url.stopAccessingSecurityScopedResource()
    }
    result(nil)
  }

  private func initialDirectoryURL(for suggestedPath: String) -> URL? {
    let trimmed = suggestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return URL(fileURLWithPath: resolveUserHomeDirectoryPath(), isDirectory: true)
    }

    var candidate = URL(fileURLWithPath: expandUserPath(trimmed))
    var isDirectory: ObjCBool = false
    while true {
      if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
        return isDirectory.boolValue ? candidate.deletingLastPathComponent() : candidate.deletingLastPathComponent()
      }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path || parent.path.isEmpty {
        break
      }
      candidate = parent
    }
    return URL(fileURLWithPath: resolveUserHomeDirectoryPath(), isDirectory: true)
  }

  private func expandUserPath(_ path: String) -> String {
    guard path.hasPrefix("~/") else {
      return path
    }
    let relative = String(path.dropFirst(2))
    return (resolveUserHomeDirectoryPath() as NSString).appendingPathComponent(relative)
  }

  private func resolveUserHomeDirectoryPath() -> String {
    if let directoryPointer = getpwuid(getuid())?.pointee.pw_dir {
      return String(cString: directoryPointer)
    }
    return FileManager.default.homeDirectoryForCurrentUser.path
  }
}
