import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import ChronicleCore

/// 通过 NSWorkspace 跟踪前台应用使用时长，空闲时自动暂停。
@MainActor
final class AppUsageTracker: ObservableObject {
    @Published private(set) var liveUsage: [AppUsageRecord] = []
    @Published private(set) var activeAppName: String?
    @Published private(set) var activeSince: Date?
    @Published private(set) var isIdle = false
    @Published private(set) var todayTotal: TimeInterval = 0

    private let store: ChronicleStore
    private var current: AppUsageRecord?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var dayStart = Calendar.current.startOfDay(for: Date())
    private var lastTitleRefresh = Date.distantPast

    private let idleThreshold: TimeInterval = 120

    init(store: ChronicleStore) {
        self.store = store
    }

    func start() {
        guard !started else { return }
        started = true
        dayStart = Calendar.current.startOfDay(for: Date())
        liveUsage = store.usage(from: dayStart, to: dayStart.addingTimeInterval(86400))
        refreshTotal()

        // 不在这里弹系统授权：没有辅助功能权限时只是拿不到窗口标题，
        // 由界面上的提示条引导用户主动授权，避免每次启动都弹窗。

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in self?.begin(app) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.suspendTracking() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeTracking() }
        })

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            begin(app)
        }
    }

    func stop() {
        guard started else { return }
        closeCurrent()
        ticker?.invalidate()
        ticker = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        started = false
    }

    private func begin(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "未知应用"
        let bundleID = app.bundleIdentifier ?? name

        if let current, current.bundleID == bundleID {
            return
        }
        closeCurrent()
        isIdle = false

        let record = AppUsageRecord(
            bundleID: bundleID,
            appName: name,
            start: Date(),
            end: Date(),
            windowTitle: Self.windowTitle(for: app.processIdentifier)
        )
        lastTitleRefresh = Date()
        current = record
        liveUsage.append(record)
        activeAppName = name
        activeSince = record.start
        refreshTotal()
    }

    /// 读取指定进程最前面的窗口标题：优先辅助功能接口，其次 CGWindowList（需要屏幕录制权限）。
    private static func windowTitle(for pid: pid_t) -> String? {
        if let title = focusedWindowTitle(for: pid) {
            return title
        }
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windows {
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  owner == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let title = window[kCGWindowName as String] as? String,
                  !title.isEmpty else { continue }
            return title
        }
        return nil
    }

    private static func focusedWindowTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String,
              !title.isEmpty else { return nil }
        return title
    }

    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        if !calendar.isDate(now, inSameDayAs: dayStart) {
            closeCurrent()
            dayStart = calendar.startOfDay(for: now)
            liveUsage = []
            if let app = NSWorkspace.shared.frontmostApplication {
                begin(app)
            }
            return
        }

        if idleSeconds() > idleThreshold {
            if current != nil {
                closeCurrent()
                isIdle = true
                activeAppName = nil
                activeSince = nil
            }
        } else if isIdle {
            isIdle = false
            if let app = NSWorkspace.shared.frontmostApplication {
                begin(app)
            }
        }

        if let record = current, let index = liveUsage.lastIndex(where: { $0.id == record.id }) {
            liveUsage[index].end = now
            current?.end = now

            if now.timeIntervalSince(lastTitleRefresh) >= 2 {
                lastTitleRefresh = now
                if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                   let title = Self.windowTitle(for: pid) {
                    current?.windowTitle = title
                    liveUsage[index].windowTitle = title
                }
            }
            refreshTotal()
        } else if current == nil, !isIdle, let app = NSWorkspace.shared.frontmostApplication {
            begin(app)
        }
    }

    private func idleSeconds() -> TimeInterval {
        let anyInput = CGEventType(rawValue: UInt32.max)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func suspendTracking() {
        closeCurrent()
    }

    private func resumeTracking() {
        if let app = NSWorkspace.shared.frontmostApplication {
            begin(app)
        }
    }

    private func closeCurrent() {
        if let record = current {
            store.recordUsage(record)
        }
        current = nil
        activeAppName = nil
        activeSince = nil
        refreshTotal()
    }

    private func refreshTotal() {
        let now = Date()
        let dayEnd = dayStart.addingTimeInterval(86400)
        todayTotal = liveUsage.reduce(0) { result, record in
            let start = max(record.start, dayStart)
            let end = min(record.end, min(now, dayEnd))
            return result + max(0, end.timeIntervalSince(start))
        }
    }
}
