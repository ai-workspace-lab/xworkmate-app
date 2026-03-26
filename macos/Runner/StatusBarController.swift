import Cocoa
import Combine

final class StatusBarController: NSObject {
  private let viewModel: AppStatusViewModel
  private let openAppHandler: () -> Void
  private let quitAndPauseHandler: () -> Void

  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()
  private let tasksMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let openAppMenuItem = NSMenuItem(title: "Open App", action: nil, keyEquivalent: "")
  private let quitMenuItem = NSMenuItem(title: "退出并暂停任务", action: nil, keyEquivalent: "")

  private var cancellables = Set<AnyCancellable>()

  init(
    viewModel: AppStatusViewModel,
    openAppHandler: @escaping () -> Void,
    quitAndPauseHandler: @escaping () -> Void
  ) {
    self.viewModel = viewModel
    self.openAppHandler = openAppHandler
    self.quitAndPauseHandler = quitAndPauseHandler
    super.init()

    setUpMenu()
    bindViewModel()
    render(snapshot: viewModel.snapshot)
  }

  private func setUpMenu() {
    tasksMenuItem.isEnabled = false
    statusMenuItem.isEnabled = false

    openAppMenuItem.target = self
    openAppMenuItem.action = #selector(openAppAction(_:))

    quitMenuItem.target = self
    quitMenuItem.action = #selector(quitAndPauseAction(_:))

    menu.addItem(tasksMenuItem)
    menu.addItem(statusMenuItem)
    menu.addItem(.separator())
    menu.addItem(openAppMenuItem)
    menu.addItem(.separator())
    menu.addItem(quitMenuItem)

    statusItem.menu = menu
    statusItem.button?.toolTip = "XWorkmate"
  }

  private func bindViewModel() {
    viewModel.$snapshot
      .receive(on: RunLoop.main)
      .sink { [weak self] snapshot in
        self?.render(snapshot: snapshot)
      }
      .store(in: &cancellables)
  }

  private func render(snapshot: AppStatusSnapshot) {
    tasksMenuItem.title = snapshot.menuTaskSummary
    statusMenuItem.title = snapshot.menuStatusSummary
    updateStatusButton(snapshot: snapshot)
  }

  private func updateStatusButton(snapshot: AppStatusSnapshot) {
    guard let button = statusItem.button else {
      return
    }
    button.title = snapshot.buttonBadgeText
    button.toolTip = """
    \(snapshot.connectionLabel)
    运行: \(snapshot.runningTasks)
    暂停: \(snapshot.pausedTasks)
    超时: \(snapshot.timedOutTasks)
    """

    if #available(macOS 11.0, *) {
      let symbolName = buttonSymbolName(for: snapshot)
      let image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: snapshot.connectionLabel
      )
      image?.isTemplate = true
      button.image = image
    } else {
      button.image = nil
      button.title = fallbackPrefix(for: snapshot) + snapshot.buttonBadgeText
    }
  }

  private func buttonSymbolName(for snapshot: AppStatusSnapshot) -> String {
    if snapshot.runningTasks > 0 && snapshot.connectionState == .connected {
      return "bolt.horizontal.circle.fill"
    }
    if snapshot.timedOutTasks > 0 || snapshot.connectionState == .error {
      return "exclamationmark.triangle.fill"
    }
    return snapshot.connectionState.symbolName
  }

  private func fallbackPrefix(for snapshot: AppStatusSnapshot) -> String {
    switch snapshot.connectionState {
    case .connected:
      return "[C]"
    case .connecting:
      return "[~]"
    case .disconnected:
      return "[D]"
    case .error:
      return "[!]"
    }
  }

  @objc private func openAppAction(_ sender: Any?) {
    openAppHandler()
  }

  @objc private func quitAndPauseAction(_ sender: Any?) {
    quitAndPauseHandler()
  }
}
