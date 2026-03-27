import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private let skillDirectoryChannelName = "plus.svc.xworkmate/skill_directory_access"
  private let appLifecycleChannelName = "plus.svc.xworkmate/app_lifecycle"
  private let dockDisplayMode: DockDisplayMode = .regular
  private let statusProvider = FlutterAppStatusProvider()
  private var directoryAccessSessions: [String: URL] = [:]
  private var appLifecycleChannel: FlutterMethodChannel?
  private var appLifecycleMessengerId: ObjectIdentifier?
  private var skillDirectoryChannel: FlutterMethodChannel?
  private var skillDirectoryMessengerId: ObjectIdentifier?
  private lazy var statusViewModel = AppStatusViewModel(provider: statusProvider)
  private var statusBarController: StatusBarController?
  private var terminationInFlight = false
  private var terminationTimeoutWorkItem: DispatchWorkItem?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    applyDockDisplayMode()
    mainFlutterWindow?.delegate = self

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      registerApplicationChannels(for: controller)
    }
    setUpStatusBarController()
    statusViewModel.startRefreshing()
    DispatchQueue.main.async { [weak self] in
      self?.showMainWindow()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationInFlight else {
      return .terminateLater
    }
    terminationInFlight = true
    var hasReplied = false
    let finishTermination: () -> Void = { [weak self] in
      guard let self else {
        return
      }
      guard !hasReplied else {
        return
      }
      hasReplied = true
      self.terminationTimeoutWorkItem?.cancel()
      self.terminationTimeoutWorkItem = nil
      self.terminationInFlight = false
      sender.reply(toApplicationShouldTerminate: true)
    }

    let timeoutWorkItem = DispatchWorkItem(block: finishTermination)
    terminationTimeoutWorkItem = timeoutWorkItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timeoutWorkItem)
    statusViewModel.prepareForExit(completion: finishTermination)
    return .terminateLater
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showMainWindow()
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    statusViewModel.stopRefreshing()
    for (_, url) in directoryAccessSessions {
      url.stopAccessingSecurityScopedResource()
    }
    directoryAccessSessions.removeAll()
    super.applicationWillTerminate(notification)
  }

  func registerApplicationChannels(for controller: FlutterViewController) {
    registerAppLifecycleChannel(for: controller)
    registerSkillDirectoryChannel(for: controller)
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

  func registerAppLifecycleChannel(for controller: FlutterViewController) {
    let messengerObject = controller.engine.binaryMessenger as AnyObject
    let messengerId = ObjectIdentifier(messengerObject)
    if appLifecycleMessengerId == messengerId {
      return
    }
    appLifecycleChannel = FlutterMethodChannel(
      name: appLifecycleChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    appLifecycleMessengerId = messengerId
    statusViewModel.bind(channel: appLifecycleChannel)
  }

  private func setUpStatusBarController() {
    guard statusBarController == nil else {
      return
    }
    statusBarController = StatusBarController(
      viewModel: statusViewModel,
      openAppHandler: { [weak self] in
        self?.showMainWindow()
      },
      quitAndPauseHandler: { [weak self] in
        self?.requestTermination()
      }
    )
  }

  private func requestTermination() {
    NSApp.terminate(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    NSApp.hide(nil)
    return false
  }

  private func showMainWindow() {
    guard let window = mainFlutterWindow else {
      return
    }
    NSApp.unhide(nil)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func applyDockDisplayMode() {
    switch dockDisplayMode {
    case .regular:
      NSApp.setActivationPolicy(.regular)
    case .menuBarOnly:
      NSApp.setActivationPolicy(.accessory)
    }
  }

  private func handleSkillDirectoryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "resolveUserHomeDirectory":
      result(resolveUserHomeDirectoryPath())
    case "authorizeDirectory":
      authorizeDirectory(call, result: result)
    case "authorizeDirectories":
      authorizeDirectories(call, result: result)
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

    let panel = buildAuthorizationPanel(
      title: "授权技能目录",
      message: "请选择要授予 XWorkmate 只读访问权限的技能目录。",
      allowsMultipleSelection: false,
      suggestedPath: suggestedPath
    )
    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      result(nil)
      return
    }

    do {
      result(try authorizationPayload(for: selectedURL))
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

  private func authorizeDirectories(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let suggestedPaths = (arguments?["suggestedPaths"] as? [String] ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let panel = buildAuthorizationPanel(
      title: "批量授权技能目录",
      message: "请选择要授予 XWorkmate 只读访问权限的一个或多个技能目录。",
      allowsMultipleSelection: true,
      suggestedPath: suggestedPaths.first ?? ""
    )
    guard panel.runModal() == .OK else {
      result([])
      return
    }

    do {
      let payload = try panel.urls.map(authorizationPayload(for:))
      result(payload)
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

  private func buildAuthorizationPanel(
    title: String,
    message: String,
    allowsMultipleSelection: Bool,
    suggestedPath: String
  ) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.title = title
    panel.message = message
    panel.prompt = "授权"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = allowsMultipleSelection
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.showsHiddenFiles = true
    if let initialURL = initialDirectoryURL(for: suggestedPath) {
      panel.directoryURL = initialURL
    }
    return panel
  }

  private func authorizationPayload(for selectedURL: URL) throws -> [String: Any] {
    let resolvedURL = selectedURL.standardizedFileURL
    let bookmarkData = try resolvedURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return [
      "path": resolvedURL.path,
      "bookmark": bookmarkData.base64EncodedString(),
    ]
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
