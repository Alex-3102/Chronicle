import Foundation
import ChronicleCore

/// 统计范围：统计页顶部切换。
enum StatisticsRange: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }
}

/// 柱状图聚合粒度。
enum StatisticsUnit {
    case hour, day, week, month
}

enum StatisticsDimension {
    case project, application
}

/// 一个柱子里某一段（项目或应用）。
struct BucketPart: Identifiable {
    let id: String
    let seconds: TimeInterval
}

struct StatisticsBucket: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let parts: [BucketPart]

    var total: TimeInterval {
        parts.reduce(0) { $0 + $1.seconds }
    }
}

/// 分布条目：项目或应用。
struct ShareItem: Identifiable {
    let id: String
    let name: String
    let seconds: TimeInterval
    let colorHex: String
    let bundleID: String?
    let projectID: String?
    let parentID: String?
    let isUnassigned: Bool
}

struct StatisticsSnapshot {
    let interval: DateInterval
    let range: StatisticsRange
    let unit: StatisticsUnit
    let slices: [WorkSlice]
    let buckets: [StatisticsBucket]
    let projects: [ShareItem]
    let applications: [ShareItem]
    let entries: [TimeEntry]
    /// 24 小时分布，用于「最活跃时段」。
    let hourly: [TimeInterval]

    var total: TimeInterval {
        slices.reduce(0) { $0 + $1.duration }
    }

    var dayCount: Int {
        max(1, Calendar.current.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
    }

    var dailyAverage: TimeInterval {
        total / Double(dayCount)
    }

    /// 最活跃的一天（日范围内为最活跃的小时）。
    var mostActiveBucket: StatisticsBucket? {
        buckets.max { $0.total < $1.total }
    }

    /// 最活跃时段（按小时聚合）。
    var mostActiveHour: (hour: Int, seconds: TimeInterval)? {
        guard let index = hourly.indices.max(by: { hourly[$0] < hourly[$1] }), hourly[index] > 0 else {
            return nil
        }
        return (index, hourly[index])
    }

    func seconds(projectID: String) -> TimeInterval {
        projects.filter { $0.projectID == projectID }.reduce(0) { $0 + $1.seconds }
    }
}

enum StatisticsEngine {
    static func unit(for range: StatisticsRange) -> StatisticsUnit {
        switch range {
        case .day: return .hour
        case .week, .month: return .day
        case .year: return .month
        }
    }

    static func interval(for range: StatisticsRange, day: Date, calendar: Calendar = .current) -> DateInterval {
        switch range {
        case .day:
            let start = calendar.startOfDay(for: day)
            return DateInterval(start: start, duration: 24 * 60 * 60)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: day)
                ?? DateInterval(start: day, duration: 7 * 24 * 3600)
        case .month:
            return calendar.dateInterval(of: .month, for: day)
                ?? DateInterval(start: day, duration: 30 * 24 * 3600)
        case .year:
            return calendar.dateInterval(of: .year, for: day)
                ?? DateInterval(start: day, duration: 365 * 24 * 3600)
        }
    }

    static func buckets(
        slices: [WorkSlice],
        interval: DateInterval,
        unit: StatisticsUnit,
        calendar: Calendar = .current
    ) -> [StatisticsBucket] {
        var boundaries: [Date] = []
        var cursor = alignedStart(interval.start, unit: unit, calendar: calendar)
        while cursor < interval.end {
            boundaries.append(cursor)
            cursor = next(cursor, unit: unit, calendar: calendar)
        }
        boundaries.append(max(interval.end, boundaries.last ?? interval.end))

        var result: [StatisticsBucket] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }
            result.append(StatisticsBucket(
                id: "bucket-\(start.timeIntervalSince1970)",
                start: start,
                end: end,
                parts: []
            ))
        }

        // 把每个切片按重叠时长分配到桶里。
        var parts: [[String: TimeInterval]] = Array(repeating: [:], count: result.count)
        for slice in slices {
            for index in result.indices where slice.end > result[index].start && slice.start < result[index].end {
                let from = max(slice.start, result[index].start)
                let to = min(slice.end, result[index].end)
                guard to > from else { continue }
                let key = slice.projectID ?? "__unassigned__"
                parts[index][key, default: 0] += to.timeIntervalSince(from)
            }
        }

        return result.indices.map { index in
            StatisticsBucket(
                id: result[index].id,
                start: result[index].start,
                end: result[index].end,
                parts: parts[index]
                    .map { BucketPart(id: $0.key, seconds: $0.value) }
                    .sorted { $0.seconds > $1.seconds }
            )
        }
    }

    static func projectShares(
        slices: [WorkSlice],
        projects: [Project]
    ) -> [ShareItem] {
        var totals: [String: TimeInterval] = [:]
        for slice in slices {
            let key = slice.projectID ?? "__unassigned__"
            totals[key, default: 0] += slice.duration
        }
        let byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var items: [ShareItem] = totals.map { key, seconds in
            if key == "__unassigned__" {
                return ShareItem(
                    id: key,
                    name: "未分配",
                    seconds: seconds,
                    colorHex: "#8E8E93",
                    bundleID: nil,
                    projectID: nil,
                    parentID: nil,
                    isUnassigned: true
                )
            }
            let project = byID[key]
            return ShareItem(
                id: key,
                name: project?.name ?? "已删除项目",
                seconds: seconds,
                colorHex: project?.colorHex ?? "#8E8E93",
                bundleID: nil,
                projectID: key,
                parentID: project?.parentID,
                isUnassigned: false
            )
        }
        items.sort { $0.seconds > $1.seconds }
        return items
    }

    static func appShares(
        slices: [WorkSlice]
    ) -> [ShareItem] {
        var totals: [String: TimeInterval] = [:]
        var names: [String: String] = [:]
        for slice in slices {
            guard let activity = slice.activity else { continue }
            let key = activity.bundleID.isEmpty ? activity.appName : activity.bundleID
            totals[key, default: 0] += slice.duration
            names[key] = activity.appName
        }
        return totals
            .map { key, seconds in
                ShareItem(
                    id: key,
                    name: names[key] ?? key,
                    seconds: seconds,
                    colorHex: "",
                    bundleID: key,
                    projectID: nil,
                    parentID: nil,
                    isUnassigned: false
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }

    static func hourly(slices: [WorkSlice], calendar: Calendar = .current) -> [TimeInterval] {
        var values = [TimeInterval](repeating: 0, count: 24)
        for slice in slices {
            var cursor = slice.start
            while cursor < slice.end {
                let hour = calendar.component(.hour, from: cursor)
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? slice.end
                let to = min(hourEnd, slice.end)
                values[hour] += to.timeIntervalSince(cursor)
                cursor = to
            }
        }
        return values
    }

    private static func alignedStart(_ date: Date, unit: StatisticsUnit, calendar: Calendar) -> Date {
        switch unit {
        case .hour: return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        case .day: return calendar.startOfDay(for: date)
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .month: return calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private static func next(_ date: Date, unit: StatisticsUnit, calendar: Calendar) -> Date {
        switch unit {
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: date) ?? date.addingTimeInterval(3600)
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date.addingTimeInterval(7 * 86400)
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(31 * 86400)
        }
    }
}
