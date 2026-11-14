import Foundation

/// 统一时间切片：把应用活动和手动条目按所有起止边界切开，保证互不重叠。
/// 时间轴、统计、报告都从切片派生，不再各自累加。
public struct WorkSlice: Hashable {
    public let start: Date
    public let end: Date
    /// 该时段的前台应用活动（即使被手动条目覆盖也保留，供应用维度统计）
    public let activity: AppUsageRecord?
    /// 该时段生效的时间条目（重叠时取开始较晚的）
    public let entry: TimeEntry?
    /// 项目归属：条目优先，其次应用记录自身的归属
    public let projectID: String?

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    public init(start: Date, end: Date, activity: AppUsageRecord?, entry: TimeEntry?, projectID: String?) {
        self.start = start
        self.end = end
        self.activity = activity
        self.entry = entry
        self.projectID = projectID
    }
}

/// 合并后的归属区间，供项目轨道和项目总时长使用。
public struct WorkSpan: Hashable {
    public let start: Date
    public let end: Date
    public let projectID: String?

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    public init(start: Date, end: Date, projectID: String?) {
        self.start = start
        self.end = end
        self.projectID = projectID
    }
}

public enum TimeAccounting {
    /// 生成互不重叠的切片。区间按 [from, to) 处理，未结束的记录截到 now。
    public static func slices(
        usage: [AppUsageRecord],
        entries: [TimeEntry],
        from: Date,
        to: Date,
        now: Date = Date()
    ) -> [WorkSlice] {
        let limit = min(to, max(from, now))
        guard limit > from else { return [] }

        struct Interval {
            let start: Date
            let end: Date
            let activity: AppUsageRecord?
            let entry: TimeEntry?
        }

        var intervals: [Interval] = []
        for record in usage where record.end > from && record.start < limit {
            let start = max(record.start, from)
            let end = min(record.end, limit)
            guard end > start else { continue }
            intervals.append(Interval(start: start, end: end, activity: record, entry: nil))
        }
        for entry in entries where entry.end > from && entry.start < limit {
            let start = max(entry.start, from)
            let end = min(entry.end, limit)
            guard end > start else { continue }
            intervals.append(Interval(start: start, end: end, activity: nil, entry: entry))
        }
        guard !intervals.isEmpty else { return [] }

        var boundarySet = Set<Date>()
        boundarySet.insert(from)
        boundarySet.insert(limit)
        for interval in intervals {
            boundarySet.insert(interval.start)
            boundarySet.insert(interval.end)
        }
        let boundaries = boundarySet.sorted()

        var result: [WorkSlice] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }

            let coveringEntry = intervals
                .filter { $0.entry != nil && $0.start <= start && $0.end >= end }
                .max { lhs, rhs in
                    if lhs.start != rhs.start { return lhs.start < rhs.start }
                    return (lhs.entry?.id ?? "") > (rhs.entry?.id ?? "")
                }?
                .entry
            let coveringActivity = intervals
                .filter { $0.activity != nil && $0.start <= start && $0.end >= end }
                .max { lhs, rhs in
                    if lhs.start != rhs.start { return lhs.start < rhs.start }
                    return (lhs.activity?.id ?? "") > (rhs.activity?.id ?? "")
                }?
                .activity

            guard coveringEntry != nil || coveringActivity != nil else { continue }
            let projectID = coveringEntry?.projectID ?? coveringActivity?.projectID

            if let last = result.last,
               last.entry?.id == coveringEntry?.id,
               last.activity?.id == coveringActivity?.id,
               last.projectID == projectID {
                result[result.count - 1] = WorkSlice(
                    start: last.start,
                    end: end,
                    activity: coveringActivity,
                    entry: coveringEntry,
                    projectID: projectID
                )
            } else {
                result.append(WorkSlice(
                    start: start,
                    end: end,
                    activity: coveringActivity,
                    entry: coveringEntry,
                    projectID: projectID
                ))
            }
        }
        return result
    }

    /// 把相邻且归属相同的切片合并成归属区间。
    public static func spans(from slices: [WorkSlice]) -> [WorkSpan] {
        var spans: [WorkSpan] = []
        for slice in slices {
            if let last = spans.last, last.projectID == slice.projectID, last.end >= slice.start {
                spans[spans.count - 1] = WorkSpan(
                    start: last.start,
                    end: max(last.end, slice.end),
                    projectID: last.projectID
                )
            } else {
                spans.append(WorkSpan(start: slice.start, end: slice.end, projectID: slice.projectID))
            }
        }
        return spans
    }

    /// 合并重叠区间的总时长。
    public static func unionDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var cursor: Date?
        for interval in sorted {
            if let start = cursor {
                if interval.start > start {
                    total += interval.duration
                    cursor = interval.end
                } else if interval.end > start {
                    total += interval.end.timeIntervalSince(start)
                    cursor = interval.end
                }
            } else {
                total += interval.duration
                cursor = interval.end
            }
        }
        return total
    }
}
