import SwiftUI
import ChronicleCore

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.orange.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.panelAlt.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}

/// 项目选择浮层中的一个选项（项目、未分配、全部活动、无父级…）。
struct ProjectPickerOption: Identifiable {
    let id: String
    let title: String
    let colorHex: String?
    let depth: Int
}

/// 项目搜索浮层：搜索框 + 颜色圆点 + 层级缩进 + 方向键选择。
/// 项目选择、父级项目与顶部筛选共用这一套外观。
struct ProjectPickerPanel: View {
    let selectedID: String?
    let options: (String) -> [ProjectPickerOption]
    let onPick: (String) -> Void
    @Binding var isOpen: Bool
    /// 列表里始终存在的固定项数量（筛选器有「全部活动 / 未分配」两项）。
    var fixedCount = 1

    @State private var query = ""
    @State private var highlighted = 0
    @State private var hoveredID: String?
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private var entries: [ProjectPickerOption] { options(query) }

    var body: some View {
        panel
            .onAppear(perform: prepare)
            .onDisappear(perform: removeMonitor)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
                TextField("搜索项目 / 拼音", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text)
                    .focusEffectDisabled()
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)

            Divider().overlay(Theme.divider)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(entry, index: index)
                                .id(entry.id)
                        }
                        if entries.count <= fixedCount {
                            Text("没有匹配的项目")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(5)
                }
                .scrollIndicators(.never)
                .frame(height: min(240, max(58, CGFloat(entries.count) * 25 + 10)))
                .onChange(of: highlighted) { _, value in
                    guard entries.indices.contains(value) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(entries[value].id, anchor: .center)
                    }
                }
            }

            Divider().overlay(Theme.divider)

            Text("↑↓ 选择 · ↵ 确认 · esc 关闭")
                .font(.system(size: 9))
                .foregroundColor(Theme.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
        }
        .frame(width: 248)
        .background(Theme.panel)
        .onChange(of: query) { _, _ in
            highlighted = 0
            hoveredID = nil
        }
    }

    private func row(_ entry: ProjectPickerOption, index: Int) -> some View {
        let selected = entry.id == selectedID
        let active = index == highlighted
        return HStack(spacing: 7) {
            Circle()
                .fill(entry.colorHex.map { Color(hexString: $0) } ?? Theme.tertiary)
                .frame(width: 7, height: 7)
                .frame(width: 9)

            Text(entry.title)
                .font(.system(size: 12))
                .foregroundColor(selected ? Theme.text : Theme.text.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 6)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.secondary)
            }
        }
        .padding(.leading, CGFloat(6 + entry.depth * 13))
        .padding(.trailing, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(active ? Theme.selection : (hoveredID == entry.id ? Theme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredID = entry.id
            } else if hoveredID == entry.id {
                hoveredID = nil
            }
        }
        .onTapGesture { commit(at: index) }
    }

    private func prepare() {
        query = ""
        let index = entries.firstIndex { $0.id == selectedID } ?? 0
        highlighted = index
        installMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            searchFocused = true
        }
    }

    private func installMonitor() {
        removeMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isOpen else { return event }
            let items = entries
            switch event.keyCode {
            case 125: // ↓
                highlighted = min(items.count - 1, highlighted + 1)
                return nil
            case 126: // ↑
                highlighted = max(0, highlighted - 1)
                return nil
            case 36, 76: // return / enter
                commit(at: highlighted)
                return nil
            case 53: // esc
                isOpen = false
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func commit(at index: Int) {
        let items = entries
        guard items.indices.contains(index) else { return }
        onPick(items[index].id)
        isOpen = false
    }
}

/// 项目选择器：按钮 + 上面的搜索浮层，绑定 projectID（nil 对应第一项）。
struct ProjectPicker: View {
    @EnvironmentObject var app: AppState
    @Binding var projectID: String?
    var compact = false
    /// 第一项（nil）的文案。
    var noneTitle = "未分配"
    /// 需要排除的项目（编辑项目时的自己与子孙）。
    var excluding: Set<String> = []

    @State private var isOpen = false

    private let noneID = "__none__"

    private func options(query: String) -> [ProjectPickerOption] {
        var items = [ProjectPickerOption(id: noneID, title: noneTitle, colorHex: nil, depth: 0)]
        for project in app.pickerProjects(matching: query) where !excluding.contains(project.id) {
            items.append(
                ProjectPickerOption(
                    id: project.id,
                    title: project.name,
                    colorHex: project.colorHex,
                    depth: app.depth(of: project)
                )
            )
        }
        return items
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(app.color(for: projectID))
                    .frame(width: 7, height: 7)
                    .opacity(projectID == nil ? 0 : 1)
                Text(app.project(projectID)?.name ?? noneTitle)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: compact ? 26 : 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.window)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isOpen ? Theme.orange.opacity(0.6) : Theme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen) {
            ProjectPickerPanel(
                selectedID: projectID ?? noneID,
                options: options(query:),
                onPick: { id in
                    projectID = id == noneID ? nil : id
                    isOpen = false
                },
                isOpen: $isOpen
            )
        }
    }
}

private func labeledField<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(.system(size: 10))
            .foregroundColor(Theme.secondary)
        content()
    }
}

struct NewEntrySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let editing: TimeEntry?

    @State private var projectID: String?
    @State private var title = ""
    @State private var note = ""
    @State private var start = Date().addingTimeInterval(-30 * 60)
    @State private var end = Date()
    @FocusState private var titleFocused: Bool

    init(editing: TimeEntry? = nil) {
        self.editing = editing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editing == nil ? "你要做什么？" : "编辑时间条目")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondary)
                }
                .buttonStyle(.plain)
            }

            labeledField("项目") {
                ProjectPicker(projectID: $projectID)
            }

            labeledField("标题") {
                DarkField(focused: titleFocused) {
                    TextField("你将会做什么…", text: $title)
                        .focused($titleFocused)
                }
            }

            labeledField("备注") {
                TextEditor(text: $note)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.window)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
            }

            HStack(alignment: .bottom, spacing: 12) {
                labeledField("开始时间") {
                    datePicker($start)
                }
                labeledField("结束时间") {
                    datePicker($end)
                }
            }

            HStack(spacing: 6) {
                Button("现在") {
                    end = Date()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(Theme.blue)

                Button("+15 分钟") {
                    end = start.addingTimeInterval(15 * 60)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(Theme.blue)

                Button("+30 分钟") {
                    end = start.addingTimeInterval(30 * 60)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(Theme.blue)

                Spacer()

                Text("时长 \(Fmt.sidebar(max(0, end.timeIntervalSince(start))))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }

            Divider().overlay(Theme.divider)

            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(editing == nil ? "开始追踪" : "保存") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                    .opacity(end > start ? 1 : 0.4)
                    .disabled(end <= start)
            }
        }
        .padding(20)
        .frame(width: 470)
        .background(Theme.panel)
        .onAppear {
            if let editing {
                projectID = editing.projectID
                title = editing.title
                note = editing.note
                start = editing.start
                end = editing.end
            } else {
                projectID = app.selectedProjectID
            }
            titleFocused = true
        }
    }

    private func datePicker(_ binding: Binding<Date>) -> some View {
        DatePicker("", selection: binding, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.field)
            .font(.system(size: 11))
    }

    private func save() {
        guard end > start else { return }
        if let editing {
            app.updateEntry(editing, projectID: projectID, title: title, note: note, start: start, end: end)
        } else {
            app.addEntry(
                projectID: projectID,
                title: title,
                note: note,
                start: start,
                end: end,
                source: .manual
            )
        }
        dismiss()
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private let editing: Project?

    @State private var name: String
    @State private var colorHex: String
    @State private var parentID: String?
    @State private var isGroup: Bool
    @State private var isArchived: Bool
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(editing: Project? = nil, presetParentID: String? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _colorHex = State(initialValue: editing?.colorHex ?? Theme.palette[0])
        _parentID = State(initialValue: editing?.parentID ?? presetParentID)
        _isGroup = State(initialValue: editing?.isGroup ?? false)
        _isArchived = State(initialValue: editing?.isArchived ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "新建项目" : "编辑项目")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.text)

            labeledField("名称") {
                DarkField(focused: nameFocused) {
                    TextField("项目名称", text: $name)
                        .focused($nameFocused)
                }
            }

            labeledField("颜色") {
                colorPicker
            }

            labeledField("父级项目") {
                ProjectPicker(
                    projectID: $parentID,
                    noneTitle: "无（顶层项目）",
                    excluding: excludedParentIDs
                )
            }

            if editing != nil {
                Toggle(isOn: $isArchived) {
                    Text("归档（不在项目树和搜索中显示）")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondary)
                }
                .toggleStyle(.checkbox)
            }

            Divider().overlay(Theme.divider)

            HStack {
                if editing != nil {
                    Button("删除项目") { confirmDelete = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.red)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(editing == nil ? "创建" : "保存") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                    .opacity(trimmedName.isEmpty ? 0.4 : 1)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(Theme.panel)
        .onAppear { nameFocused = true }
        .confirmationDialog("删除项目「\(editing?.name ?? "")」？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if let editing {
                    app.deleteProject(editing)
                }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("子项目会一并删除，已有记录会变为未分配。")
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var colorPicker: some View {
        HStack(spacing: 8) {
            ForEach(Theme.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hexString: hex))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: colorHex == hex ? 1.6 : 0)
                            .padding(-3)
                    )
                    .contentShape(Circle())
                    .onTapGesture { colorHex = hex }
            }
            Spacer(minLength: 0)
        }
    }

    /// 父级项目不能选自己或自己的子孙。
    private var excludedParentIDs: Set<String> {
        guard let editing else { return [] }
        var excluded: Set<String> = [editing.id]
        func walk(_ id: String) {
            for child in app.projects where child.parentID == id {
                excluded.insert(child.id)
                walk(child.id)
            }
        }
        walk(editing.id)
        return excluded
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if var project = editing {
            project.name = trimmedName
            project.colorHex = colorHex
            project.parentID = parentID
            project.isGroup = isGroup
            project.isArchived = isArchived
            app.updateProject(project)
        } else {
            app.createProject(name: trimmedName, colorHex: colorHex, isGroup: isGroup, parentID: parentID)
        }
        dismiss()
    }
}

struct StartTimerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var projectID: String?
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开始定时器")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.text)

            labeledField("项目") {
                ProjectPicker(projectID: $projectID)
            }

            labeledField("标题") {
                DarkField(focused: titleFocused) {
                    TextField("这段时间要做什么？", text: $title)
                        .focused($titleFocused)
                }
            }

            Text("开始后会在标题栏显示计时器，停止时自动保存为时间条目。")
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiary)

            Divider().overlay(Theme.divider)

            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("开始计时") {
                    app.startFocusTimer(projectID: projectID, title: title)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(Theme.panel)
        .onAppear {
            projectID = app.selectedProjectID
            titleFocused = true
        }
    }
}
