import SwiftUI

struct HeaderBar: View {
    @EnvironmentObject var app: AppState
    @FocusState private var searchFocused: Bool
    @State private var filterOpen = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ToolbarButton(icon: "plus.square", title: "新建时间条目") {
                    app.newEntryPresented = true
                }
                ToolbarButton(icon: "clock", title: "开始定时器") {
                    app.startTimerPresented = true
                }
                ToolbarButton(icon: "hourglass", title: "临时计时", tint: Theme.orange) {
                    app.openTempTimer()
                }
            }

            FocusTimerPill(timer: app.focusTimer)
            TempTimerPill(timer: app.tempTimer)

            Spacer(minLength: 6)
            dateNav
            Spacer(minLength: 6)
            rightControls
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Theme.panel)
        .onChange(of: app.showGlobalSearch) { _, isOn in
            if isOn {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
    }

    private var dateNav: some View {
        HStack(spacing: 2) {
            RoundIconButton(icon: "chevron.left") { app.moveDay(by: -1) }
            Button {
                app.goToday()
            } label: {
                Text(Fmt.dayLabel(app.selectedDay))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text)
                    .frame(minWidth: 70)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("回到今天")
            RoundIconButton(icon: "chevron.right") { app.moveDay(by: 1) }
        }
    }

    private var rightControls: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11))
                Text("本机")
                    .font(.system(size: 11))
            }
            .foregroundColor(Theme.secondary)
            .padding(.trailing, 4)

            filterMenu

            if app.showGlobalSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiary)
                    TextField("搜索记录", text: $app.globalSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text)
                        .focused($searchFocused)
                    Button {
                        app.globalSearch = ""
                        app.showGlobalSearch = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 7)
                .frame(width: 154, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.window)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1)
                )
            } else {
                ToolbarButton(icon: "magnifyingglass", title: "搜索") {
                    app.showGlobalSearch = true
                }
            }

            ToolbarButton(icon: "gearshape", title: "设置") {
                app.settingsPresented = true
            }
        }
    }

    private let allActivityID = "__all__"
    private let unassignedID = "__unassigned__"

    private var filterSelectedID: String {
        if app.unassignedOnly { return unassignedID }
        return app.selectedProjectID ?? allActivityID
    }

    private func filterOptions(matching query: String) -> [ProjectPickerOption] {
        var items = [
            ProjectPickerOption(id: allActivityID, title: "全部活动", colorHex: nil, depth: 0),
            ProjectPickerOption(id: unassignedID, title: "未分配", colorHex: nil, depth: 0)
        ]
        for project in app.pickerProjects(matching: query) {
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

    private var filterMenu: some View {
        Button {
            filterOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                Text("筛选条件")
                    .font(.system(size: 11))
            }
            .foregroundColor(app.filterDescription == nil ? Theme.secondary : Theme.orange)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(app.filterDescription == nil ? Color.clear : Theme.selection)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $filterOpen) {
            ProjectPickerPanel(
                selectedID: filterSelectedID,
                options: filterOptions(matching:),
                onPick: { id in
                    switch id {
                    case allActivityID:
                        app.selectAllActivity()
                    case unassignedID:
                        app.selectUnassigned()
                    default:
                        if let project = app.project(id) {
                            app.select(project: project)
                        }
                    }
                    filterOpen = false
                },
                isOpen: $filterOpen,
                fixedCount: 2
            )
        }
    }
}

struct FocusTimerPill: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var timer: FocusUpTimerModel

    var body: some View {
        if timer.isRunning {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.red)
                    .frame(width: 6, height: 6)
                Text(timer.title)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(Fmt.clock(timer.elapsed))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.orange)
                Button {
                    app.stopFocusTimer()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help("停止并记录")
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(Theme.panelAlt))
        }
    }
}

struct TempTimerPill: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var timer: TempTimerModel

    var body: some View {
        if timer.isRunning {
            Button {
                app.openTempTimer()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 10))
                    Text(Fmt.clock(timer.remaining))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundColor(Theme.orange)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Theme.orange.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("打开临时计时面板")
        }
    }
}
