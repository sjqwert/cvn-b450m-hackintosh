// BrightnessBar — 菜单栏亮度控制（gamma 表调光）
// v1.1 修复：菜单打开期间不再改写状态栏标题（原实现会立刻关闭菜单，导致滑块拖不动）
import Cocoa
import CoreGraphics
import Carbon.HIToolbox

let kLevelKey = "bb.level"
let kMinLevel = 0.10
let kMaxLevel = 1.00

// MARK: - Gamma 引擎

final class GammaEngine {
    static let shared = GammaEngine()
    private var baseR: [CGGammaValue] = []
    private var baseG: [CGGammaValue] = []
    private var baseB: [CGGammaValue] = []
    private var count = 256
    private var applying = false
    private(set) var level: Double = 1.0

    private var display: CGDirectDisplayID { CGMainDisplayID() }

    /// 采集未调光基准。启动时先重置 ColorSync 再采集，避免多次启动叠加变暗。
    func resetAndCaptureBase() {
        CGDisplayRestoreColorSyncSettings()
        var r = [CGGammaValue](repeating: 0, count: 256)
        var g = [CGGammaValue](repeating: 0, count: 256)
        var b = [CGGammaValue](repeating: 0, count: 256)
        var n: UInt32 = 256
        let err = CGGetDisplayTransferByTable(display, 256, &r, &g, &b, &n)
        if err == .success, n > 2 {
            count = Int(n)
            baseR = Array(r.prefix(count))
            baseG = Array(g.prefix(count))
            baseB = Array(b.prefix(count))
        } else {
            count = 256
            let linear = (0..<256).map { CGGammaValue($0) / 255.0 }
            baseR = linear; baseG = linear; baseB = linear
        }
    }

    func apply(_ newLevel: Double) {
        level = min(kMaxLevel, max(kMinLevel, newLevel))
        guard baseR.count == count else { return }
        var r = [CGGammaValue](repeating: 0, count: count)
        var g = [CGGammaValue](repeating: 0, count: count)
        var b = [CGGammaValue](repeating: 0, count: count)
        let k = CGGammaValue(level)
        for i in 0..<count {
            r[i] = min(1.0, baseR[i] * k)
            g[i] = min(1.0, baseG[i] * k)
            b[i] = min(1.0, baseB[i] * k)
        }
        applying = true
        CGSetDisplayTransferByTable(display, UInt32(count), &r, &g, &b)
        applying = false
    }

    func reapply() {
        // 自己写 gamma 也会触发重配置回调，必须挡掉，否则会自激
        if applying { return }
        if baseR.isEmpty { resetAndCaptureBase() }
        apply(level)
    }

    func restore() {
        CGDisplayRestoreColorSyncSettings()
        level = 1.0
    }
}

// MARK: - 控制器

final class Controller: NSObject, NSMenuDelegate {
    static let shared = Controller()

    private var statusItem: NSStatusItem!
    private var slider: NSSlider!
    private var headerItem: NSMenuItem!
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var menuOpen = false

    func start() {
        GammaEngine.shared.resetAndCaptureBase()
        buildStatusItem()
        let saved = (UserDefaults.standard.object(forKey: kLevelKey) as? Double) ?? 1.0
        applyLevel(saved, persist: false)
        registerHotKeys()
        startCommandWatcher()
        // 不注册 CGDisplay 重配置回调：写 gamma 本身就会触发它，会自激。
        // 分辨率变化后若 gamma 被系统重置，拖一下滑块即可恢复。
    }

    /// 外部指令通道：命令行 `brightness set 70` 会写 ~/.brightnessbar.cmd，
    /// 这里轮询取走并施加。（分布式通知在本机实测收不到，故改用文件）
    private var cmdTimer: Timer?

    private func startCommandWatcher() {
        cmdTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            let path = NSHomeDirectory() + "/.brightnessbar.cmd"
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(atPath: path)
            let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
            Controller.shared.applyLevel(v > 1.0 ? v / 100.0 : v, persist: true)
        }
    }

    // MARK: UI

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "sun.max.fill",
                                accessibilityDescription: "亮度")
            btn.imagePosition = .imageLeft
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }

        let menu = NSMenu()
        menu.delegate = self

        headerItem = NSMenuItem(title: "亮度", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // 滑块：菜单打开期间不能改状态栏标题，否则 AppKit 会关掉菜单
        slider = NSSlider(value: 100, minValue: kMinLevel * 100, maxValue: kMaxLevel * 100,
                          target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 4, width: 220, height: 24)
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 244, height: 32))
        holder.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = holder
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        // 纯菜单项兜底：滑块万一失灵，这些一定能点
        let presets: [(String, Double)] = [
            ("恢复 100%（最亮）", 1.00),
            ("75%", 0.75),
            ("50%", 0.50),
            ("25%", 0.25),
            ("最暗 10%", 0.10)
        ]
        for (title, value) in presets {
            let it = NSMenuItem(title: title, action: #selector(applyPreset(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = value
            menu.addItem(it)
        }

        menu.addItem(.separator())
        let plus = NSMenuItem(title: "调亮 10%　⌃⌥↑", action: #selector(up), keyEquivalent: "")
        plus.target = self
        menu.addItem(plus)
        let minus = NSMenuItem(title: "调暗 10%　⌃⌥↓", action: #selector(down), keyEquivalent: "")
        minus.target = self
        menu.addItem(minus)

        menu.addItem(.separator())
        let launch = NSMenuItem(title: "开机自动运行", action: #selector(toggleLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LoginItem.isEnabled ? .on : .off
        launch.tag = 900
        menu.addItem(launch)

        let quit = NSMenuItem(title: "退出（会恢复满亮度）", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        refreshTitle()
    }

    // MARK: 行为

    @objc private func sliderChanged(_ sender: NSSlider) {
        applyLevel(sender.doubleValue / 100.0, persist: true)
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        applyLevel(v, persist: true)
    }

    @objc func up() { applyLevel(GammaEngine.shared.level + 0.10, persist: true) }
    @objc func down() { applyLevel(GammaEngine.shared.level - 0.10, persist: true) }

    @objc private func toggleLogin() {
        LoginItem.toggle()
        if let it = statusItem.menu?.item(withTag: 900) {
            it.state = LoginItem.isEnabled ? .on : .off
        }
    }

    @objc private func quit() {
        GammaEngine.shared.restore()
        UserDefaults.standard.set(1.0, forKey: kLevelKey)
        NSApp.terminate(nil)
    }

    private func applyLevel(_ v: Double, persist: Bool) {
        let lv = min(kMaxLevel, max(kMinLevel, v))
        GammaEngine.shared.apply(lv)
        if persist { UserDefaults.standard.set(lv, forKey: kLevelKey) }
        headerItem.title = "当前亮度 \(Int((lv * 100).rounded()))%"
        if let s = slider, abs(s.doubleValue - lv * 100) > 0.5 { s.doubleValue = lv * 100 }
        if !menuOpen { refreshTitle() }
    }

    private func refreshTitle() {
        let pct = Int((GammaEngine.shared.level * 100).rounded())
        statusItem.button?.title = " \(pct)%"
    }

    // MARK: 全局快捷键

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async {
                if hk.id == 1 { Controller.shared.up() }
                if hk.id == 2 { Controller.shared.down() }
            }
            return noErr
        }, 1, &spec, nil, nil)

        let mods = UInt32(controlKey | optionKey)
        for (idx, key) in [(1, UInt32(kVK_UpArrow)), (2, UInt32(kVK_DownArrow))] {
            var ref: EventHotKeyRef?
            let hid = EventHotKeyID(signature: OSType(0x42425221), id: UInt32(idx))
            RegisterEventHotKey(key, mods, hid, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }
}

// MARK: - 登录项

enum LoginItem {
    static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/local.brightnessbar.plist"
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    static func toggle() {
        if isEnabled {
            try? FileManager.default.removeItem(atPath: plistPath)
        } else {
            let exe = Bundle.main.executablePath ?? "/Applications/BrightnessBar.app/Contents/MacOS/BrightnessBar"
            let plist: [String: Any] = [
                "Label": "local.brightnessbar",
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            try? FileManager.default.createDirectory(
                atPath: NSHomeDirectory() + "/Library/LaunchAgents",
                withIntermediateDirectories: true)
            (plist as NSDictionary).write(toFile: plistPath, atomically: true)
        }
    }
}

// MARK: - 入口

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        // 单实例保护：开机自启与手动打开同时发生时，只保留一个，避免两个进程抢 gamma
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.brightnessbar")
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        Controller.shared.start()
    }
    func applicationWillTerminate(_ note: Notification) {
        GammaEngine.shared.restore()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
