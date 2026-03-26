import Combine
import Foundation
import FlutterMacOS

enum DockDisplayMode {
  case regular
  case menuBarOnly
}

enum MenuBarConnectionState: String {
  case connected
  case connecting
  case disconnected
  case error

  init(rawValue: String, fallbackLabel: String) {
    switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "connected":
      self = .connected
    case "connecting":
      self = .connecting
    case "error":
      self = .error
    case "disconnected":
      self = .disconnected
    default:
      self = fallbackLabel.lowercased().contains("connect")
        ? .connecting
        : .disconnected
    }
  }

  var symbolName: String {
    switch self {
    case .connected:
      return "checkmark.circle.fill"
    case .connecting:
      return "arrow.triangle.2.circlepath.circle"
    case .disconnected:
      return "xmark.circle"
    case .error:
      return "exclamationmark.triangle.fill"
    }
  }
}

struct AppStatusSnapshot {
  let connectionState: MenuBarConnectionState
  let connectionLabel: String
  let runningTasks: Int
  let pausedTasks: Int
  let timedOutTasks: Int
  let queuedTasks: Int
  let scheduledTasks: Int
  let failedTasks: Int
  let totalTasks: Int
  let badgeCount: Int

  init(
    connectionState: MenuBarConnectionState,
    connectionLabel: String,
    runningTasks: Int,
    pausedTasks: Int,
    timedOutTasks: Int,
    queuedTasks: Int,
    scheduledTasks: Int,
    failedTasks: Int,
    totalTasks: Int,
    badgeCount: Int
  ) {
    self.connectionState = connectionState
    self.connectionLabel = connectionLabel
    self.runningTasks = runningTasks
    self.pausedTasks = pausedTasks
    self.timedOutTasks = timedOutTasks
    self.queuedTasks = queuedTasks
    self.scheduledTasks = scheduledTasks
    self.failedTasks = failedTasks
    self.totalTasks = totalTasks
    self.badgeCount = badgeCount
  }

  static let unavailable = AppStatusSnapshot(
    connectionState: .disconnected,
    connectionLabel: "Disconnected",
    runningTasks: 0,
    pausedTasks: 0,
    timedOutTasks: 0,
    queuedTasks: 0,
    scheduledTasks: 0,
    failedTasks: 0,
    totalTasks: 0,
    badgeCount: 0
  )

  init(payload: [String: Any]) {
    let connectionLabel = (payload["connectionLabel"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let rawStatus = (payload["connectionStatus"] as? String) ?? ""
    self.connectionLabel = connectionLabel?.isEmpty == false ? connectionLabel! : "Disconnected"
    connectionState = MenuBarConnectionState(
      rawValue: rawStatus,
      fallbackLabel: self.connectionLabel
    )
    runningTasks = Self.intValue(payload["runningTasks"])
    pausedTasks = Self.intValue(payload["pausedTasks"])
    timedOutTasks = Self.intValue(payload["timedOutTasks"])
    queuedTasks = Self.intValue(payload["queuedTasks"])
    scheduledTasks = Self.intValue(payload["scheduledTasks"])
    failedTasks = Self.intValue(payload["failedTasks"])
    totalTasks = Self.intValue(payload["totalTasks"])
    let badgeCount = Self.intValue(payload["badgeCount"])
    self.badgeCount = badgeCount > 0 ? badgeCount : runningTasks + queuedTasks
  }

  var menuTaskSummary: String {
    "任务: 运行 \(runningTasks) | 暂停 \(pausedTasks) | 超时 \(timedOutTasks)"
  }

  var menuStatusSummary: String {
    "当前状态: \(connectionLabel)"
  }

  var buttonBadgeText: String {
    badgeCount > 0 ? " \(badgeCount)" : ""
  }

  private static func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let value = value as? Int {
      return value
    }
    if let value = value as? Double {
      return Int(value)
    }
    if let value = value as? String, let parsed = Int(value) {
      return parsed
    }
    return 0
  }
}

protocol AppStatusSnapshotProviding: AnyObject {
  func bind(channel: FlutterMethodChannel?)
  func fetchSnapshot(completion: @escaping (AppStatusSnapshot) -> Void)
  func prepareForExit(completion: @escaping () -> Void)
}

final class FlutterAppStatusProvider: AppStatusSnapshotProviding {
  private weak var channel: FlutterMethodChannel?

  func bind(channel: FlutterMethodChannel?) {
    self.channel = channel
  }

  func fetchSnapshot(completion: @escaping (AppStatusSnapshot) -> Void) {
    guard let channel else {
      completion(.unavailable)
      return
    }
    channel.invokeMethod("desktopStatusSnapshot", arguments: nil) { result in
      guard let payload = result as? [String: Any] else {
        completion(.unavailable)
        return
      }
      completion(AppStatusSnapshot(payload: payload))
    }
  }

  func prepareForExit(completion: @escaping () -> Void) {
    guard let channel else {
      completion()
      return
    }
    channel.invokeMethod("prepareForExit", arguments: nil) { _ in
      completion()
    }
  }
}

final class AppStatusViewModel: ObservableObject {
  @Published var snapshot: AppStatusSnapshot = .unavailable

  private let provider: AppStatusSnapshotProviding
  private let refreshInterval: TimeInterval
  private var refreshCancellable: AnyCancellable?

  init(
    provider: AppStatusSnapshotProviding,
    refreshInterval: TimeInterval = 5
  ) {
    self.provider = provider
    self.refreshInterval = refreshInterval
  }

  func bind(channel: FlutterMethodChannel?) {
    provider.bind(channel: channel)
    refreshNow()
  }

  func startRefreshing() {
    guard refreshCancellable == nil else {
      return
    }
    refreshNow()
    refreshCancellable = Timer.publish(
      every: refreshInterval,
      on: .main,
      in: .common
    )
    .autoconnect()
    .sink { [weak self] _ in
      self?.refreshNow()
    }
  }

  func stopRefreshing() {
    refreshCancellable?.cancel()
    refreshCancellable = nil
  }

  func refreshNow() {
    provider.fetchSnapshot { [weak self] snapshot in
      DispatchQueue.main.async {
        self?.snapshot = snapshot
      }
    }
  }

  func prepareForExit(completion: @escaping () -> Void) {
    provider.prepareForExit(completion: completion)
  }

  func applyRemoteSnapshot(_ snapshot: AppStatusSnapshot) {
    DispatchQueue.main.async {
      self.snapshot = snapshot
    }
  }
}
