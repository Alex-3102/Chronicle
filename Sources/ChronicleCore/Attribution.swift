import Foundation

/// 按「项目 + 日期」保存的耗时归因。
public struct Attribution: Identifiable, Hashable {
    public var projectID: String
    /// 本地日期键 yyyy-MM-dd
    public var day: String
    public var reason: String
    public var hasUnexpected: Bool
    public var unexpectedDetail: String
    public var canOptimize: Bool
    public var optimizationDetail: String

    public var id: String { "\(projectID)|\(day)" }

    public init(
        projectID: String,
        day: String,
        reason: String = "",
        hasUnexpected: Bool = false,
        unexpectedDetail: String = "",
        canOptimize: Bool = false,
        optimizationDetail: String = ""
    ) {
        self.projectID = projectID
        self.day = day
        self.reason = reason
        self.hasUnexpected = hasUnexpected
        self.unexpectedDetail = unexpectedDetail
        self.canOptimize = canOptimize
        self.optimizationDetail = optimizationDetail
    }

    public var isEmpty: Bool {
        reason.isEmpty && !hasUnexpected && unexpectedDetail.isEmpty
            && !canOptimize && optimizationDetail.isEmpty
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

extension ChronicleStore {
    public func attribution(projectID: String, day: String) -> Attribution? {
        let rows = (try? db.query("""
        SELECT project_id, day, reason, has_unexpected, unexpected_detail, can_optimize, optimization_detail
        FROM attribution WHERE project_id = ? AND day = ?
        """, [.text(projectID), .text(day)])) ?? []
        return rows.first.flatMap(attribution(from:))
    }

    /// 按日期键闭区间查询，用于周 / 月汇总。
    public func attributions(from startDay: String, to endDay: String) -> [Attribution] {
        let rows = (try? db.query("""
        SELECT project_id, day, reason, has_unexpected, unexpected_detail, can_optimize, optimization_detail
        FROM attribution WHERE day >= ? AND day <= ? ORDER BY day ASC
        """, [.text(startDay), .text(endDay)])) ?? []
        return rows.compactMap(attribution(from:))
    }

    public func saveAttribution(_ item: Attribution) {
        try? db.run("""
        INSERT OR REPLACE INTO attribution
        (project_id, day, reason, has_unexpected, unexpected_detail, can_optimize, optimization_detail)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(item.projectID),
            .text(item.day),
            .text(item.reason),
            .double(item.hasUnexpected ? 1 : 0),
            .text(item.unexpectedDetail),
            .double(item.canOptimize ? 1 : 0),
            .text(item.optimizationDetail)
        ])
    }

    private func attribution(from row: SQLRow) -> Attribution? {
        guard let projectID = row.text("project_id"), let day = row.text("day") else { return nil }
        return Attribution(
            projectID: projectID,
            day: day,
            reason: row.text("reason") ?? "",
            hasUnexpected: (row.int("has_unexpected") ?? 0) != 0,
            unexpectedDetail: row.text("unexpected_detail") ?? "",
            canOptimize: (row.int("can_optimize") ?? 0) != 0,
            optimizationDetail: row.text("optimization_detail") ?? ""
        )
    }
}
