import SwiftUI
import AppKit
import ChronicleCore

// MARK: - 模型

enum ReportRange: String, CaseIterable, Identifiable {
    case day, week, month, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "今日"
        case .week: return "本周"
        case .month: return "本月"
        case .custom: return "自定义"
        }
    }
}

enum ReportContent: String, CaseIterable, Identifiable {
    case entries, apps, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entries: return "时间条目"
        case .apps: return "应用使用"
        case .all: return "全部"
        }
    }
}

enum ReportKind {
    case entry, app
}

struct ReportRow: Identifiable {
    let id: String
    let kind: ReportKind
    let start: Date
    let end: Date
    let title: String
    let projectName: String
    let appName: String
    let detail: String
    let entryIDs: [String]
    let usageIDs: [String]
    let projectID: String?

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

struct ReportColumn: Identifiable {
    let id: String
    let title: String
    let width: CGFloat

    static let all: [ReportColumn] = [
        ReportColumn(id: "start", title: "开始", width: 92),
        ReportColumn(id: "end", title: "结束", width: 92),
        ReportColumn(id: "duration", title: "时长", width: 74),
        ReportColumn(id: "kind", title: "类型", width: 60),
        ReportColumn(id: "project", title: "项目", width: 132),
        ReportColumn(id: "title", title: "描述", width: 260),
        ReportColumn(id: "app", title: "应用", width: 140)
    ]
}

// MARK: - 页面

struct ReportsView: View {
    @EnvironmentObject var app: AppState

    @State private var range: ReportRange = .day
    @State private var content: ReportContent = .all
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var customEnd = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86399)
    @State private var visibleColumns: Set<String> = ["start", "end", "duration", "project", "title", "app"]
    @State private var sortKey = "start"
    @State private var sortAscending = true
    @State private var customPopover = false

    private var interval: DateInterval {
        let calendar = Calendar.current
        switch range {
        case .day:
            let start = calendar.startOfDay(for: app.selectedDay)
            return DateInterval(start: start, duration: 86400)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: app.selectedDay)
                ?? DateInterval(start: app.selectedDay, duration: 7 * 86400)
        case .month:
            return calendar.dateInterval(of: .month, for: app.selectedDay)
                ?? DateInterval(start: app.selectedDay, duration: 30 * 86400)
        case .custom:
            let start = Calendar.current.startOfDay(for: customStart)
            let end = Calendar.current.startOfDay(for: customEnd).addingTimeInterval(86400)
            return DateInterval(start: start, end: max(start.addingTimeInterval(3600), end))
        }
    }

    private var columns: [ReportColumn] {
        ReportColumn.all.filter { visibleColumns.contains($0.id) }
    }

    private var rows: [ReportRow] {
        let output = interval
        var result: [ReportRow] = []

        if content != .apps {
            for entry in app.store.entries(from: output.start, to: output.end) {
                let from = max(entry.start, output.start)
                let to = min(entry.end, output.end)
                guard to > from else { continue }
                let project = app.project(entry.projectID)
                result.append(ReportRow(
                    id: "entry-\(entry.id)",
                    kind: .entry,
                    start: from,
                    end: to,
                    title: entry.title,
                    projectName: project?.name ?? "未分配",
                    appName: "",
                    detail: entry.note,
                    entryIDs: [entry.id],
                    usageIDs: [],
                    projectID: entry.projectID
                ))
            }
        }

        if content != .entries {
            for record in app.store.usage(from: output.start, to: output.end) {
                let from = max(record.start, output.start)
                let to = min(record.end, output.end)
                guard to > from else { continue }
                result.append(ReportRow(
                    id: "usage-\(record.id)",
                    kind: .app,
                    start: from,
                    end: to,
                    title: record.windowTitle ?? "",
                    projectName: app.project(record.projectID)?.name ?? "未分配",
                    appName: record.appName,
                    detail: record.url ?? record.filePath ?? "",
                    entryIDs: [],
                    usageIDs: [record.id],
                    projectID: record.projectID
                ))
            }
        }

        return sorted(result)
    }

    private func sorted(_ list: [ReportRow]) -> [ReportRow] {
        list.sorted { lhs, rhs in
            let result: Bool
            switch sortKey {
            case "end":
                result = lhs.end < rhs.end
            case "duration":
                result = lhs.duration < rhs.duration
            case "project":
                result = lhs.projectName.localizedCompare(rhs.projectName) == .orderedAscending
            case "title":
                result = lhs.title.localizedCompare(rhs.title) == .orderedAscending
            case "app":
                result = lhs.appName.localizedCompare(rhs.appName) == .orderedAscending
            case "kind":
                result = (lhs.kind == .entry ? 0 : 1) < (rhs.kind == .entry ? 0 : 1)
            default:
                result = lhs.start < rhs.start
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        let list = rows
        let entryTotal = list.filter { $0.kind == .entry }.reduce(0) { $0 + $1.duration }
        let appTotal = list.filter { $0.kind == .app }.reduce(0) { $0 + $1.duration }

        VStack(alignment: .leading, spacing: 0) {
            header(list: list, entryTotal: entryTotal, appTotal: appTotal)
            Divider().overlay(Theme.divider)

            GeometryReader { geo in
            ReportTable(
                rows: list,
                width: geo.size.width,
                columns: columns,
                onSort: { key, ascending in
                    sortKey = key
                    sortAscending = ascending
                },
                onAssign: { ids, projectID in
                    app.assignRecords(entryIDs: ids.entryIDs, activityIDs: ids.usageIDs, to: projectID)
                },
                onEdit: { entryID in
                    if let entry = app.entries.first(where: { $0.id == entryID }) {
                        app.editingEntry = entry
                    }
                },
                onDelete: { entryIDs, usageIDs in
                    for id in entryIDs { app.deleteEntry(id: id) }
                    if !usageIDs.isEmpty {
                        app.store.assignUsage(ids: usageIDs, projectID: nil)
                        app.reload()
                    }
                },
                projects: app.projects
            )
            .background(Theme.window)
            }

            Divider().overlay(Theme.divider)
            footer(list: list, entryTotal: entryTotal, appTotal: appTotal)
        }
        .background(Theme.window)
    }

    // MARK: - 头部

    private func header(list: [ReportRow], entryTotal: TimeInterval, appTotal: TimeInterval) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("报告")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text("\(rangeText) · \(list.count) 行")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
            }

            Spacer()

            segment(items: ReportRange.allCases.map { ($0.rawValue, $0.title) }, selection: range.rawValue) { raw in
                if let value = ReportRange(rawValue: raw) {
                    range = value
                    if value == .custom { customPopover = true }
                }
            }
            .popover(isPresented: $customPopover) { customRangePicker }

            segment(items: ReportContent.allCases.map { ($0.rawValue, $0.title) }, selection: content.rawValue) { raw in
                if let value = ReportContent(rawValue: raw) { content = value }
            }

            Menu {
                ForEach(ReportColumn.all) { column in
                    Button {
                        if visibleColumns.contains(column.id) {
                            if visibleColumns.count > 2 { visibleColumns.remove(column.id) }
                        } else {
                            visibleColumns.insert(column.id)
                        }
                    } label: {
                        if visibleColumns.contains(column.id) {
                            Label(column.title, systemImage: "checkmark")
                        } else {
                            Text(column.title)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondary)
                    .frame(width: 24, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("列显示")

            Button {
                exportCSV(list)
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.panelAlt)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var customRangePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自定义范围")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.text)
            DatePicker("开始", selection: $customStart, displayedComponents: .date)
                .font(.system(size: 11))
            DatePicker("结束", selection: $customEnd, displayedComponents: .date)
                .font(.system(size: 11))
            HStack {
                Spacer()
                Button("完成") { customPopover = false }
                    .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private func footer(list: [ReportRow], entryTotal: TimeInterval, appTotal: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Text("共 \(list.count) 行")
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiary)
            if content != .apps {
                Text("条目 \(list.filter { $0.kind == .entry }.count)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
            }
            if content != .entries {
                Text("应用 \(list.filter { $0.kind == .app }.count)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
            }
            Spacer()
            if content != .apps {
                Text("条目合计 \(Fmt.human(entryTotal))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondary)
            }
            if content != .entries {
                Text("应用合计 \(Fmt.human(appTotal))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 26)
    }

    private func segment(
        items: [(String, String)],
        selection: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let active = item.0 == selection
                Button {
                    onSelect(item.0)
                } label: {
                    Text(item.1)
                        .font(.system(size: 10.5, weight: active ? .medium : .regular))
                        .foregroundColor(active ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(active ? Theme.selection : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.panelAlt.opacity(0.8))
        )
    }

    private var rangeText: String {
        let calendar = Calendar.current
        switch range {
        case .day:
            return Fmt.dayLong(interval.start)
        case .week, .month:
            let end = interval.end.addingTimeInterval(-1)
            return "\(calendar.component(.month, from: interval.start))/\(calendar.component(.day, from: interval.start)) – \(calendar.component(.month, from: end))/\(calendar.component(.day, from: end))"
        case .custom:
            let end = interval.end.addingTimeInterval(-1)
            return "\(Fmt.monthDay(interval.start)) – \(Fmt.monthDay(end))"
        }
    }

    // MARK: - CSV

    private func exportCSV(_ list: [ReportRow]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Chronicle-\(range.rawValue).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var text = "类型,开始,结束,时长(秒),时长,项目,描述,应用,链接/文件\n"
        for row in list {
            let fields = [
                row.kind == .entry ? "时间条目" : "应用使用",
                formatter.string(from: row.start),
                formatter.string(from: row.end),
                String(format: "%.0f", row.duration),
                Fmt.human(row.duration),
                row.projectName,
                row.title,
                row.appName,
                row.detail
            ]
            text += fields.map(escape).joined(separator: ",") + "\n"
        }
        // 带 BOM，Excel 打开中文不乱码。
        if let data = ("\u{FEFF}" + text).data(using: .utf8) {
            try? data.write(to: url)
        }
    }

    private func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - AppKit 明细表

struct ReportTable: NSViewRepresentable {
    let rows: [ReportRow]
    let width: CGFloat
    let columns: [ReportColumn]
    let onSort: (String, Bool) -> Void
    let onAssign: ((entryIDs: [String], usageIDs: [String]), String?) -> Void
    let onEdit: (String) -> Void
    let onDelete: ([String], [String]) -> Void
    let projects: [Project]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = ReportNSTableView()
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = NSColor(Theme.window)
        tableView.gridStyleMask = []
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.autoresizingMask = [.width]
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.coordinator = context.coordinator
        tableView.menuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.buildMenu() ?? NSMenu()
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(Theme.window)
        scrollView.autohidesScrollers = true

        context.coordinator.tableView = tableView
        context.coordinator.configure(rows: rows, columns: columns, onSort: onSort, onAssign: onAssign, onEdit: onEdit, onDelete: onDelete, projects: projects)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? ReportNSTableView else { return }
        context.coordinator.configure(rows: rows, columns: columns, onSort: onSort, onAssign: onAssign, onEdit: onEdit, onDelete: onDelete, projects: projects)
        context.coordinator.syncColumns(columns, in: tableView)
        let available = max(width, 320)
        let needed = columns.reduce(0) { $0 + $1.width }
        // 列总宽不足时把表格拉满视口，最后一列由 AppKit 自动吃掉剩余宽度。
        tableView.frame = NSRect(x: 0, y: 0, width: max(needed, available), height: max(tableView.frame.height, 1))
        if context.coordinator.needsReload {
            tableView.reloadData()
            context.coordinator.needsReload = false
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var tableView: ReportNSTableView?
        var rows: [ReportRow] = []
        var columns: [ReportColumn] = []
        var needsReload = false
        var contextRow: Int = -1

        private var onSort: ((String, Bool) -> Void)?
        private var onAssign: (((entryIDs: [String], usageIDs: [String]), String?) -> Void)?
        private var onEdit: ((String) -> Void)?
        private var onDelete: (([String], [String]) -> Void)?
        private var projects: [Project] = []

        func configure(
            rows: [ReportRow],
            columns: [ReportColumn],
            onSort: @escaping (String, Bool) -> Void,
            onAssign: @escaping ((entryIDs: [String], usageIDs: [String]), String?) -> Void,
            onEdit: @escaping (String) -> Void,
            onDelete: @escaping ([String], [String]) -> Void,
            projects: [Project]
        ) {
            if self.rows.map(\.id) != rows.map(\.id) {
                needsReload = true
            }
            self.rows = rows
            self.columns = columns
            self.onSort = onSort
            self.onAssign = onAssign
            self.onEdit = onEdit
            self.onDelete = onDelete
            self.projects = projects
        }

        func syncColumns(_ columns: [ReportColumn], in tableView: NSTableView) {
            let current = tableView.tableColumns.map(\.identifier.rawValue)
            guard current != columns.map(\.id) else { return }
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }
            for column in columns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
                tableColumn.title = column.title
                tableColumn.width = column.width
                tableColumn.minWidth = 48
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.id, ascending: true)
                tableView.addTableColumn(tableColumn)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < rows.count else { return nil }
            let item = rows[row]
            let identifier = tableColumn.identifier

            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let field = NSTextField(labelWithString: "")
                field.font = NSFont.systemFont(ofSize: 10.5)
                field.textColor = NSColor(Theme.text)
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(field)
                cell.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }

            let (text, color) = value(for: item, column: identifier.rawValue)
            cell.textField?.stringValue = text
            cell.textField?.textColor = color
            return cell
        }

        private func value(for row: ReportRow, column: String) -> (String, NSColor) {
            switch column {
            case "start":
                return (Fmt.timeOfDay(row.start), NSColor(Theme.text))
            case "end":
                return (Fmt.timeOfDay(row.end), NSColor(Theme.text))
            case "duration":
                return (Fmt.sidebar(row.duration), NSColor(Theme.secondary))
            case "kind":
                return (row.kind == .entry ? "条目" : "应用", NSColor(Theme.tertiary))
            case "project":
                return (row.projectName, row.projectID == nil ? NSColor(Theme.tertiary) : NSColor(Theme.secondary))
            case "title":
                return (row.title.isEmpty ? row.detail : row.title, NSColor(Theme.text))
            case "app":
                return (row.appName.isEmpty ? "—" : row.appName, NSColor(Theme.secondary))
            default:
                return ("", NSColor(Theme.text))
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            onSort?(key, descriptor.ascending)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < rows.count else { return nil }
            let item = rows[row]
            let ids = item.entryIDs.isEmpty ? item.usageIDs : item.entryIDs
            guard !ids.isEmpty else { return nil }
            let prefix = item.entryIDs.isEmpty ? "usage" : "entry"
            let pasteboard = NSPasteboardItem()
            pasteboard.setString("chronicle:\(prefix):\(ids.joined(separator: ","))", forType: .string)
            return pasteboard
        }

        func buildMenu() -> NSMenu {
            let menu = NSMenu()
            guard contextRow >= 0, contextRow < rows.count else { return menu }
            let row = rows[contextRow]
            let selection = selectedRows(including: row)

            let entryIDs = selection.flatMap(\.entryIDs)
            let usageIDs = selection.flatMap(\.usageIDs)

            menu.addItem(withTitle: "分配 \(selection.count) 行到项目", action: nil, keyEquivalent: "")

            for project in projectList() {
                let item = NSMenuItem(title: project.0, action: #selector(assignAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["project": project.1 ?? "", "entry": entryIDs, "usage": usageIDs]
                menu.addItem(item)
            }
            let none = NSMenuItem(title: "未分配", action: #selector(assignAction(_:)), keyEquivalent: "")
            none.target = self
            none.representedObject = ["project": "", "entry": entryIDs, "usage": usageIDs]
            menu.addItem(none)

            menu.addItem(.separator())

            if let entryID = row.entryIDs.first {
                let edit = NSMenuItem(title: "编辑条目…", action: #selector(editAction(_:)), keyEquivalent: "")
                edit.target = self
                edit.representedObject = entryID
                menu.addItem(edit)
            }

            let delete = NSMenuItem(title: "删除所选", action: #selector(deleteAction(_:)), keyEquivalent: "")
            delete.target = self
            delete.representedObject = ["entry": entryIDs, "usage": usageIDs]
            menu.addItem(delete)
            return menu
        }

        private func selectedRows(including row: ReportRow) -> [ReportRow] {
            guard let tableView else { return [row] }
            let indexes = tableView.selectedRowIndexes
            if indexes.contains(contextRow) {
                return indexes.compactMap { $0 < rows.count ? rows[$0] : nil }
            }
            return [row]
        }

        private func projectList() -> [(String, String?)] {
            projects.map { ($0.name, Optional($0.id)) }
        }

        @objc private func assignAction(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? [String: Any],
                  let entryIDs = payload["entry"] as? [String],
                  let usageIDs = payload["usage"] as? [String] else { return }
            let raw = payload["project"] as? String ?? ""
            onAssign?((entryIDs: entryIDs, usageIDs: usageIDs), raw.isEmpty ? nil : raw)
        }

        @objc private func editAction(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            onEdit?(id)
        }

        @objc private func deleteAction(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? [String: Any],
                  let entryIDs = payload["entry"] as? [String],
                  let usageIDs = payload["usage"] as? [String] else { return }
            onDelete?(entryIDs, usageIDs)
        }
    }
}

/// 右键前先选中鼠标下的行，并回调自定义菜单。
final class ReportNSTableView: NSTableView {
    weak var coordinator: ReportTable.Coordinator?
    var menuProvider: (() -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 {
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            coordinator?.contextRow = row
        } else {
            coordinator?.contextRow = -1
        }
        return menuProvider?()
    }
}
