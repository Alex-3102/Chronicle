import SwiftUI
import ChronicleCore

struct DayStat: Identifiable {
    let id: Date
    let day: Date
    let entriesSeconds: TimeInterval
    let usageSeconds: TimeInterval
    let entryCount: Int
    let topProjectName: String?
}

struct ReportsView: View {
    @EnvironmentObject var app: AppState

    private var isScoped: Bool {
        app.unassignedOnly || app.selectedProjectID != nil
    }

    /// 只保留当前筛选范围内的条目。
    private func scopedEntries(_ list: [TimeEntry]) -> [TimeEntry] {
        if app.unassignedOnly {
            return list.filter { $0.projectID == nil }
        }
        guard app.selectedProjectID != nil else { return list }
        let ids = app.selectionProjectIDs
        return list.filter { $0.projectID.map(ids.contains) ?? false }
    }

    /// 范围内应用使用 = 应用记录落在这些条目时间区间内的部分。
    private func usageSeconds(records: [AppUsageRecord], entries: [TimeEntry], start: Date, end: Date) -> TimeInterval {
        guard isScoped else {
            return app.store.usageTotals(records: records, from: start, to: end)
                .reduce(0) { $0 + $1.seconds }
        }
        let ranges = entries
            .map { DateInterval(start: max($0.start, start), end: min($0.end, end)) }
            .filter { $0.duration > 0 }
        guard !ranges.isEmpty else { return 0 }
        var total: TimeInterval = 0
        for record in records {
            for range in ranges {
                total += max(0, min(record.end, range.end).timeIntervalSince(max(record.start, range.start)))
            }
        }
        return total
    }

    private var days: [DayStat] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: app.selectedDay)
        return (0..<7).reversed().compactMap { offset -> DayStat? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchor) else { return nil }
            let start = calendar.startOfDay(for: day)
            let end = start.addingTimeInterval(86400)

            let entries = scopedEntries(app.store.entries(from: start, to: end))
            let total = entries.reduce(0) { $0 + $1.duration }
            let usageRecords = app.store.usage(from: start, to: end)
            let usage = usageSeconds(records: usageRecords, entries: entries, start: start, end: end)

            var perProject: [String: TimeInterval] = [:]
            for entry in entries where entry.projectID != nil {
                perProject[entry.projectID!, default: 0] += entry.duration
            }
            let topID = perProject.max { $0.value < $1.value }?.key

            return DayStat(
                id: start,
                day: start,
                entriesSeconds: total,
                usageSeconds: usage,
                entryCount: entries.count,
                topProjectName: app.unassignedOnly ? "未分配" : app.project(topID)?.name
            )
        }
    }

    private var weekTotal: TimeInterval {
        days.reduce(0) { $0 + $1.entriesSeconds }
    }

    private var weekUsage: TimeInterval {
        days.reduce(0) { $0 + $1.usageSeconds }
    }

    private var maxSeconds: TimeInterval {
        max(days.map(\.entriesSeconds).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        MetricCard(
                            title: "本周记录",
                            value: Fmt.human(weekTotal),
                            icon: "calendar",
                            accent: Theme.orange
                        )
                        MetricCard(
                            title: "本周应用使用",
                            value: Fmt.human(weekUsage),
                            icon: "desktopcomputer",
                            accent: Theme.blue
                        )
                        MetricCard(
                            title: "记录条数",
                            value: "\(days.reduce(0) { $0 + $1.entryCount })",
                            icon: "list.bullet",
                            accent: Theme.green
                        )
                    }

                    chartSection
                    dayListSection
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
        .background(Theme.window)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.scopeName.map { "报告 · \($0)" } ?? "报告")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text("截至 \(Fmt.dayLabel(app.selectedDay)) 的最近 7 天")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "每日记录时长")

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { stat in
                    VStack(spacing: 6) {
                        Text(Fmt.sidebar(stat.entriesSeconds))
                            .font(.system(size: 8.5))
                            .monospacedDigit()
                            .foregroundColor(Theme.secondary)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                Calendar.current.isDateInToday(stat.day)
                                    ? Theme.orange
                                    : Theme.orange.opacity(0.55)
                            )
                            .frame(
                                width: 28,
                                height: max(3, CGFloat(stat.entriesSeconds / maxSeconds) * 118)
                            )

                        Text(Fmt.weekday(stat.day))
                            .font(.system(size: 9))
                            .foregroundColor(Calendar.current.isDateInToday(stat.day) ? Theme.orange : Theme.secondary)
                        Text(Fmt.monthDay(stat.day))
                            .font(.system(size: 8))
                            .foregroundColor(Theme.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 172, alignment: .bottom)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
        )
    }

    private var dayListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "每日明细")

            VStack(spacing: 0) {
                ForEach(days) { stat in
                    HStack(spacing: 10) {
                        Text(Fmt.monthDay(stat.day))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.text)
                            .frame(width: 54, alignment: .leading)
                        Text(Fmt.weekday(stat.day))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.tertiary)
                            .frame(width: 32, alignment: .leading)
                        Text(stat.topProjectName ?? "—")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(stat.entryCount) 条")
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.tertiary)
                        Text(Fmt.sidebar(stat.usageSeconds))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(Theme.blue.opacity(0.85))
                            .frame(width: 46, alignment: .trailing)
                        Text(Fmt.sidebar(stat.entriesSeconds))
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundColor(Theme.text)
                            .frame(width: 46, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        app.selectedDay = stat.day
                        app.reload()
                        app.section = .activity
                    }

                    if stat.id != days.last?.id {
                        Divider().overlay(Theme.divider.opacity(0.6))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
        )
    }
}
