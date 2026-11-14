import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 236)
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            VStack(spacing: 0) {
                HeaderBar()
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                if !app.accessibilityTrusted && !app.accessibilityNoticeDismissed {
                    AccessibilityNoticeBar()
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                }
                content
            }
        }
        .background(Theme.window)
        .frame(minWidth: 1080, minHeight: 660)
        .sheet(isPresented: $app.newEntryPresented) {
            NewEntrySheet(presetRange: app.newEntryDraftRange).environmentObject(app)
        }
        .sheet(isPresented: $app.newProjectPresented) {
            NewProjectSheet(presetParentID: app.newProjectParentID).environmentObject(app)
        }
        .sheet(isPresented: $app.startTimerPresented) {
            StartTimerSheet().environmentObject(app)
        }
        .sheet(item: $app.editingProject) { project in
            NewProjectSheet(editing: project).environmentObject(app)
        }
        .sheet(item: $app.editingEntry) { entry in
            NewEntrySheet(editing: entry).environmentObject(app)
        }
        .sheet(isPresented: $app.settingsPresented) {
            SettingsView().environmentObject(app)
        }
        .onAppear { app.startServices() }
    }

    @ViewBuilder
    private var content: some View {
        switch app.section {
        case .activity:
            HStack(spacing: 0) {
                TimelinePane()
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
                UsagePane()
                    .frame(width: 296)
            }
        case .stats:
            StatsView()
        case .reports:
            ReportsView()
        }
    }
}

/// 未授权辅助功能时，在所有 tab 上方显示一条提示；关掉后整块区域消失。
struct AccessibilityNoticeBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Theme.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("未开启辅助功能权限")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.text)
                Text("无法记录窗口标题；应用使用时长仍会正常统计。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondary)
            }

            Spacer(minLength: 8)

            Button("去授权") {
                app.requestAccessibility()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.orange)

            Button {
                app.dismissAccessibilityNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("本次运行不再提示")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.orange.opacity(0.08))
    }
}
