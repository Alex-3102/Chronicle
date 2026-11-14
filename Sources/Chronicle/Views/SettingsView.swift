import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button {
                    dismiss()
                    app.settingsPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("外观")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.secondary)
                Picker("", selection: Binding(
                    get: { app.appearance },
                    set: { app.setAppearance($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("时间轴最大缩放")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.secondary)
                    Spacer()
                    Text("\(Int(app.timelineMaxZoom))×")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(Theme.text)
                }
                Slider(value: Binding(
                    get: { app.timelineMaxZoom },
                    set: { app.setTimelineMaxZoom($0.rounded()) }
                ), in: 1...24)
                Text("在活动页用 ⌘+ / ⌘- 或工具栏放大镜调整时间轴。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { app.timelineZoomToWorkHours },
                    set: { app.setTimelineZoomToWorkHours($0) }
                )) {
                    Text("时间轴只显示工作时段")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                HStack(spacing: 8) {
                    Text("工作时段")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondary)
                    Spacer()
                    Text(timeText(app.workdayStartMinutes))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(Theme.text)
                    Text("–")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.tertiary)
                    Text(timeText(app.workdayEndMinutes))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(Theme.text)
                }
                Text("有记录超出这个范围时，时间轴会自动向外扩展到整点。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("辅助功能权限")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.secondary)
                    Spacer()
                    if app.accessibilityTrusted {
                        Text("已授权")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.green)
                    } else {
                        Button("去授权") { app.requestAccessibility() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.orange)
                        if app.accessibilityNoticeDismissed {
                            Button("重新提醒") { app.restoreAccessibilityNotice() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.secondary)
                        }
                    }
                }
                Text("用于记录窗口标题；未授权时其余使用时长照常统计。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 430, height: 380)
        .background(Theme.panel)
    }

    private func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
