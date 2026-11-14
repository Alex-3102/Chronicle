import Foundation
import ChronicleCore

/// 某一天（或任意范围）的统一时间快照：时间轴、统计、报告都从这里派生。
struct AccountingSnapshot {
    let slices: [WorkSlice]
    let spans: [WorkSpan]

    /// 真实总时长：互不重叠的切片之和。
    var total: TimeInterval {
        slices.reduce(0) { $0 + $1.duration }
    }

    static func make(
        usage: [AppUsageRecord],
        entries: [TimeEntry],
        range: DateInterval,
        now: Date
    ) -> AccountingSnapshot {
        let slices = TimeAccounting.slices(
            usage: usage,
            entries: entries,
            from: range.start,
            to: range.end,
            now: now
        )
        return AccountingSnapshot(slices: slices, spans: TimeAccounting.spans(from: slices))
    }

    /// 该时刻生效的切片（供悬浮卡片使用）。
    func slice(at date: Date) -> WorkSlice? {
        slices.first { $0.start <= date && $0.end > date }
    }
}
