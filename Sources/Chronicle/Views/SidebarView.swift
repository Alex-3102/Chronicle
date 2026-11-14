import SwiftUI
import UniformTypeIdentifiers
import ChronicleCore

struct SidebarRowItem: Identifiable {
    let project: Project
    let depth: Int
    var id: String { project.id }
}

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @FocusState private var searchFocused: Bool
    @State private var rootDropTargeted = false
    @State private var keyMonitor: Any?

    private let rowHeight: CGFloat = 26
    private let indent: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            navSection
                .padding(.horizontal, 10)
                .padding(.top, 34)

            projectHeader
                .padding(.top, 14)

            searchField
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        specialRow(
                            icon: "clock",
                            title: "全部活动",
                            seconds: app.allTotal,
                            selected: app.selectedProjectID == nil && !app.unassignedOnly
                        ) {
                            app.selectAllActivity()
                        }

                        specialRow(
                            icon: "tray",
                            title: "未分配",
                            seconds: app.unassignedTotal,
                            selected: app.unassignedOnly
                        ) {
                            app.selectUnassigned()
                        }

                        myProjectsHeader

                        ForEach(rows) { row in
                            ProjectRow(project: row.project, depth: row.depth, rowHeight: rowHeight, indent: indent)
                                .id(row.project.id)
                        }

                        if rows.isEmpty {
                            EmptyStateText(
                                text: app.projectSearch.isEmpty
                                    ? "还没有项目，点右上角「+」新建一个。"
                                    : "没有匹配的项目，试试拼音或首字母。"
                            )
                            .padding(.horizontal, 8)
                        }

                        Text("↑↓ 选择项目，←→ 折叠或展开；拖动可调整顺序，双击直接开始计时。")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.tertiary)
                            .padding(.top, 16)
                            .padding(.horizontal, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .contextMenu { projectListMenu }
                .onChange(of: app.selectedProjectID) { _, value in
                    guard let value else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }

            Divider().overlay(Theme.divider)
            SidebarStatus(tracker: app.tracker, timer: app.focusTimer)
        }
        .background(Theme.sidebar)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    /// ↑↓ 选择项目，←→ 折叠 / 展开；输入框聚焦时让按键正常进入输入框。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window,
                  window == NSApp.keyWindow,
                  window.sheetParent == nil,
                  window.attachedSheet == nil,
                  !(window.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }
            switch event.keyCode {
            case 125: app.moveSelection(by: 1); return nil
            case 126: app.moveSelection(by: -1); return nil
            case 124: app.expandSelectedProject(); return nil
            case 123: app.collapseSelectedProject(); return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private var rows: [SidebarRowItem] {
        app.sidebarRows().map { SidebarRowItem(project: $0.project, depth: $0.depth) }
    }

    private var navSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SidebarSection.allCases) { section in
                let selected = app.section == section
                Button {
                    app.section = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selected ? Theme.orange : Theme.secondary)
                            .frame(width: 15)
                        Text(section.title)
                            .font(.system(size: 12, weight: selected ? .medium : .regular))
                            .foregroundColor(selected ? Theme.text : Theme.text.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Theme.selection : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var projectHeader: some View {
        HStack(spacing: 6) {
            Text("项目")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.secondary)
            Spacer()
            NewProjectIconButton()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .contextMenu { projectListMenu }
    }

    /// 项目列表区域（含空白处）共用的右键菜单。
    @ViewBuilder
    private var projectListMenu: some View {
        Toggle("显示归档项目", isOn: Binding(
            get: { app.showArchived },
            set: { app.showArchived = $0 }
        ))
        Divider()
        Button("新建项目…") {
            app.newProjectParentID = nil
            app.newProjectPresented = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            TextField("搜索项目 / 拼音 / 首字母", text: $app.projectSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Theme.text)
                .focused($searchFocused)
            if !app.projectSearch.isEmpty {
                Button {
                    app.projectSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.window)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    private var myProjectsHeader: some View {
        HStack(spacing: 8) {
            Text("我的项目")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.secondary)
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
            Text(Fmt.sidebar(app.assignedTotal))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundColor(Theme.tertiary)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .padding(.top, 8)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(rootDropTargeted ? Theme.selection : Color.clear)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            app.moveProject(id, under: nil)
            return true
        } isTargeted: { targeted in
            rootDropTargeted = targeted
        }
        .help("把项目拖到这里可移动到顶层")
    }

    private func specialRow(
        icon: String,
        title: String,
        seconds: TimeInterval,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(selected ? Theme.orange : Theme.secondary)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundColor(selected ? Theme.text : Theme.text.opacity(0.85))
                Spacer()
                Text(Fmt.sidebar(seconds))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 项目标题右侧的圆形加号：新建项目。
struct NewProjectIconButton: View {
    @EnvironmentObject var app: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            app.newProjectParentID = nil
            app.newProjectPresented = true
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(hovering ? Theme.orange : Theme.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(hovering ? Theme.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("新建项目")
    }
}

struct ProjectRow: View {
    @EnvironmentObject var app: AppState
    let project: Project
    let depth: Int
    let rowHeight: CGFloat
    let indent: CGFloat

    @State private var hovering = false
    @State private var confirmDelete = false
    @State private var dropZone: ProjectDropZone?

    var body: some View {
        let selected = app.selectedProjectID == project.id && !app.unassignedOnly
        let total = app.aggregateTotal(for: project.id)
        let color = Color(hexString: project.colorHex)
        let hasChildren = !app.children(of: project.id).isEmpty
        let running = app.focusTimer.isRunning && app.focusTimer.projectID == project.id
        let archived = project.isArchived || app.isArchived(project)

        HStack(spacing: 5) {
            DisclosureTriangle(
                expanded: !app.collapsedGroups.contains(project.id),
                visible: hasChildren
            )
            .frame(width: 10, height: 10)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded {
                if hasChildren { app.toggleExpanded(project) }
            })

            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 13, height: 13)
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 13)

            Text(project.name)
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundColor(selected ? Theme.text : Theme.text.opacity(0.88))
                .lineLimit(1)

            if archived {
                Text("归档")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.hover)
                    )
            }

            if running {
                Circle()
                    .fill(Theme.orange)
                    .frame(width: 5, height: 5)
            }

            Spacer(minLength: 4)

            if hovering {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { app.editingProject = project })
                    .help("编辑项目")
            }

            if total > 0.5 {
                Text(Fmt.sidebar(total))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
        }
        .padding(.leading, 4 + CGFloat(depth) * indent)
        .padding(.trailing, 7)
        .frame(height: rowHeight)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.selection : (hovering ? Theme.hover : Color.clear))
                indentGuides
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.blue.opacity(dropZone == .inside ? 0.9 : 0), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if dropZone == .before {
                dropIndicator
                    .offset(y: -1)
            }
        }
        .overlay(alignment: .bottom) {
            if dropZone == .after {
                dropIndicator
                    .offset(y: 1)
            }
        }
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(color)
                    .frame(width: 2.5)
                    .padding(.vertical, 5)
            }
        }
        .opacity(archived ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            app.startTimer(for: project)
        }
        .onTapGesture {
            app.select(project: project)
        }
        .onHover { hovering = $0 }
        .draggable(project.id) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.panel)
            )
        }
        .onDrop(of: [.text], delegate: ProjectDropDelegate(
            rowHeight: rowHeight,
            onZone: { dropZone = $0 },
            onDrop: { id, zone in
                guard id != project.id else { return }
                switch zone {
                case .before:
                    app.moveProject(id, under: project.parentID, before: project.id)
                case .after:
                    app.moveProject(id, under: project.parentID, after: project.id)
                case .inside:
                    app.moveProject(id, under: project.id)
                }
            }
        ))
        .contextMenu {
            Button("开始计时") { app.startTimer(for: project) }
            Button("编辑项目…") { app.editingProject = project }
            Button("新建子项目…") {
                app.newProjectParentID = project.id
                app.newProjectPresented = true
            }
            Divider()
            if archived {
                Button("取消归档") { app.setArchived(project, false) }
            } else {
                Button("归档项目") { app.setArchived(project, true) }
            }
            Divider()
            Button("删除项目", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog(
            "删除项目「\(project.name)」？",
            isPresented: $confirmDelete
        ) {
            Button("删除", role: .destructive) { app.deleteProject(project) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("子项目会一并删除，已有时间记录会变为未分配。")
        }
    }

    /// 插入位置提示：一条蓝色横线，从当前层级缩进处开始。
    private var dropIndicator: some View {
        Capsule()
            .fill(Theme.blue)
            .frame(height: 2)
            .padding(.leading, 4 + CGFloat(depth) * indent)
            .padding(.trailing, 7)
            .allowsHitTesting(false)
    }

    /// 父级缩进的竖向引导线，让层级更清楚。
    private var indentGuides: some View {
        Canvas { context, size in
            for level in 0..<max(depth, 0) {
                let x = 4 + CGFloat(level) * indent + 9
                var path = Path()
                path.move(to: CGPoint(x: x, y: 2))
                path.addLine(to: CGPoint(x: x, y: size.height - 2))
                context.stroke(path, with: .color(Theme.divider.opacity(0.55)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 拖动项目时的落点区域：插到目标前面 / 后面，或成为目标的子项目。
enum ProjectDropZone {
    case before
    case after
    case inside
}

/// 按拖动位置实时区分「插入」和「归属」，让行上能画出对应的提示。
private struct ProjectDropDelegate: DropDelegate {
    let rowHeight: CGFloat
    let onZone: (ProjectDropZone?) -> Void
    let onDrop: (String, ProjectDropZone) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        onZone(zone(for: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onZone(zone(for: info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onZone(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = zone(for: info)
        onZone(nil)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            DispatchQueue.main.async {
                onDrop(id, zone)
            }
        }
        return true
    }

    /// 上 1/3 插到前面、下 1/3 插到后面，中间 1/3 才成为子项目。
    private func zone(for info: DropInfo) -> ProjectDropZone {
        let ratio = min(max(info.location.y / max(rowHeight, 1), 0), 1)
        if ratio < 0.34 { return .before }
        if ratio > 0.66 { return .after }
        return .inside
    }
}

/// 自绘的三角展开箭头，避免默认控件风格。
struct DisclosureTriangle: View {
    let expanded: Bool
    let visible: Bool

    var body: some View {
        Canvas { context, size in
            guard visible else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 3.1
            var path = Path()
            if expanded {
                path.move(to: CGPoint(x: center.x - radius, y: center.y - radius * 0.55))
                path.addLine(to: CGPoint(x: center.x + radius, y: center.y - radius * 0.55))
                path.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.85))
            } else {
                path.move(to: CGPoint(x: center.x - radius * 0.55, y: center.y - radius))
                path.addLine(to: CGPoint(x: center.x + radius * 0.85, y: center.y))
                path.addLine(to: CGPoint(x: center.x - radius * 0.55, y: center.y + radius))
            }
            path.closeSubpath()
            context.fill(path, with: .color(Theme.tertiary))
        }
    }
}

struct SidebarStatus: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tracker: AppUsageTracker
    @ObservedObject var timer: FocusUpTimerModel

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(timer.isRunning ? Theme.red : (tracker.isIdle ? Theme.tertiary : Theme.green))
                .frame(width: 6, height: 6)

            if timer.isRunning {
                Text("定时器")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondary)
                Text(Fmt.clock(timer.elapsed))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.text)
                Spacer()
                Button("停止") { app.stopFocusTimer() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.orange)
            } else {
                Text(tracker.activeAppName.map { "正在追踪 \($0)" } ?? "已暂停追踪")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondary)
                    .lineLimit(1)
                Spacer()
                Text(Fmt.sidebar(tracker.todayTotal))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(Theme.sidebar)
    }
}
