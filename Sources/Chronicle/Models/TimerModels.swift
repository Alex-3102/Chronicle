import Foundation
import AppKit

/// 临时计时：倒计时，结束自动记录。
@MainActor
final class TempTimerModel: ObservableObject {
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var isFinished = false
    @Published var projectID: String?
    @Published var infoText: String?

    let title = "临时计时"
    var onComplete: (@MainActor () -> Void)?

    static let presets = [5, 10, 15, 25, 45]

    private var ticker: Timer?
    private var deadline: Date?

    var elapsed: TimeInterval { max(0, duration - remaining) }
    var progress: Double { duration > 0 ? min(1, max(0, remaining / duration)) : 0 }

    func setPreset(minutes: Int) {
        guard !isRunning else { return }
        duration = TimeInterval(minutes * 60)
        remaining = duration
        isFinished = false
        infoText = nil
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if isFinished || remaining <= 0.5 {
            remaining = duration
            isFinished = false
            infoText = nil
        }
        guard duration > 0 else { return }
        isRunning = true
        deadline = Date().addingTimeInterval(remaining)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        infoText = "已暂停"
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        isRunning = false
        isFinished = false
        remaining = duration
        infoText = nil
    }

    func shutdown() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        isRunning = false
    }

    private func tick() {
        guard isRunning, let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining <= 0.05 {
            remaining = 0
            finish()
        }
    }

    private func finish() {
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        isFinished = true
        NSSound(named: NSSound.Name("Glass"))?.play()
        onComplete?()
    }
}

/// 开始定时器：正计时，停止时写入时间条目。
@MainActor
final class FocusUpTimerModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var projectID: String?
    @Published private(set) var title = ""

    private var startedAt: Date?

    func start(projectID: String?, title: String) {
        self.projectID = projectID
        self.title = title.isEmpty ? "专注记录" : title
        startedAt = Date()
        elapsed = 0
        isRunning = true
    }

    func tick() {
        guard isRunning, let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    func stop() -> (projectID: String?, title: String, start: Date, end: Date)? {
        guard isRunning, let startedAt else { return nil }
        let end = Date()
        isRunning = false
        self.startedAt = nil
        let session = (projectID: projectID, title: title, start: startedAt, end: end)
        elapsed = 0
        return session
    }
}
