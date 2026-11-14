import SwiftUI
import ChronicleCore

/// 应用轨道的一段：可能是真实活动区间，也可能是按屏幕分辨率聚合出的主要应用块。
struct AppBandSegment: Identifiable {
    let id: String
    let bundleID: String
    let name: String
    let color: Color
    let start: Date
    let end: Date
    /// true 表示这是缩小时的聚合块，只代表这段时间的主要应用
    let isBucketed: Bool
    let isOther: Bool
}

/// 项目归属轨道的一段：由互不重叠的 WorkSlice 合并而来。
struct ProjectBandSpan: Identifiable {
    let id: String
    let projectID: String?
    let color: Color
    let start: Date
    let end: Date

    var isUnassigned: Bool { projectID == nil }
}

/// 时间条目轨道的一块，lane 用于重叠条目并排。
struct TimelineEntryBlock: Identifiable {
    let id: String
    let entry: TimeEntry
    let lane: Int
    let color: Color
    let dimmed: Bool
}

enum TimelineData {
    /// 缩小时应用切换会碎成细线，按约 24px 一个时间桶取主要应用；放大到每小时 600px 后回到真实区间。
    static func appSegments(
        records: [AppUsageRecord],
        range: DateInterval,
        pixelsPerHour: CGFloat,
        color: @escaping (String) -> Color
    ) -> [AppBandSegment] {
        let rangeStart = range.start
        let rangeEnd = range.end
        let records = records
            .filter { $0.end > rangeStart && $0.start < rangeEnd }
            .sorted { $0.start < $1.start }
        guard !records.isEmpty else { return [] }

        var names: [String: String] = [:]
        for record in records {
            names[record.bundleID] = record.appName
        }

        if pixelsPerHour >= 600 {
            // 放大后展示真实活动区间，相邻且同应用的连续区间合并。
            var runs: [(bundleID: String, start: Date, end: Date)] = []
            for record in records {
                let from = max(record.start, rangeStart)
                let to = min(record.end, rangeEnd)
                guard to > from else { continue }
                if let last = runs.last, last.bundleID == record.bundleID, last.end >= from {
                    runs[runs.count - 1].end = max(last.end, to)
                } else {
                    runs.append((record.bundleID, from, to))
                }
            }
            return runs.map { run in
                return AppBandSegment(
                    id: "raw-\(run.bundleID)-\(run.start.timeIntervalSince1970)",
                    bundleID: run.bundleID,
                    name: names[run.bundleID] ?? run.bundleID,
                    color: color(run.bundleID),
                    start: run.start,
                    end: run.end,
                    isBucketed: false,
                    isOther: false
                )
            }
        }

        // 桶时长让每个桶大约占 24px，最小 30 分钟，避免一天被切成过多细线。
        let bucketSeconds = max(60.0, Double(24 / max(48, pixelsPerHour) * 3600))
        let bucketCount = max(1, Int(ceil(range.duration / bucketSeconds)))
        var buckets = Array(repeating: [String: TimeInterval](), count: bucketCount)

        for record in records {
            let from = max(record.start, rangeStart)
            let to = min(record.end, rangeEnd)
            guard to > from else { continue }
            var cursor = from
            while cursor < to {
                let offset = cursor.timeIntervalSince(rangeStart)
                let index = min(bucketCount - 1, max(0, Int(offset / bucketSeconds)))
                let bucketEnd = rangeStart.addingTimeInterval(Double(index + 1) * bucketSeconds)
                let sliceEnd = min(to, bucketEnd)
                let seconds = sliceEnd.timeIntervalSince(cursor)
                guard seconds > 0 else { break }
                buckets[index][record.bundleID, default: 0] += seconds
                cursor = sliceEnd
            }
        }

        // 每桶选占用最长的应用，并列时按 bundleID 稳定选择。
        var picks: [(bundleID: String, index: Int)] = []
        for (index, bucket) in buckets.enumerated() {
            guard let best = bucket.max(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }) else { continue }
            picks.append((best.key, index))
        }
        guard !picks.isEmpty else { return [] }

        var runs: [(bundleID: String, from: Int, to: Int)] = []
        for pick in picks {
            if let last = runs.last, last.bundleID == pick.bundleID, pick.index == last.to + 1 {
                runs[runs.count - 1].to = pick.index
            } else {
                runs.append((pick.bundleID, pick.index, pick.index))
            }
        }

        return runs.map { run in
            let start = rangeStart.addingTimeInterval(Double(run.from) * bucketSeconds)
            let end = min(rangeEnd, rangeStart.addingTimeInterval(Double(run.to + 1) * bucketSeconds))
            return AppBandSegment(
                id: "bucket-\(run.bundleID)-\(run.from)",
                bundleID: run.bundleID,
                name: names[run.bundleID] ?? run.bundleID,
                color: color(run.bundleID),
                start: start,
                end: end,
                isBucketed: true,
                isOther: false
            )
        }
    }

    /// 项目归属：直接使用统一快照的归属区间（条目优先、其次应用自身归属）。
    /// 只有实际有活动或条目的区间才绘制色带，不再把整天画成「未分配」。
    static func projectSpans(
        spans: [WorkSpan],
        range: DateInterval,
        color: @escaping (String?) -> Color
    ) -> [ProjectBandSpan] {
        var result: [ProjectBandSpan] = []
        for span in spans {
            let from = max(span.start, range.start)
            let to = min(span.end, range.end)
            guard to > from else { continue }
            if let last = result.last, last.projectID == span.projectID, last.end >= from {
                result[result.count - 1] = ProjectBandSpan(
                    id: last.id,
                    projectID: last.projectID,
                    color: last.color,
                    start: last.start,
                    end: max(last.end, to)
                )
            } else {
                result.append(ProjectBandSpan(
                    id: "span-\(from.timeIntervalSince1970)-\(span.projectID ?? "none")",
                    projectID: span.projectID,
                    color: color(span.projectID),
                    start: from,
                    end: to
                ))
            }
        }
        return result
    }

    /// 时间条目：重叠条目分子轨道，横向上下并排、竖向左右并排。
    static func entryBlocks(
        entries: [TimeEntry],
        range: DateInterval,
        color: @escaping (String?) -> Color,
        dimmed: @escaping (TimeEntry) -> Bool
    ) -> [TimelineEntryBlock] {
        let visible = entries
            .filter { $0.end > range.start && $0.start < range.end }
            .sorted { $0.start < $1.start }
        guard !visible.isEmpty else { return [] }

        var laneEnds: [Date] = []
        var result: [TimelineEntryBlock] = []
        for entry in visible {
            var lane = 0
            while lane < laneEnds.count, laneEnds[lane] > entry.start {
                lane += 1
            }
            if lane >= laneEnds.count {
                laneEnds.append(entry.end)
            } else {
                laneEnds[lane] = entry.end
            }
            result.append(TimelineEntryBlock(
                id: entry.id,
                entry: entry,
                // 保留真实 lane，不把多余的重叠条目压到最后一层（否则会互相覆盖）。
                lane: lane,
                color: color(entry.projectID),
                dimmed: dimmed(entry)
            ))
        }
        return result
    }
}
