import SwiftUI
import ChronicleCore

struct StatsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        StatsContent(tracker: app.tracker)
            .background(Theme.window)
    }
}

struct StatsContent: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tracker: AppUsageTracker

    var body: some View {
        let usageTotals = app.scopedUsageTotals
        let usageSeconds = usageTotals.reduce(0) { $0 + $1.seconds }
        let breakdown = projectBreakdown

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        MetricCard(
                            title: app.scopeName == nil ? "记录总时长" : "\(app.scopeName!) 记录时长",
                            value: Fmt.human(app.scopedTotal),
                            icon: "clock",
                            accent: Theme.orange
                        )
                        MetricCard(
                            title: "应用使用",
                            value: Fmt.human(usageSeconds),
                            icon: "desktopcomputer",
                            accent: Theme.blue
                        )
                        MetricCard(
                            title: "活跃项目",
                            value: "\(breakdown.count)",
                            icon: "folder",
                            accent: Theme.green
                        )
                    }

                    section("项目分布") {
                        if breakdown.isEmpty {
                            EmptyStateText(text: "这一天还没有项目记录。")
                        } else {
                            let maxSeconds = breakdown.first?.seconds ?? 1
                            VStack(spacing: 10) {
                                ForEach(breakdown) { item in
                                    RankRow(
                                        color: Color(hexString: item.project.colorHex),
                                        title: item.project.name,
                                        subtitle: nil,
                                        seconds: item.seconds,
                                        maxSeconds: maxSeconds
                                    )
                                }
                            }
                        }
                    }

                    section("应用使用排行") {
                        if usageTotals.isEmpty {
                            EmptyStateText(text: "还没有捕获到应用使用数据。")
                        } else {
                            let maxSeconds = usageTotals.first?.seconds ?? 1
                            VStack(spacing: 10) {
                                ForEach(usageTotals.prefix(8)) { item in
                                    RankRow(
                                        color: Theme.appColor(for: item.bundleID),
                                        title: item.appName,
                                        subtitle: item.bundleID,
                                        seconds: item.seconds,
                                        maxSeconds: maxSeconds
                                    )
                                }
                            }
                        }
                    }

                    section("今日记录") {
                        let scoped = app.scopedEntries
                        if scoped.isEmpty {
                            EmptyStateText(text: "还没有时间条目，点击「新建时间条目」开始记录。")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(scoped) { entry in
                                    entryRow(entry)
                                    if entry.id != scoped.last?.id {
                                        Divider().overlay(Theme.divider.opacity(0.6))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.scopeName.map { "统计 · \($0)" } ?? "统计")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text("\(Fmt.dayLong(app.selectedDay)) · 记录 \(app.scopedEntries.count) 条")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    /// 当前筛选范围内的项目时长分布（选中项目时包含其子项目）。
    private var projectBreakdown: [ProjectBreakdownItem] {
        var totals: [String: TimeInterval] = [:]
        for entry in app.scopedEntries {
            guard let projectID = entry.projectID else { continue }
            totals[projectID, default: 0] += app.clampedDuration(entry)
        }
        if app.unassignedOnly, app.scopedTotal > 0 {
            // 未分配范围下没有项目，单独展示一条灰色「未分配」。
            let placeholder = Project(id: "unassigned", name: "未分配", colorHex: "#8E8E93")
            return [ProjectBreakdownItem(project: placeholder, seconds: app.scopedTotal)]
        }
        return app.projects
            .compactMap { project -> ProjectBreakdownItem? in
                guard let seconds = totals[project.id], seconds > 0 else { return nil }
                return ProjectBreakdownItem(project: project, seconds: seconds)
            }
            .sorted { $0.seconds > $1.seconds }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
        )
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.color(for: entry.projectID))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text("\(app.project(entry.projectID)?.name ?? "未分配") · \(Fmt.timeOfDay(entry.start)) – \(Fmt.timeOfDay(entry.end))")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Fmt.sidebar(app.clampedDuration(entry)))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundColor(Theme.secondary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            Button("删除记录", role: .destructive) { app.deleteEntry(entry) }
        }
    }
}

struct ProjectBreakdownItem: Identifiable {
    let project: Project
    let seconds: TimeInterval
    var id: String { project.id }
}

struct RankRow: View {
    let color: Color
    let title: String
    let subtitle: String?
    let seconds: TimeInterval
    let maxSeconds: TimeInterval

    private var fraction: Double {
        maxSeconds > 0 ? seconds / maxSeconds : 0
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.text.opacity(0.92))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.sidebar(seconds))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
            DurationBar(fraction: fraction, color: color.opacity(0.8), height: 4)
        }
    }
}
