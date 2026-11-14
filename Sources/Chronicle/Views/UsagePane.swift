import SwiftUI
import ChronicleCore

struct UsagePane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        UsageContent(tracker: app.tracker)
            .background(Theme.panel)
    }
}

struct UsageContent: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var tracker: AppUsageTracker

    var body: some View {
        let totals = app.dayUsageTotals
        let totalSeconds = totals.reduce(0) { $0 + $1.seconds }

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("应用使用")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(Fmt.sidebar(totalSeconds))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider().overlay(Theme.divider)

            if totals.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(Theme.tertiary)
                    Text("正在等待应用使用数据…")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        UsageStrip(records: app.dayUsageRecords, start: app.dayInterval.start)
                            .frame(height: 84)

                        Text(app.isToday ? "今天的时间轴" : "\(Fmt.monthDay(app.selectedDay)) 的时间轴")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.tertiary)

                        Divider().overlay(Theme.divider)

                        ForEach(totals) { item in
                            UsageRow(total: item, maxSeconds: totals.first?.seconds ?? 1)
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

struct UsageStrip: View {
    let records: [AppUsageRecord]
    let start: Date

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let dayEnd = start.addingTimeInterval(86400)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.035))

                ForEach(segments(width: width, dayEnd: dayEnd)) { segment in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(segment.color.opacity(0.9))
                        .frame(width: max(1, segment.width), height: 74)
                        .offset(x: segment.x, y: 5)
                }

                ForEach(0..<5) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 0.5, height: 74)
                        .offset(x: CGFloat(index) / 4 * width, y: 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func segments(width: CGFloat, dayEnd: Date) -> [UsageSegment] {
        records.compactMap { record in
            let from = max(record.start, start)
            let to = min(record.end, dayEnd)
            guard to > from else { return nil }
            return UsageSegment(
                id: record.id,
                name: record.appName,
                color: Theme.appColor(for: record.bundleID),
                x: CGFloat(from.timeIntervalSince(start) / 86400) * width,
                width: CGFloat(to.timeIntervalSince(from) / 86400) * width
            )
        }
    }
}

struct UsageRow: View {
    let total: AppUsageTotal
    let maxSeconds: TimeInterval

    private var fraction: Double {
        maxSeconds > 0 ? total.seconds / maxSeconds : 0
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                if let icon = AppIconCache.shared.icon(for: total.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                } else {
                    Circle()
                        .fill(Theme.appColor(for: total.bundleID))
                        .frame(width: 7, height: 7)
                }
                Text(total.appName)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.text.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Fmt.sidebar(total.seconds))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
            DurationBar(
                fraction: fraction,
                color: Theme.appColor(for: total.bundleID).opacity(0.75),
                height: 3
            )
        }
    }
}
