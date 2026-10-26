// Zomboid Server Monitor: a macOS menu-bar app that keeps the Workshop
// update watcher for a Project Zomboid dedicated server running, and shows
// the server's mod status.
//
// A launchd agent starts the app at login and restarts it if it exits. The app
// runs the configured watch command as a child process, restarts it if it
// dies, and shows the latest status file in the menu bar. Opening the app from
// /Applications while the agent is off turns it back on.
//
// All paths and commands come from Info.plist keys written by build.sh.

import AppKit

func setting(_ key: String) -> String? {
  Bundle.main.object(forInfoDictionaryKey: key) as? String
}

func commandSetting(_ key: String) -> [String] {
  guard let raw = setting(key), !raw.isEmpty else { return [] }
  // Arguments are separated by "|" so paths with spaces survive.
  return raw.components(separatedBy: "|")
}

func resolve(_ path: String) -> String {
  let expanded = NSString(string: path).expandingTildeInPath
  return expanded.hasPrefix("/") ? expanded : workDir + "/" + expanded
}

let appName = setting("CFBundleName") ?? "Zomboid Server Monitor"
let agentLabel = setting("WWAgentLabel") ?? "zomboid-server-monitor"
let workDir = NSString(string: setting("WWWorkDir") ?? "~").expandingTildeInPath
let watchCommand = commandSetting("WWWatchCommand")
let offCommand = commandSetting("WWOffCommand")
let logFile = resolve(setting("WWLogFile") ?? "zomboid-server-monitor.log")
let statusFile = setting("WWStatusFile").map(resolve)
let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
let launchedByLaunchd = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == agentLabel
let agentPlist = NSHomeDirectory() + "/Library/LaunchAgents/\(agentLabel).plist"
let uid = getuid()

func makeProcess(_ command: [String]) -> Process {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: command[0])
  p.arguments = Array(command.dropFirst())
  p.currentDirectoryURL = URL(fileURLWithPath: workDir)
  var env = ProcessInfo.processInfo.environment
  env["PATH"] = searchPath
  env.removeValue(forKey: "XPC_SERVICE_NAME")
  p.environment = env
  return p
}

@discardableResult
func run(_ command: [String]) -> (status: Int32, output: String) {
  guard !command.isEmpty else { return (1, "") }
  let p = makeProcess(command)
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = pipe
  do { try p.run() } catch { return (1, "Could not run \(command[0]): \(error.localizedDescription)") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func launchctl(_ args: String...) -> Int32 { run(["/bin/launchctl"] + args).status }

/// Optional JSON status written by the watcher:
/// { "checked_at": <unix s>, "server_running": bool,
///   "mods": [{ "title": str, "server": "current"|..., "local": "match"|"differs" }] }
struct Status {
  var checkedAt: Date?
  var serverRunning: Bool?
  var behind: [String] = []
  var notUploaded: [String] = []
  var hasMods = false

  static func load() -> Status {
    var s = Status()
    guard let path = statusFile, let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return s }
    if let t = json["checked_at"] as? Double { s.checkedAt = Date(timeIntervalSince1970: t) }
    s.serverRunning = json["server_running"] as? Bool
    if let mods = json["mods"] as? [[String: Any]] {
      s.hasMods = true
      for mod in mods {
        let name = (mod["title"] as? String) ?? (mod["project"] as? String) ?? (mod["id"] as? String ?? "?")
        if let state = mod["server"] as? String, state != "current" { s.behind.append("\(name) (\(state))") }
        if mod["local"] as? String == "differs" { s.notUploaded.append(name) }
      }
    }
    return s
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var statusItem: NSStatusItem?
  var child: Process?
  var stopping = false
  var sigterm: DispatchSourceSignal?

  func applicationDidFinishLaunching(_ note: Notification) {
    if !launchedByLaunchd {
      openedByHand()
      return
    }
    signal(SIGTERM, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    src.setEventHandler { [weak self] in self?.shutdown() }
    src.resume()
    sigterm = src

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    statusItem = item
    startChild()
    refreshIcon()
    Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshIcon() }
  }

  /// launchd owns the real instance. Turn the agent on and step aside.
  func openedByHand() {
    let domain = "gui/\(uid)"
    var message: String
    if FileManager.default.fileExists(atPath: agentPlist) {
      _ = launchctl("enable", "\(domain)/\(agentLabel)")
      if launchctl("print", "\(domain)/\(agentLabel)") != 0 {
        _ = launchctl("bootstrap", domain, agentPlist)
      }
      message = "\(appName) is on. It lives in your menu bar."
    } else {
      message = "The launch agent is not installed yet (\(agentPlist)). Run ./install-agent.sh from the project folder."
    }
    let alert = NSAlert()
    alert.messageText = appName
    alert.informativeText = message
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    NSApp.terminate(nil)
  }

  // MARK: watcher child process

  func startChild() {
    guard !stopping, !watchCommand.isEmpty else { return }
    let fm = FileManager.default
    try? fm.createDirectory(atPath: (logFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    if !fm.fileExists(atPath: logFile) { fm.createFile(atPath: logFile, contents: nil) }
    let log = FileHandle(forWritingAtPath: logFile)
    log?.seekToEndOfFile()
    let p = makeProcess(watchCommand)
    p.standardOutput = log
    p.standardError = log
    p.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, !self.stopping else { return }
        self.child = nil
        self.refreshIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { if self.child == nil { self.startChild() } }
      }
    }
    do {
      try p.run()
      child = p
    } catch {
      child = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.startChild() }
    }
  }

  func stopChild() {
    guard let c = child else { return }
    c.terminationHandler = nil
    if c.isRunning { c.terminate(); c.waitUntilExit() }
    child = nil
  }

  func shutdown() {
    stopping = true
    stopChild()
    exit(0)
  }

  // MARK: menu

  func refreshIcon() {
    guard let button = statusItem?.button else { return }
    let s = Status.load()
    let running = child?.isRunning == true
    let symbol = !running ? "exclamationmark.arrow.triangle.2.circlepath"
      : (s.behind.isEmpty && s.notUploaded.isEmpty) ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle"
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: appName)
    button.toolTip = "\(appName): " + (running ? "running" : "watcher not running")
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let s = Status.load()
    let running = child?.isRunning == true
    let fmt = DateFormatter()
    fmt.dateStyle = .none
    fmt.timeStyle = .short

    func info(_ text: String) {
      let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    func action(_ title: String, _ sel: Selector) {
      let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }

    info(running ? "Watcher: on, running" : "Watcher: on, restarting…")
    if let r = s.serverRunning { info("Server: " + (r ? "running" : "stopped")) }
    if let t = s.checkedAt { info("Last check: " + fmt.string(from: t)) }
    if s.hasMods {
      if s.behind.isEmpty && s.notUploaded.isEmpty { info("All items up to date") }
      for m in s.behind { info("⚠︎ Server copy behind: \(m)") }
      for m in s.notUploaded { info("⚠︎ Local changes not uploaded: \(m)") }
    }
    menu.addItem(.separator())
    action("Check Now", #selector(checkNow))
    action("Open Log", #selector(openLog))
    action("Open Project Folder", #selector(openFolder))
    menu.addItem(.separator())
    action("Turn Watcher Off…", #selector(turnOff))
  }

  /// Restarting the watch command makes it check right away.
  @objc func checkNow() {
    stopChild()
    startChild()
    refreshIcon()
  }

  @objc func openLog() {
    NSWorkspace.shared.open(
      [URL(fileURLWithPath: logFile)],
      withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
      configuration: NSWorkspace.OpenConfiguration())
  }

  @objc func openFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: workDir)) }

  @objc func turnOff() {
    let alert = NSAlert()
    alert.messageText = "Turn \(appName) off?"
    alert.informativeText = "It stays off, also after a reboot, until you open \(appName) from Applications again."
    alert.addButton(withTitle: "Turn Off")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    stopping = true
    stopChild()
    // Do not wait here: unloading the agent waits for this app to exit, and
    // the SIGTERM it sends ends the app through shutdown().
    let command = offCommand.isEmpty
      ? ["/bin/sh", "-c", "launchctl disable gui/\(uid)/\(agentLabel); launchctl bootout gui/\(uid)/\(agentLabel)"]
      : offCommand
    try? makeProcess(command).run()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    statusItem?.button?.performClick(nil)
    return false
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
