import SwiftUI
import Combine
import AppKit
import ApplicationServices
import ChronicleCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case activity
    case stats
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "活动"
        case .stats: return "统计"
        case .reports: return "报告"
        }
    }

    var icon: String {
        switch self {
        case .activity: return "scope"
        case .stats: return "chart.bar"
        case .reports: return "doc.text"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let store: ChronicleStore
    let tracker: AppUsageTracker
    let tempTimer = TempTimerModel()
    let focusTimer = FocusUpTimerModel()
    /// 活动明细树的展开 / 选中状态，放在视图外面避免重建时丢失。
    let activityViewState = ActivityViewState()

    private var trackerCancellable: AnyCancellable?

    @Published var projects: [Project] = []
    @Published var projectTotals: [String: TimeInterval] = [:]
    @Published var section: SidebarSection = .activity
    @Published var selectedProjectID: String?
    @Published var unassignedOnly = false
    @Published var selectedDay = Calendar.current.startOfDay(for: Date())
    @Published var entries: [TimeEntry] = []
    @Published var usage: [AppUsageRecord] = []
    @Published var projectSearch = ""
    @Published var globalSearch = ""
    @Published var showGlobalSearch = false
    @Published var collapsedGroups: Set<String> = []
    @Published var now = Date()

    @Published var showArchived = false
    @Published var appearance: AppearanceMode = .system
    @Published var timelineMaxZoom: Double = 8
    @Published var timelineZoom: Double = 1
    @Published var timelineOrientation: TimelineOrientation = .horizontal
    /// 工作时段（分钟数），时间轴默认只展示这一段。
    @Published var workdayStartMinutes = 8 * 60
    @Published var workdayEndMinutes = 18 * 60
    @Published var timelineZoomToWorkHours = true

    /// 辅助功能权限：只用于读取前台窗口标题，未授权时其余记录照常。
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    @Published var accessibilityNoticeDismissed = false

    @Published var newEntryPresented = false
    @Published var editingEntry: TimeEntry?
    /// 双击空白处新建条目时预填的时间范围。
    @Published var newEntryDraftRange: DateInterval?
    /// 时间轴上当前选中的条目。
    @Published var selectedEntryID: String?
    /// 空白处拖拽出的时间筛选范围。
    @Published var timelineSelection: DateInterval?
    @Published var newProjectPresented = false
    @Published var newProjectParentID: String?
    @Published var editingProject: Project?
    @Published var startTimerPresented = false
    @Published var settingsPresented = false

    private var pinyinIndex = PinyinIndex()
    private var servicesStarted = false
    private var focusTicker: Timer?
    private var clockTicker: Timer?
    private var accessibilityTicker: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// 条目 / 应用数据每次整体重载后递增，用于共享快照的缓存键。
    private var dataRevision = 0
    private var accountingCache: (key: String, snapshot: AccountingSnapshot)?

    lazy var tempWindow = TempTimerWindowController(appState: self)

    init() {
        let store: ChronicleStore
        do {
            store = try ChronicleStore(path: ChronicleStore.defaultPath())
        } catch {
            NSLog("Chronicle: 无法打开数据库 \(error)")
            store = try! ChronicleStore(path: ":memory:")
        }
        self.store = store
        self.tracker = AppUsageTracker(store: store)

        store.seedIfNeeded()
        if let raw = store.setting("appearance"), let mode = AppearanceMode(rawValue: raw) {
            appearance = mode
        }
        if let raw = store.setting("timelineMaxZoom"), let value = Double(raw) {
            timelineMaxZoom = min(24, max(1, value))
        }
        if let raw = store.setting("timelineOrientation"), let value = TimelineOrientation(rawValue: raw) {
            timelineOrientation = value
        }
        if let raw = store.setting("workdayStartMinutes"), let value = Int(raw) {
            workdayStartMinutes = min(23 * 60, max(0, value))
        }
        if let raw = store.setting("workdayEndMinutes"), let value = Int(raw) {
            workdayEndMinutes = min(24 * 60, max(60, value))
        }
        if let raw = store.setting("timelineZoomToWorkHours") {
            timelineZoomToWorkHours = raw == "1"
        }
        refreshProjects()
        reload()
        // tracker 是独立的 ObservableObject，把它的变化转发给 AppState，
        // 这样只观察 AppState 的视图（时间轴、所有活动列表）也能实时刷新。
        trackerCancellable = tracker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        tempTimer.onComplete = { [weak self] in
            self?.handleTempTimerComplete()
        }
    }

    // MARK: - 设置

    func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        store.setSetting("appearance", mode.rawValue)
        applyAppearance()
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    func setTimelineMaxZoom(_ value: Double) {
        timelineMaxZoom = min(24, max(1, value))
        store.setSetting("timelineMaxZoom", String(timelineMaxZoom))
        if timelineZoom > timelineMaxZoom {
            setTimelineZoom(timelineMaxZoom)
        }
    }

    func setTimelineZoom(_ value: Double) {
        timelineZoom = min(timelineMaxZoom, max(1, value))
    }

    func adjustTimelineZoom(by factor: Double) {
        setTimelineZoom(timelineZoom * factor)
    }

    func setTimelineOrientation(_ value: TimelineOrientation) {
        guard timelineOrientation != value else { return }
        timelineOrientation = value
        store.setSetting("timelineOrientation", value.rawValue)
    }

    func toggleTimelineOrientation() {
        setTimelineOrientation(timelineOrientation.isHorizontal ? .vertical : .horizontal)
    }

    // MARK: - 生命周期

    func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        applyAppearance()
        tracker.start()

        focusTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.focusTimer.tick() }
        }
        clockTicker = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.shutdown() }
        }
        // 从系统设置授权回来时刷新状态，提示条随之消失。
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibility() }
        }
        // 未授权时每 2 秒复查一次：用户在系统设置里打开开关后，提示条不用等下次激活就会消失。
        accessibilityTicker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.accessibilityTrusted else { return }
                self.refreshAccessibility()
            }
        }
    }

    // MARK: - 辅助功能权限

    func refreshAccessibility() {
        let trusted = AXIsProcessTrusted() || canReadAccessibility()
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
        }
    }

    /// `AXIsProcessTrusted()` 有时在系统设置里已放行的情况下仍返回 false（授权后没重启的进程）。
    /// 再实际读一次系统级辅助功能属性，确认是真的能拿到数据。
    private func canReadAccessibility() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        return result == .success
    }

    /// 用户主动点击「去授权」时才弹系统授权窗口（会同时打开系统设置）。
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibility()
    }

    /// 选择「不再提醒」只对本次运行有效，下次启动仍会提示。
    func dismissAccessibilityNotice() {
        accessibilityNoticeDismissed = true
    }

    /// 在设置里重新显示提示区域。
    func restoreAccessibilityNotice() {
        accessibilityNoticeDismissed = false
    }

    func shutdown() {
        if let session = focusTimer.stop() {
            store.addEntry(TimeEntry(
                projectID: session.projectID,
                title: session.title,
                note: "定时器",
                start: session.start,
                end: session.end,
                source: .timer
            ))
        }
        tracker.stop()
        tempTimer.shutdown()
        focusTicker?.invalidate()
        clockTicker?.invalidate()
        accessibilityTicker?.invalidate()
    }

    // MARK: - 数据加载

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDay)
    }

    var dayInterval: DateInterval {
        let start = Calendar.current.startOfDay(for: selectedDay)
        return DateInterval(start: start, duration: 24 * 60 * 60)
    }

    /// 时间轴实际展示范围：默认只显示工作时段，有记录超出时向外扩展到整点。
    var timelineRange: DateInterval {
        let day = dayInterval
        guard timelineZoomToWorkHours else { return day }
        let calendar = Calendar.current
        var start = calendar.date(byAdding: .minute, value: workdayStartMinutes, to: day.start) ?? day.start
        var end = calendar.date(byAdding: .minute, value: workdayEndMinutes, to: day.start) ?? day.end
        if end <= start { end = start.addingTimeInterval(3600) }

        let slices = accounting.slices
        if let first = slices.first?.start, first < start {
            start = calendar.dateInterval(of: .hour, for: first)?.start ?? first
        }
        if let last = slices.last?.end, last > end {
            end = calendar.dateInterval(of: .hour, for: last.addingTimeInterval(-1))?.end ?? last
        }
        start = max(start, day.start)
        end = min(end, day.end)
        return DateInterval(start: start, end: end)
    }

    func setWorkday(startMinutes: Int, endMinutes: Int) {
        workdayStartMinutes = min(23 * 60, max(0, startMinutes))
        workdayEndMinutes = min(24 * 60, max(workdayStartMinutes + 30, endMinutes))
        store.setSetting("workdayStartMinutes", String(workdayStartMinutes))
        store.setSetting("workdayEndMinutes", String(workdayEndMinutes))
    }

    func setTimelineZoomToWorkHours(_ enabled: Bool) {
        timelineZoomToWorkHours = enabled
        store.setSetting("timelineZoomToWorkHours", enabled ? "1" : "0")
    }

    func reload() {
        let interval = dayInterval
        entries = store.entries(from: interval.start, to: interval.end)
        usage = store.usage(from: interval.start, to: interval.end)
        projectTotals = store.projectTotals(from: interval.start, to: interval.end)
        dataRevision &+= 1
        accountingCache = nil
    }

    func refreshProjects() {
        projects = store.loadProjects()

        var index = PinyinIndex()
        index.rebuild(store.projectSearchIndex())
        pinyinIndex = index

        if let id = selectedProjectID, !projects.contains(where: { $0.id == id }) {
            selectedProjectID = nil
        }
    }

    func moveDay(by days: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        reload()
    }

    func goToday() {
        selectedDay = Calendar.current.startOfDay(for: Date())
        reload()
    }

    // MARK: - 筛选

    var searchQuery: String {
        globalSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var filterDescription: String? {
        if unassignedOnly { return "未分配" }
        if let project = project(selectedProjectID) { return project.name }
        return nil
    }

    private var filterProjectIDs: Set<String>? {
        guard let id = selectedProjectID else { return nil }
        var ids: Set<String> = [id]
        func walk(_ parent: String) {
            for child in projects where child.parentID == parent {
                ids.insert(child.id)
                walk(child.id)
            }
        }
        walk(id)
        return ids
    }

    /// 时间轴专用：只按搜索过滤，不受当前选中项目影响，未选中的项目弱化展示而不是隐藏。
    var timelineEntries: [TimeEntry] {
        guard !searchQuery.isEmpty else { return entries }
        return entries.filter { entry in
            if entry.title.lowercased().contains(searchQuery) { return true }
            if entry.note.lowercased().contains(searchQuery) { return true }
            if let project = project(entry.projectID), project.name.lowercased().contains(searchQuery) {
                return true
            }
            return false
        }
    }

    /// 所有活动列表使用的条目：额外按时间轴框选范围过滤。
    var activityListEntries: [TimeEntry] {
        guard let selection = timelineSelection else { return timelineEntries }
        return timelineEntries.filter { $0.end > selection.start && $0.start < selection.end }
    }

    /// 所有活动列表使用的应用记录：额外按时间轴框选范围过滤。
    var activityListUsage: [AppUsageRecord] {
        guard let selection = timelineSelection else { return dayUsageRecords }
        return dayUsageRecords.filter { $0.end > selection.start && $0.start < selection.end }
    }

    /// 该条目是否落在当前所选项目范围内；用于时间轴上弱化其他项目。
    func isInSelection(_ entry: TimeEntry) -> Bool {
        guard !unassignedOnly else { return entry.projectID == nil }
        guard let ids = filterProjectIDs else { return true }
        guard let projectID = entry.projectID else { return false }
        return ids.contains(projectID)
    }

    /// 没有关联手动条目的应用活动是否落在当前筛选范围内。
    var isUnlinkedInSelection: Bool {
        unassignedOnly || selectedProjectID == nil
    }

    /// 从根到该项目的路径，例如 需求 › 国补 › 汽摩。
    func projectPath(_ id: String?) -> [Project] {
        guard let id else { return [] }
        var chain: [Project] = []
        var current = project(id)
        while let node = current {
            chain.insert(node, at: 0)
            current = node.parentID.flatMap { project($0) }
        }
        return chain
    }

    var filteredEntries: [TimeEntry] {
        var list = entries
        if unassignedOnly {
            list = list.filter { $0.projectID == nil }
        } else if let ids = filterProjectIDs {
            list = list.filter { entry in
                guard let projectID = entry.projectID else { return false }
                return ids.contains(projectID)
            }
        }
        if !searchQuery.isEmpty {
            list = list.filter { entry in
                if entry.title.lowercased().contains(searchQuery) { return true }
                if entry.note.lowercased().contains(searchQuery) { return true }
                if let project = project(entry.projectID), project.name.lowercased().contains(searchQuery) {
                    return true
                }
                return false
            }
        }
        return list
    }

    var dayUsageRecords: [AppUsageRecord] {
        let base = isToday ? tracker.liveUsage : usage
        guard !searchQuery.isEmpty else { return base }
        return base.filter {
            $0.appName.lowercased().contains(searchQuery) || $0.bundleID.lowercased().contains(searchQuery)
        }
    }

    var dayUsageTotals: [AppUsageTotal] {
        store.usageTotals(records: dayUsageRecords, from: dayInterval.start, to: dayInterval.end)
    }

    var hasAnyData: Bool {
        !entries.isEmpty || !dayUsageRecords.isEmpty
    }

    // MARK: - 汇总

    /// 条目落在当前所选日期内的时长（跨天条目按当天部分计算）
    func clampedDuration(_ entry: TimeEntry) -> TimeInterval {
        let interval = dayInterval
        let from = max(entry.start, interval.start)
        let to = min(entry.end, interval.end)
        return max(0, to.timeIntervalSince(from))
    }

    var allTotal: TimeInterval {
        accounting.total
    }

    /// 当天前台应用实际使用时长（合并重叠区间）
    var trackedTotal: TimeInterval {
        let intervals = accounting.slices.compactMap { slice -> DateInterval? in
            guard slice.activity != nil else { return nil }
            return DateInterval(start: slice.start, end: slice.end)
        }
        return TimeAccounting.unionDuration(intervals)
    }

    /// 未分配 = 切片总时长 − 已归入项目的时长
    var unassignedTotal: TimeInterval {
        max(0, accounting.total - assignedTotal)
    }

    var assignedTotal: TimeInterval {
        accounting.slices.reduce(0) { $0 + ($1.projectID == nil ? 0 : $1.duration) }
    }

    // MARK: - 统一时间快照

    /// 当天所有页面的唯一口径：应用活动 + 时间条目切成互不重叠的切片。
    var accounting: AccountingSnapshot {
        let interval = dayInterval
        let live = isToday ? tracker.liveUsage : usage
        let key = [
            String(interval.start.timeIntervalSince1970),
            String(dataRevision),
            String(entries.count),
            String(live.count),
            isToday ? String(Int(now.timeIntervalSince1970)) : "0"
        ].joined(separator: "|")
        if let cache = accountingCache, cache.key == key {
            return cache.snapshot
        }
        let snapshot = AccountingSnapshot.make(
            usage: live,
            entries: entries,
            range: interval,
            now: now
        )
        accountingCache = (key, snapshot)
        return snapshot
    }

    /// 把条目和应用记录一起分配到项目，供拖拽与右键菜单复用。
    func assignRecords(entryIDs: [String], activityIDs: [String] = [], to projectID: String?) {
        for id in entryIDs {
            guard var entry = entries.first(where: { $0.id == id }) else { continue }
            entry.projectID = projectID
            store.addEntry(entry)
        }
        store.assignUsage(ids: activityIDs, projectID: projectID)
        reload()
    }

    // MARK: - 当前筛选范围

    /// 当前选中项目及其所有子孙项目的 id。
    var selectionProjectIDs: Set<String> {
        guard !unassignedOnly, let id = selectedProjectID else { return [] }
        var ids: Set<String> = [id]
        var queue = [id]
        while let parent = queue.popLast() {
            for child in projects where child.parentID == parent && !ids.contains(child.id) {
                ids.insert(child.id)
                queue.append(child.id)
            }
        }
        return ids
    }

    /// 按当前筛选过滤后的条目（选中项目时包含其子项目）。
    var scopedEntries: [TimeEntry] {
        if unassignedOnly {
            return entries.filter { $0.projectID == nil }
        }
        guard selectedProjectID != nil else { return entries }
        let ids = selectionProjectIDs
        return entries.filter { $0.projectID.map(ids.contains) ?? false }
    }

    var scopedTotal: TimeInterval {
        scopedEntries.reduce(0) { $0 + clampedDuration($1) }
    }

    /// 选中条目落在当天的时间区间。
    var scopedEntryRanges: [DateInterval] {
        scopedEntries.compactMap { entry in
            let from = max(entry.start, dayInterval.start)
            let to = min(entry.end, dayInterval.end)
            return to > from ? DateInterval(start: from, end: to) : nil
        }
    }

    /// 选中范围内的应用使用时长：只统计落在这些条目时间区间内的部分。
    var scopedUsageTotals: [AppUsageTotal] {
        guard unassignedOnly || selectedProjectID != nil else { return dayUsageTotals }
        let ranges = scopedEntryRanges
        guard !ranges.isEmpty else { return [] }
        var perBundle: [String: (name: String, seconds: TimeInterval)] = [:]
        for record in dayUsageRecords {
            var seconds: TimeInterval = 0
            for range in ranges {
                seconds += max(0, min(record.end, range.end).timeIntervalSince(max(record.start, range.start)))
            }
            guard seconds > 0 else { continue }
            let current = perBundle[record.bundleID] ?? (record.appName, 0)
            perBundle[record.bundleID] = (current.name, current.seconds + seconds)
        }
        return perBundle
            .map { AppUsageTotal(bundleID: $0.key, appName: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// 当前筛选的展示名称：nil 表示「全部活动」。
    var scopeName: String? {
        if unassignedOnly { return "未分配" }
        guard let id = selectedProjectID else { return nil }
        return project(id)?.name
    }

    func aggregateTotal(for projectID: String) -> TimeInterval {
        var total = projectTotals[projectID] ?? 0
        for child in projects where child.parentID == projectID {
            total += aggregateTotal(for: child.id)
        }
        return total
    }

    func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func color(for projectID: String?) -> Color {
        guard let project = project(projectID) else { return Theme.tertiary }
        return Color(hexString: project.colorHex)
    }

    // MARK: - 项目树

    private func sortProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.name < rhs.name
    }

    var treeProjects: [Project] {
        projects.filter { $0.parentID == nil }.sorted(by: sortProjects)
    }

    func children(of id: String) -> [Project] {
        projects.filter { $0.parentID == id }.sorted(by: sortProjects)
    }

    var flatTree: [Project] {
        var result: [Project] = []
        func walk(_ parent: String?) {
            for project in projects.filter({ $0.parentID == parent }).sorted(by: sortProjects) {
                result.append(project)
                walk(project.id)
            }
        }
        walk(nil)
        return result
    }

    func depth(of project: Project) -> Int {
        var depth = 0
        var parentID = project.parentID
        while let id = parentID, let parent = projects.first(where: { $0.id == id }) {
            depth += 1
            parentID = parent.parentID
        }
        return depth
    }

    /// 自身或任一祖先被归档
    func isArchived(_ project: Project) -> Bool {
        var current: Project? = project
        while let node = current {
            if node.isArchived { return true }
            guard let parentID = node.parentID else { return false }
            current = self.project(parentID)
        }
        return false
    }

    func isVisible(_ project: Project) -> Bool {
        if !showArchived && isArchived(project) { return false }
        return true
    }

    func sidebarChildren(of parentID: String?) -> [Project] {
        projects
            .filter { $0.parentID == parentID && isVisible($0) }
            .sorted(by: sortProjects)
    }

    func sidebarRows() -> [(project: Project, depth: Int)] {
        let query = projectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return searchProjects(query).map { ($0, depth(of: $0)) }
        }
        var rows: [(Project, Int)] = []
        func walk(_ parent: String?, depth: Int) {
            for project in sidebarChildren(of: parent) {
                rows.append((project, depth))
                if !collapsedGroups.contains(project.id) {
                    walk(project.id, depth: depth + 1)
                }
            }
        }
        walk(nil, depth: 0)
        return rows
    }

    // MARK: - 键盘操作

    /// ↑↓：在当前可见的项目之间移动选择。
    func moveSelection(by delta: Int) {
        let rows = sidebarRows().map(\.project)
        guard !rows.isEmpty else { return }
        guard let index = rows.firstIndex(where: { $0.id == selectedProjectID }) else {
            select(project: delta > 0 ? rows[0] : rows[rows.count - 1])
            return
        }
        let target = min(rows.count - 1, max(0, index + delta))
        guard target != index else { return }
        select(project: rows[target])
    }

    /// →：展开选中的项目。
    func expandSelectedProject() {
        guard let id = selectedProjectID,
              let project = project(id),
              !children(of: id).isEmpty,
              collapsedGroups.contains(id) else { return }
        toggleExpanded(project)
    }

    /// ←：折叠选中的项目。
    func collapseSelectedProject() {
        guard let id = selectedProjectID,
              let project = project(id),
              !children(of: id).isEmpty,
              !collapsedGroups.contains(id) else { return }
        toggleExpanded(project)
    }

    func searchProjects(_ query: String) -> [Project] {
        let keys = Set(pinyinIndex.search(query))
        guard !keys.isEmpty else { return [] }

        var visible = Set<String>()
        for project in projects where keys.contains(project.id) && !isArchived(project) {
            visible.insert(project.id)
            var parentID = project.parentID
            while let id = parentID, let parent = projects.first(where: { $0.id == id }) {
                visible.insert(parent.id)
                parentID = parent.parentID
            }
        }
        return flatTree.filter { visible.contains($0.id) }
    }

    /// 项目选择器用：搜索为空时返回完整树，否则只保留命中的项目（保持树的顺序）。
    func pickerProjects(matching query: String) -> [Project] {
        let tree = flatTree.filter { !isArchived($0) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return tree }
        let keys = Set(pinyinIndex.search(trimmed))
        guard !keys.isEmpty else { return [] }
        return tree.filter { keys.contains($0.id) }
    }

    func toggleExpanded(_ project: Project) {
        if collapsedGroups.contains(project.id) {
            collapsedGroups.remove(project.id)
        } else {
            collapsedGroups.insert(project.id)
        }
    }

    // MARK: - 移动 / 归档

    func canMove(_ id: String, under parentID: String?) -> Bool {
        guard let parentID else { return true }
        if parentID == id { return false }
        var current: String? = parentID
        while let cur = current {
            if cur == id { return false }
            current = project(cur)?.parentID
        }
        return true
    }

    func moveProject(_ id: String, under parentID: String?, before beforeID: String? = nil, after afterID: String? = nil) {
        guard let moving = project(id), canMove(id, under: parentID) else { return }
        var siblings = projects
            .filter { $0.parentID == parentID && $0.id != id }
            .sorted(by: sortProjects)

        let index: Int
        if let beforeID, let position = siblings.firstIndex(where: { $0.id == beforeID }) {
            index = position
        } else if let afterID, let position = siblings.firstIndex(where: { $0.id == afterID }) {
            index = position + 1
        } else {
            index = siblings.count
        }
        siblings.insert(moving, at: min(index, siblings.count))

        for (order, item) in siblings.enumerated() {
            let targetParent = item.id == id ? parentID : item.parentID
            if item.sortOrder != order || item.parentID != targetParent {
                store.setProjectParent(id: item.id, parentID: targetParent, sortOrder: order)
            }
        }
        if let parentID {
            collapsedGroups.remove(parentID)
        }
        refreshProjects()
    }

    func setArchived(_ project: Project, _ archived: Bool) {
        store.setProjectArchived(id: project.id, archived: archived)
        if archived, let selected = selectedProjectID, selected == project.id || isDescendant(selected, of: project.id) {
            selectedProjectID = nil
            unassignedOnly = false
        }
        refreshProjects()
        reload()
    }

    func isDescendant(_ id: String, of ancestorID: String) -> Bool {
        var current = project(id)?.parentID
        while let cur = current {
            if cur == ancestorID { return true }
            current = project(cur)?.parentID
        }
        return false
    }

    // MARK: - 选择

    func selectAllActivity() {
        unassignedOnly = false
        selectedProjectID = nil
    }

    func selectUnassigned() {
        unassignedOnly = true
        selectedProjectID = nil
    }

    /// 只是切换筛选，不改变当前所在的 tab（统计 / 报告里选中项目时留在原地）。
    func select(project: Project) {
        unassignedOnly = false
        selectedProjectID = project.id
    }

    // MARK: - 项目增删改

    func createProject(name: String, colorHex: String, isGroup: Bool, parentID: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let siblings = projects.filter { $0.parentID == parentID }
        let order = (siblings.map(\.sortOrder).max() ?? -1) + 1
        let project = Project(
            name: trimmed,
            colorHex: colorHex,
            parentID: parentID,
            isGroup: isGroup,
            sortOrder: order
        )
        store.upsertProject(project)
        refreshProjects()
        if let parentID {
            collapsedGroups.remove(parentID)
        }
        selectedProjectID = project.id
        unassignedOnly = false
    }

    func updateProject(_ project: Project) {
        var project = project
        if let parentID = project.parentID {
            if parentID == project.id || isDescendant(parentID, of: project.id) {
                project.parentID = self.project(project.id)?.parentID
            }
        }
        store.upsertProject(project)
        if project.isArchived, selectedProjectID == project.id {
            selectedProjectID = nil
            unassignedOnly = false
        }
        refreshProjects()
        reload()
    }

    func deleteProject(_ project: Project) {
        for child in children(of: project.id) {
            deleteProject(child)
        }
        store.deleteProject(id: project.id)
        if selectedProjectID == project.id {
            selectedProjectID = nil
            unassignedOnly = false
        }
        refreshProjects()
        reload()
    }

    // MARK: - 时间条目

    func addEntry(projectID: String?, title: String, note: String, start: Date, end: Date, source: EntrySource) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = TimeEntry(
            projectID: projectID,
            title: trimmed.isEmpty ? "未命名记录" : trimmed,
            note: note,
            start: start,
            end: end,
            source: source
        )
        store.addEntry(entry)
        reload()
    }

    func deleteEntry(_ entry: TimeEntry) {
        store.deleteEntry(id: entry.id)
        if selectedEntryID == entry.id { selectedEntryID = nil }
        reload()
    }

    /// 双击空白处新建：带上时间范围预填。
    func presentNewEntry(range: DateInterval?) {
        newEntryDraftRange = range
        newEntryPresented = true
    }

    /// 在指定时刻把一个条目拆成两条。
    func splitEntry(_ entry: TimeEntry, at date: Date) {
        guard date > entry.start.addingTimeInterval(30), date < entry.end.addingTimeInterval(-30) else { return }
        var first = entry
        first.end = date
        var second = entry
        second.id = UUID().uuidString
        second.start = date
        store.addEntry(first)
        store.addEntry(second)
        reload()
    }

    /// 与首尾相接（≤60 秒）、同项目同标题的相邻条目合并。
    func mergeEntry(_ entry: TimeEntry) {
        let neighbor = entries.first { other in
            guard other.id != entry.id, other.projectID == entry.projectID, other.title == entry.title else { return false }
            return abs(other.end.timeIntervalSince(entry.start)) <= 60
                || abs(entry.end.timeIntervalSince(other.start)) <= 60
        }
        guard let neighbor else { return }
        var merged = entry
        merged.start = min(entry.start, neighbor.start)
        merged.end = max(entry.end, neighbor.end)
        store.deleteEntry(id: neighbor.id)
        store.addEntry(merged)
        reload()
    }

    /// 编辑已有的手动时间条目（保持 id 不变）。
    func updateEntry(
        _ entry: TimeEntry,
        projectID: String?,
        title: String,
        note: String,
        start: Date,
        end: Date
    ) {
        var updated = entry
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.projectID = projectID
        updated.title = trimmed.isEmpty ? "未命名记录" : trimmed
        updated.note = note
        updated.start = start
        updated.end = end
        store.addEntry(updated)
        reload()
        refreshProjects()
    }

    /// 把记录拖到项目上完成分配。
    func assign(entryIDs: [String], to projectID: String?) {
        guard !entryIDs.isEmpty else { return }
        var changed = false
        for id in entryIDs {
            guard var entry = entries.first(where: { $0.id == id }), entry.projectID != projectID else { continue }
            entry.projectID = projectID
            store.addEntry(entry)
            changed = true
        }
        guard changed else { return }
        reload()
        refreshProjects()
    }

    // MARK: - 计时

    /// 双击项目直接开始正计时
    func startTimer(for project: Project) {
        focusTimer.start(projectID: project.id, title: project.name)
        section = .activity
        selectedProjectID = project.id
        unassignedOnly = false
    }

    func startFocusTimer(projectID: String?, title: String) {
        focusTimer.start(projectID: projectID, title: title)
        startTimerPresented = false
    }

    func stopFocusTimer() {
        guard let session = focusTimer.stop() else { return }
        addEntry(
            projectID: session.projectID,
            title: session.title,
            note: "定时器",
            start: session.start,
            end: session.end,
            source: .timer
        )
    }

    func openTempTimer() {
        if tempTimer.projectID == nil {
            tempTimer.projectID = selectedProjectID
        }
        tempWindow.show()
    }

    func closeTempTimer() {
        tempWindow.close()
    }

    func handleTempTimerComplete() {
        let end = Date()
        let seconds = tempTimer.duration
        store.addEntry(TimeEntry(
            projectID: tempTimer.projectID,
            title: tempTimer.title,
            note: "临时计时",
            start: end.addingTimeInterval(-seconds),
            end: end,
            source: .temporary
        ))
        reload()
        tempTimer.infoText = "已记录 \(Fmt.sidebar(seconds))"
    }

    func saveTempTimerProgress() {
        let seconds = tempTimer.elapsed
        guard seconds >= 1, !tempTimer.isFinished else { return }
        let end = Date()
        let projectID = tempTimer.projectID
        tempTimer.reset()
        store.addEntry(TimeEntry(
            projectID: projectID,
            title: tempTimer.title,
            note: "临时计时",
            start: end.addingTimeInterval(-seconds),
            end: end,
            source: .temporary
        ))
        reload()
        tempTimer.infoText = "已记录 \(Fmt.sidebar(seconds))"
    }
}
