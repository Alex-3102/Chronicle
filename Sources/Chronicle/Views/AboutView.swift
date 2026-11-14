import SwiftUI
import AppKit

/// 自定义「关于 Chronicle」窗口：图标、版本、口号与三条能力说明。
struct AboutView: View {
    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "版本 \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .padding(.top, 28)

            Text("Chronicle")
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(Theme.text)
                .padding(.top, 14)

            Text(versionText)
                .font(.system(size: 11))
                .foregroundColor(Theme.secondary)
                .padding(.top, 3)

            Text("让每一段时间，都清晰可见")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)
                .padding(.top, 20)

            Text("本地优先的 macOS 时间追踪应用")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 15) {
                featureRow(
                    icon: "clock",
                    title: "自动记录",
                    detail: "记录应用与窗口活动，串联一天的工作轨迹。"
                )
                featureRow(
                    icon: "folder",
                    title: "项目归类",
                    detail: "按项目整理时间，结合规则自动归类。"
                )
                featureRow(
                    icon: "chart.bar",
                    title: "统计与报表",
                    detail: "查看时间分布与项目报表，支持导出时间记录。"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.panelAlt)
            )
            .padding(.horizontal, 28)
            .padding(.top, 20)

            HStack(spacing: 5) {
                Image(systemName: "lock")
                    .font(.system(size: 9))
                Text("活动、项目与设置保存在本机")
                    .font(.system(size: 10.5))
            }
            .foregroundColor(Theme.tertiary)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 380)
        .background(Theme.window)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
