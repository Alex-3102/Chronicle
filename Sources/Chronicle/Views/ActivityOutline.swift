import AppKit
import ChronicleCore
import SwiftUI

// MARK: - 展开 / 选中状态

/// 展开、选中状态放在视图之外，时间轴重建或切换日期时都不会丢。
final class ActivityViewState {
    var expandedIDs: Set<String> = []
    var selectedIDs: Set<String> = []
    /// 已经自动展开过的项目节点，用户手动收起后不会再被自动展开。
    var knownGroupIDs: Set<String> = []
}

// MARK: - 节点

enum ActivityKind {
    case project
    case unassigned
    case title
    case entry
    case app
    case site
    case window
}

/// 活动明细树的一个节点。`duration` 为对应活动切片时长之和，
/// `start` / `end` 只表示覆盖范围，父节点时长 = 直属活动 + 子节点，不重复累加。
final class ActivityNode {
    let id: String
    let kind: ActivityKind
    var title: String
    var duration: TimeInterval
    var start: Date
    var end: Date
    var dimmed: Bool
    var children: [ActivityNode]
    let projectID: String?
    let colorHex: String?
    let bundleID: String?
    let entryID: String?
    let entryIDs: [String]

    init(
        id: String,
        kind: ActivityKind,
        title: String,
        duration: TimeInterval,
        start: Date,
        end: Date,
        dimmed: Bool,
        children: [ActivityNode] = [],
        projectID: String? = nil,
        colorHex: String? = nil,
        bundleID: String? = nil,
        entryID: String? = nil,
        entryIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.duration = duration
        self.start = start
        self.end = end
        self.dimmed = dimmed
        self.children = children
        self.projectID = projectID
        self.colorHex = colorHex
        self.bundleID = bundleID
        self.entryID = entryID
        self.entryIDs = entryIDs
    }

    /// 只描述结构（id + 子节点数量），用于判断刷新时是否需要重新加载。
    var signature: String {
        var parts: [String] = []
        parts.reserveCapacity(children.count)
        for child in children { parts.append(child.signature) }
        return id + "#" + String(children.count) + "[" + parts.joined(separator: ",") + "]"
    }
}

// MARK: - 网站 / 窗口明细

enum ActivityDetail {
    private static let browserBundles: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera"
    ]

    private static let domainRegex = try! NSRegularExpression(
        pattern: #"(?i)\b((?:[a-z0-9-]+\.)+[a-z]{2,})(?:[/:?#]|\b)"#
    )

    /// 网站按域名分组，窗口按标题分组。
    static func info(bundleID: String, raw: String) -> (kind: ActivityKind, key: String, title: String) {
        if browserBundles.contains(bundleID), let domain = domain(in: raw) {
            let value = domain.lowercased()
            return (.site, "s:\(value)", value)
        }
        return (.window, "w:\(raw.lowercased())", raw)
    }

    static func domain(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = domainRegex.firstMatch(in: text, range: range),
              let found = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[found])
    }
}

// MARK: - 树构建

struct ActivityPresentation {
    let entries: [TimeEntry]
    let usage: [AppUsageRecord]
    let projects: [Project]
    let dayInterval: DateInterval
    let isEntryInSelection: (TimeEntry) -> Bool
    let isUnlinkedInSelection: Bool

    private struct Slice {
        let entry: TimeEntry
        let from: Date
        let to: Date
        var duration: TimeInterval { to.timeIntervalSince(from) }
    }

    func build() -> [ActivityNode] {
        let dayStart = dayInterval.start
        let dayEnd = dayInterval.end

        // 1. 取当天范围内的活动切片
        let slices: [Slice] = entries.compactMap { entry in
            let from = max(entry.start, dayStart)
            let to = min(entry.end, dayEnd)
            return to > from ? Slice(entry: entry, from: from, to: to) : nil
        }

        // 2. 应用记录归属到重叠最多的手动时间条目
        var usageByEntry: [String: [AppUsageRecord]] = [:]
        var unlinked: [AppUsageRecord] = []
        for record in usage {
            let from = max(record.start, dayStart)
            let to = min(record.end, dayEnd)
            guard to > from else { continue }
            var owner: String?
            var overlap: TimeInterval = 0
            for slice in slices {
                let value = min(to, slice.to).timeIntervalSince(max(from, slice.from))
                if value > overlap {
                    overlap = value
                    owner = slice.entry.id
                }
            }
            if let owner {
                usageByEntry[owner, default: []].append(record)
            } else {
                unlinked.append(record)
            }
        }

        // 3. 条目按项目分桶
        var buckets: [String: [Slice]] = [:]
        for slice in slices {
            buckets[slice.entry.projectID ?? unassignedKey, default: []].append(slice)
        }

        var nodes: [ActivityNode] = []
        for project in projects where project.parentID == nil {
            if let node = projectNode(project, buckets: buckets, usageByEntry: usageByEntry) {
                nodes.append(node)
            }
        }

        if let node = unassignedNode(buckets: buckets, unlinked: unlinked, usageByEntry: usageByEntry) {
            nodes.append(node)
        }

        return ordered(nodes)
    }

    // MARK: 项目

    private func projectNode(
        _ project: Project,
        buckets: [String: [Slice]],
        usageByEntry: [String: [AppUsageRecord]]
    ) -> ActivityNode? {
        var children: [ActivityNode] = []
        if let list = buckets[project.id] {
            children += titleNodes(
                list,
                parentID: "p:\(project.id)",
                projectID: project.id,
                colorHex: project.colorHex,
                usageByEntry: usageByEntry
            )
        }

        var subprojectTotal: TimeInterval = 0
        for child in projects where child.parentID == project.id {
            guard let node = projectNode(child, buckets: buckets, usageByEntry: usageByEntry) else { continue }
            children.append(node)
            subprojectTotal += node.duration
        }

        guard !children.isEmpty else { return nil }
        children = ordered(children)

        let direct = (buckets[project.id] ?? []).reduce(0) { $0 + $1.duration }
        let selected = (buckets[project.id] ?? []).contains { isEntryInSelection($0.entry) }
        let dimmed = !selected && children.allSatisfy(\.dimmed)

        return ActivityNode(
            id: "p:\(project.id)",
            kind: .project,
            title: project.name,
            duration: direct + subprojectTotal,
            start: children.map(\.start).min() ?? dayInterval.start,
            end: children.map(\.end).max() ?? dayInterval.end,
            dimmed: dimmed,
            children: children,
            projectID: project.id,
            colorHex: project.colorHex
        )
    }

    private func unassignedNode(
        buckets: [String: [Slice]],
        unlinked: [AppUsageRecord],
        usageByEntry: [String: [AppUsageRecord]]
    ) -> ActivityNode? {
        var children: [ActivityNode] = []
        if let list = buckets[unassignedKey] {
            children += titleNodes(
                list,
                parentID: "p:u",
                projectID: nil,
                colorHex: nil,
                usageByEntry: usageByEntry
            )
        }
        if !unlinked.isEmpty {
            // 没有关联手动时间条目的应用活动
            children += appNodes(
                unlinked,
                parentID: "p:u",
                entryID: nil,
                dimmed: !isUnlinkedInSelection,
                range: dayInterval
            )
        }
        guard !children.isEmpty else { return nil }
        children = ordered(children)

        let direct = (buckets[unassignedKey] ?? []).reduce(0) { $0 + $1.duration }
        let appsTotal = unlinked.reduce(0) { $0 + clampedDuration($1, in: dayInterval) }
        let selected = (buckets[unassignedKey] ?? []).contains { isEntryInSelection($0.entry) }
        let dimmed = !selected && !isUnlinkedInSelection

        return ActivityNode(
            id: "p:u",
            kind: .unassigned,
            title: "未分配",
            duration: direct + appsTotal,
            start: children.map(\.start).min() ?? dayInterval.start,
            end: children.map(\.end).max() ?? dayInterval.end,
            dimmed: dimmed,
            children: children
        )
    }

    // MARK: 标题 / 条目 / 应用 / 明细

    private func titleNodes(
        _ list: [Slice],
        parentID: String,
        projectID: String?,
        colorHex: String?,
        usageByEntry: [String: [AppUsageRecord]]
    ) -> [ActivityNode] {
        var groups: [String: [Slice]] = [:]
        for slice in list {
            groups[displayTitle(slice.entry), default: []].append(slice)
        }

        let nodes = groups.map { title, slices -> ActivityNode in
            let id = "\(parentID)/t:\(title)"
            // 标题下的具体时间条目按开始时间排列
            let sorted = slices.sorted { $0.entry.start < $1.entry.start }
            let children = sorted.map { entryNode($0, parentID: id, usageByEntry: usageByEntry) }
            return ActivityNode(
                id: id,
                kind: .title,
                title: title,
                duration: slices.reduce(0) { $0 + $1.duration },
                start: sorted.first?.from ?? dayInterval.start,
                end: sorted.last?.to ?? dayInterval.end,
                dimmed: children.allSatisfy(\.dimmed),
                children: children,
                projectID: projectID,
                colorHex: colorHex,
                entryIDs: sorted.map(\.entry.id)
            )
        }
        return ordered(nodes)
    }

    private func entryNode(
        _ slice: Slice,
        parentID: String,
        usageByEntry: [String: [AppUsageRecord]]
    ) -> ActivityNode {
        let dimmed = !isEntryInSelection(slice.entry)
        let id = "\(parentID)/e:\(slice.entry.id)"
        let apps = appNodes(
            usageByEntry[slice.entry.id] ?? [],
            parentID: id,
            entryID: slice.entry.id,
            dimmed: dimmed,
            range: DateInterval(start: slice.from, end: slice.to)
        )
        return ActivityNode(
            id: id,
            kind: .entry,
            title: "\(Fmt.timeOfDay(slice.from)) – \(Fmt.timeOfDay(slice.to))",
            duration: slice.duration,
            start: slice.from,
            end: slice.to,
            dimmed: dimmed,
            children: apps,
            projectID: slice.entry.projectID,
            entryID: slice.entry.id,
            entryIDs: [slice.entry.id]
        )
    }

    /// 同一项目下重复出现的应用合并成一行：优先用 bundle ID 分组。
    private func appNodes(
        _ records: [AppUsageRecord],
        parentID: String,
        entryID: String?,
        dimmed: Bool,
        range: DateInterval
    ) -> [ActivityNode] {
        var groups: [String: [AppUsageRecord]] = [:]
        for record in records {
            let key = record.bundleID.isEmpty ? record.appName : record.bundleID
            groups[key, default: []].append(record)
        }

        let nodes = groups.map { key, list -> ActivityNode in
            let id = "\(parentID)/a:\(key)"
            let sorted = list.sorted { $0.start < $1.start }
            let name = list.reversed().compactMap { $0.appName.isEmpty ? nil : $0.appName }.first ?? key
            return ActivityNode(
                id: id,
                kind: .app,
                title: name,
                duration: list.reduce(0) { $0 + clampedDuration($1, in: range) },
                start: sorted.first?.start ?? range.start,
                end: sorted.last?.end ?? range.end,
                dimmed: dimmed,
                children: detailNodes(list, parentID: id, dimmed: dimmed, range: range),
                bundleID: key,
                entryID: entryID,
                entryIDs: entryID.map { [$0] } ?? []
            )
        }
        return ordered(nodes)
    }

    private func detailNodes(
        _ records: [AppUsageRecord],
        parentID: String,
        dimmed: Bool,
        range: DateInterval
    ) -> [ActivityNode] {
        var groups: [String: (kind: ActivityKind, title: String, records: [AppUsageRecord])] = [:]
        for record in records {
            let raw = record.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { continue }
            let info = ActivityDetail.info(bundleID: record.bundleID, raw: raw)
            if var existing = groups[info.key] {
                existing.records.append(record)
                groups[info.key] = existing
            } else {
                groups[info.key] = (info.kind, info.title, [record])
            }
        }

        // 只有一个明细且与应用同名时没有信息量
        if groups.count <= 1, let only = groups.values.first,
           only.title == only.records.first?.appName {
            return []
        }

        let nodes = groups.map { key, value -> ActivityNode in
            let sorted = value.records.sorted { $0.start < $1.start }
            return ActivityNode(
                id: "\(parentID)/d:\(key)",
                kind: value.kind,
                title: value.title,
                duration: value.records.reduce(0) { $0 + clampedDuration($1, in: range) },
                start: sorted.first?.start ?? range.start,
                end: sorted.last?.end ?? range.end,
                dimmed: dimmed
            )
        }
        return ordered(nodes)
    }

    // MARK: 辅助

    private var unassignedKey: String { "u" }

    /// 应用切片只统计与所属条目重叠的部分，避免子节点时长超过父条目。
    private func clampedDuration(_ record: AppUsageRecord, in range: DateInterval) -> TimeInterval {
        let from = max(max(record.start, range.start), dayInterval.start)
        let to = min(min(record.end, range.end), dayInterval.end)
        return max(0, to.timeIntervalSince(from))
    }

    private func displayTitle(_ entry: TimeEntry) -> String {
        let value = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未命名记录" : value
    }

    /// 项目、标题、应用、明细按时长降序，时长相同时按稳定 ID 排序。
    private func ordered(_ nodes: [ActivityNode]) -> [ActivityNode] {
        nodes.sorted { lhs, rhs in
            if abs(lhs.duration - rhs.duration) > 0.5 { return lhs.duration > rhs.duration }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - SwiftUI 容器

struct ActivityOutlineSection: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("所有活动")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(Fmt.clock(app.allTotal))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondary)
                Spacer(minLength: 6)
                Text("条目 \(app.activityListEntries.count) · 应用 \(appCount)")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 30)

            ActivityOutlineView(
                entries: app.activityListEntries,
                usage: app.activityListUsage,
                projects: app.projects,
                dayInterval: app.dayInterval,
                isEntryInSelection: { app.isInSelection($0) },
                isUnlinkedInSelection: app.isUnlinkedInSelection,
                viewState: app.activityViewState,
                onOpenEntry: { app.editingEntry = $0 },
                onAssign: { ids, projectID in app.assign(entryIDs: ids, to: projectID) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var appCount: Int {
        Set(app.activityListUsage.map { $0.bundleID.isEmpty ? $0.appName : $0.bundleID }).count
    }
}

// MARK: - NSOutlineView 包装

private enum ActivityPasteboard {
    static let type = NSPasteboard.PasteboardType("com.chronicle.entries")
}

struct ActivityOutlineView: NSViewRepresentable {
    let entries: [TimeEntry]
    let usage: [AppUsageRecord]
    let projects: [Project]
    let dayInterval: DateInterval
    let isEntryInSelection: (TimeEntry) -> Bool
    let isUnlinkedInSelection: Bool
    let viewState: ActivityViewState
    let onOpenEntry: (TimeEntry) -> Void
    let onAssign: ([String], String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = OutlineScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        outline.headerView = nil
        outline.intercellSpacing = .zero
        outline.style = .plain
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .none
        outline.allowsMultipleSelection = true
        outline.allowsEmptySelection = true
        outline.focusRingType = .none
        outline.floatsGroupRows = false
        // style / rowHeight 会重置缩进与行高，必须放在它们之后设置。
        outline.indentationPerLevel = 18
        outline.rowHeight = 31

        // 左侧时长列固定 74pt，右对齐、等宽数字
        let durationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        durationColumn.width = 74
        durationColumn.minWidth = 74
        durationColumn.maxWidth = 74
        durationColumn.resizingMask = []
        outline.addTableColumn(durationColumn)

        // 右侧详情列自动伸展
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 420
        nameColumn.minWidth = 160
        nameColumn.resizingMask = .autoresizingMask
        outline.addTableColumn(nameColumn)
        outline.outlineTableColumn = nameColumn

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        outline.registerForDraggedTypes([ActivityPasteboard.type])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)

        scroll.documentView = outline
        context.coordinator.attach(outline)
        context.coordinator.apply()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply()
    }
}

/// 让表格宽度跟随滚动视图，避免列宽停留在初始值。
final class OutlineScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let document = documentView else { return }
        let width = contentView.bounds.width
        if abs(document.frame.width - width) > 0.5 {
            document.setFrameSize(NSSize(width: width, height: document.frame.height))
        }
    }
}

// MARK: - Coordinator

@MainActor
final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var parent: ActivityOutlineView
    weak var outlineView: NSOutlineView?

    private var nodes: [ActivityNode] = []
    private var lastSignature = "\u{0}"

    init(_ parent: ActivityOutlineView) {
        self.parent = parent
    }

    func attach(_ outline: NSOutlineView) {
        outlineView = outline
    }

    // MARK: 刷新

    func apply() {
        let built = ActivityPresentation(
            entries: parent.entries,
            usage: parent.usage,
            projects: parent.projects,
            dayInterval: parent.dayInterval,
            isEntryInSelection: parent.isEntryInSelection,
            isUnlinkedInSelection: parent.isUnlinkedInSelection
        ).build()
        let signature = built.map(\.signature).joined(separator: "|")

        guard let outline = outlineView else {
            nodes = built
            lastSignature = signature
            return
        }

        if signature == lastSignature, nodes.count == built.count {
            // 结构没变：只更新可见单元格，保持展开、选中与滚动位置
            merge(nodes, built)
            reloadVisibleRows()
        } else {
            let scrollOrigin = outline.enclosingScrollView?.contentView.bounds.origin ?? .zero
            captureState()
            nodes = built
            lastSignature = signature
            outline.reloadData()
            autoExpandNewGroups()
            restoreExpansion()
            restoreSelection()
            restoreScroll(scrollOrigin)
        }
    }

    /// reloadData 会用新对象重建所有行，先按当前视图记录展开 / 选中，刷新后再恢复。
    private func captureState() {
        guard let outline = outlineView else { return }
        var expanded: Set<String> = []
        var selected: Set<String> = []
        for row in 0..<outline.numberOfRows {
            guard let node = outline.item(atRow: row) as? ActivityNode else { continue }
            if outline.isItemExpanded(node) { expanded.insert(node.id) }
            if outline.selectedRowIndexes.contains(row) { selected.insert(node.id) }
        }
        parent.viewState.expandedIDs = expanded
        parent.viewState.selectedIDs = selected
    }

    private func merge(_ current: [ActivityNode], _ next: [ActivityNode]) {
        for (old, new) in zip(current, next) {
            old.title = new.title
            old.duration = new.duration
            old.start = new.start
            old.end = new.end
            old.dimmed = new.dimmed
            merge(old.children, new.children)
        }
    }

    private func reloadVisibleRows() {
        guard let outline = outlineView else { return }
        let rows = outline.rows(in: outline.visibleRect)
        guard rows.length > 0 else { return }
        let indexes = IndexSet(integersIn: rows.location..<(rows.location + rows.length))
        for row in indexes {
            if let rowView = outline.rowView(atRow: row, makeIfNecessary: false),
               let node = outline.item(atRow: row) as? ActivityNode {
                rowView.alphaValue = node.dimmed ? 0.45 : 1
            }
        }
        outline.reloadData(
            forRowIndexes: indexes,
            columnIndexes: IndexSet(integersIn: 0..<outline.numberOfColumns)
        )
    }

    private func autoExpandNewGroups() {
        // 默认展开项目层级；「未分配」下面是大量零碎应用，收起更清爽。
        for node in nodes where node.kind == .project {
            if parent.viewState.knownGroupIDs.insert(node.id).inserted {
                parent.viewState.expandedIDs.insert(node.id)
            }
        }
    }

    private func restoreExpansion() {
        guard let outline = outlineView else { return }

        func walk(_ item: Any?) {
            let count = self.outlineView(outline, numberOfChildrenOfItem: item)
            for index in 0..<count {
                guard let node = self.outlineView(outline, child: index, ofItem: item) as? ActivityNode,
                      !node.children.isEmpty,
                      parent.viewState.expandedIDs.contains(node.id) else { continue }
                outline.expandItem(node)
                walk(node)
            }
        }
        walk(nil)
    }

    private func restoreSelection() {
        guard let outline = outlineView else { return }

        var indexes = IndexSet()
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? ActivityNode,
               parent.viewState.selectedIDs.contains(node.id) {
                indexes.insert(row)
            }
        }
        if indexes.isEmpty {
            outline.deselectAll(nil)
        } else {
            outline.selectRowIndexes(indexes, byExtendingSelection: false)
        }
    }

    private func restoreScroll(_ origin: NSPoint) {
        guard let scroll = outlineView?.enclosingScrollView, let document = scroll.documentView else { return }
        let maxY = max(0, document.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, origin.y), maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: 数据源

    func outlineView(_ outline: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? ActivityNode)?.children.count ?? nodes.count
    }

    func outlineView(_ outline: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? ActivityNode)?.children[index] ?? nodes[index]
    }

    func outlineView(_ outline: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? ActivityNode)?.children.isEmpty == false
    }

    // MARK: 行 / 单元格

    func outlineView(_ outline: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let view = ActivityRowView()
        view.alphaValue = (item as? ActivityNode)?.dimmed == true ? 0.45 : 1
        return view
    }

    func outlineView(_ outline: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? ActivityNode, let column = tableColumn else { return nil }

        if column.identifier.rawValue == "duration" {
            let cell = cellView(outline, identifier: "durationCell") { Self.makeDurationCell() }
            cell.textField?.stringValue = Fmt.clock(node.duration)
            cell.textField?.textColor = node.dimmed ? .tertiaryLabelColor : .secondaryLabelColor
            return cell
        }

        let cell = cellView(outline, identifier: "nameCell") { Self.makeNameCell() }
        configure(cell, node: node)
        return cell
    }

    private func cellView(
        _ outline: NSOutlineView,
        identifier: String,
        build: () -> NSTableCellView
    ) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let reused = outline.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            return reused
        }
        let cell = build()
        cell.identifier = id
        return cell
    }

    private func configure(_ cell: NSTableCellView, node: ActivityNode) {
        guard let label = cell.textField, let imageView = cell.imageView else { return }
        label.stringValue = node.title
        label.toolTip = node.title

        switch node.kind {
        case .project:
            imageView.image = Self.dotImage(color: Self.projectColor(node.colorHex), filled: true)
            imageView.contentTintColor = nil
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .labelColor
        case .unassigned:
            imageView.image = Self.dotImage(color: .tertiaryLabelColor, filled: false)
            imageView.contentTintColor = nil
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .labelColor
        case .title:
            imageView.image = Self.dotImage(color: Self.projectColor(node.colorHex), filled: false)
            imageView.contentTintColor = nil
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
        case .entry:
            imageView.image = Self.symbol("clock", size: 11)
            imageView.contentTintColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11.5)
            label.textColor = .labelColor
        case .app:
            if let bundle = node.bundleID, let icon = AppIconCache.shared.icon(for: bundle) {
                imageView.image = icon
                imageView.contentTintColor = nil
            } else {
                imageView.image = Self.symbol("app.dashed", size: 11)
                imageView.contentTintColor = .secondaryLabelColor
            }
            label.font = .systemFont(ofSize: 12)
            label.textColor = .labelColor
        case .site, .window:
            imageView.image = Self.symbol(node.kind == .site ? "globe" : "macwindow", size: 11)
            imageView.contentTintColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11.5)
            label.textColor = .secondaryLabelColor
        }
    }

    // MARK: 双击

    @objc func handleDoubleClick(_ sender: Any?) {
        guard let outline = outlineView, outline.clickedRow >= 0,
              let node = outline.item(atRow: outline.clickedRow) as? ActivityNode else { return }

        if node.kind == .entry {
            if let id = node.entryID, let entry = parent.entries.first(where: { $0.id == id }) {
                parent.onOpenEntry(entry)
            }
            return
        }

        guard !node.children.isEmpty else { return }
        if outline.isItemExpanded(node) {
            outline.collapseItem(node)
        } else {
            outline.expandItem(node)
        }
    }

    // MARK: 拖拽分配

    func outlineView(_ outline: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? ActivityNode, !node.entryIDs.isEmpty else { return nil }
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(node.entryIDs.joined(separator: ","), forType: ActivityPasteboard.type)
        return pasteboard
    }

    func outlineView(
        _ outline: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let node = item as? ActivityNode,
              node.kind == .project || node.kind == .unassigned,
              index == NSOutlineViewDropOnItemIndex else { return [] }
        return .move
    }

    func outlineView(
        _ outline: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let node = item as? ActivityNode,
              node.kind == .project || node.kind == .unassigned,
              let raw = info.draggingPasteboard.string(forType: ActivityPasteboard.type) else { return false }
        let ids = raw.split(separator: ",").map(String.init)
        guard !ids.isEmpty else { return false }
        parent.onAssign(ids, node.kind == .unassigned ? nil : node.projectID)
        return true
    }

    // MARK: 单元格构建

    private static func makeDurationCell() -> NSTableCellView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: cell.leadingAnchor, constant: 4)
        ])
        return cell
    }

    private static func makeNameCell() -> NSTableCellView {
        let cell = NSTableCellView()
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyUpOrDown
        cell.addSubview(image)
        cell.imageView = image

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 15),
            image.heightAnchor.constraint(equalToConstant: 15),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private static func projectColor(_ hex: String?) -> NSColor {
        guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return .tertiaryLabelColor
        }
        if value.hasPrefix("#") { value.removeFirst() }
        let number = UInt32(value, radix: 16) ?? 0xBDBDBD
        return NSColor(srgbHex: number)
    }

    private static func dotImage(color: NSColor, filled: Bool) -> NSImage {
        let size: CGFloat = 15
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(x: (size - 9) / 2, y: (size - 9) / 2, width: 9, height: 9)
            let path = NSBezierPath(ovalIn: rect)
            if filled {
                color.setFill()
                path.fill()
            } else {
                color.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 1.4
                path.stroke()
            }
            return true
        }
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// 选中行使用灰色圆角背景，行间画浅色细分隔线。
final class ActivityRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isSelected {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
        NSColor.separatorColor.withAlphaComponent(0.22).setFill()
        NSRect(x: 10, y: 0.25, width: max(0, bounds.width - 20), height: 0.5).fill()
    }
}
