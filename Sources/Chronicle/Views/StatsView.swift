import SwiftUI
import AppKit
import ChronicleCore

struct StatsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        StatsContent()
            .background(Theme.window)
    }
}

struct StatsContent: View {
    @EnvironmentObject var app: AppState

    @State private var dimension: StatisticsDimension = .project
    @State private var hoveredBucket: String?
    @State private var hoveredShare: String?
    @State private var expanded: Set<String> = []

    var body: some View {
        let snapshot = app.statistics(app.statisticsRange)

        VStack(alignment: .leading, spacing: 0) {
            header(snapshot)
            Divider().overlay(Theme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(snapshot)
                    barChart(snapshot)
                    HStack(alignment: .top, spacing: 14) {
                        distribution(snapshot)
                    }
                    projectTree(snapshot)
                    AttributionSection(snapshot: snapshot)
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - 头部

    private func header(_ snapshot: StatisticsSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("统计")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text("\(rangeText(snapshot)) · 总时长 \(Fmt.human(snapshot.total))")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
            }

            Spacer()

            segment(
                items: StatisticsRange.allCases.map { ($0.rawValue, $0.title) },
                selection: app.statisticsRange.rawValue
            ) { raw in
                if let value = StatisticsRange(rawValue: raw) {
                    app.statisticsRange = value
                }
            }

            segment(
                items: [("project", "按项目"), ("app", "按应用")],
                selection: dimension == .project ? "project" : "app"
            ) { raw in
                dimension = raw == "project" ? .project : .application
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private func segment(
        items: [(String, String)],
        selection: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let active = item.0 == selection
                Button {
                    onSelect(item.0)
                } label: {
                    Text(item.1)
                        .font(.system(size: 10.5, weight: active ? .medium : .regular))
                        .foregroundColor(active ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(active ? Theme.selection : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.panelAlt.opacity(0.8))
        )
    }

    // MARK: - 汇总

    private func summary(_ snapshot: StatisticsSnapshot) -> some View {
        HStack(spacing: 12) {
            MetricCard(
                title: "总时长",
                value: Fmt.human(snapshot.total),
                icon: "clock",
                accent: Theme.orange
            )
            MetricCard(
                title: "日均",
                value: Fmt.human(snapshot.dailyAverage),
                icon: "calendar",
                accent: Theme.blue
            )
            MetricCard(
                title: snapshot.range == .day ? "最活跃时段" : "最活跃日期",
                value: mostActiveText(snapshot),
                icon: "chart.bar",
                accent: Theme.green
            )
            MetricCard(
                title: "活跃项目",
                value: "\(snapshot.projects.filter { !$0.isUnassigned && $0.seconds > 0 }.count)",
                icon: "folder",
                accent: Theme.red
            )
        }
    }

    private func mostActiveText(_ snapshot: StatisticsSnapshot) -> String {
        guard let bucket = snapshot.mostActiveBucket, bucket.total > 0 else { return "—" }
        if snapshot.range == .day, let hour = snapshot.mostActiveHour {
            return String(format: "%02d:00–%02d:00", hour.hour, hour.hour + 1)
        }
        return "\(bucketLabel(bucket.start, unit: snapshot.unit)) · \(Fmt.human(bucket.total))"
    }

    // MARK: - 堆叠柱状图

    private func barChart(_ snapshot: StatisticsSnapshot) -> some View {
        card {
            HStack {
                SectionLabel(title: dimension == .project ? "项目分布" : "应用分布")
                Spacer()
                Text("共 \(snapshot.buckets.count) \(unitName(snapshot.unit))")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.tertiary)
            }

            if snapshot.total <= 0 {
                EmptyStateText(text: "这个范围还没有记录。")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                StackedBarChart(
                    snapshot: snapshot,
                    dimension: dimension,
                    color: color(for:),
                    hovered: $hoveredBucket
                )
                .frame(height: 190)
            }
        }
    }

    private func color(for id: String) -> Color {
        if dimension == .application {
            return Theme.appColor(for: id)
        }
        if id == "__unassigned__" { return Color(hexString: "#8E8E93") }
        return app.color(for: id)
    }

    // MARK: - 两个分布

    private func distribution(_ snapshot: StatisticsSnapshot) -> some View {
        DistributionLayout(spacing: 14) {
            donutCard(
                title: "应用分布",
                items: snapshot.applications.map { item in
                    DonutSlice(
                        id: item.id,
                        name: item.name,
                        color: Theme.appColor(for: item.bundleID ?? item.id),
                        seconds: item.seconds,
                        icon: AppIconCache.shared.icon(for: item.bundleID ?? item.id)
                    )
                },
                total: snapshot.total
            )

            donutCard(
                title: "项目分布",
                items: snapshot.projects.map { item in
                    DonutSlice(
                        id: item.id,
                        name: item.name,
                        color: Color(hexString: item.colorHex),
                        seconds: item.seconds,
                        icon: nil
                    )
                },
                total: snapshot.total
            )
        }
    }

    private func donutCard(title: String, items: [DonutSlice], total: TimeInterval) -> some View {
        let sum = items.reduce(0.0) { $0 + $1.seconds }
        let share = total > 0 ? sum / total * 100 : 0
        return card {
            SectionLabel(title: title)
            if sum <= 0 {
                EmptyStateText(text: "暂无数据")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                DonutChart(
                    slices: items,
                    caption: String(format: "占全部 %.0f%%", share)
                )
                .frame(height: 220)
            }
        }
    }

    // MARK: - 项目明细树

    private func projectTree(_ snapshot: StatisticsSnapshot) -> some View {
        card {
            SectionLabel(title: "项目明细")
            if snapshot.projects.isEmpty {
                EmptyStateText(text: "这个范围还没有项目记录。")
            } else {
                VStack(spacing: 0) {
                    ForEach(treeRows(snapshot)) { row in
                        treeRow(row, snapshot: snapshot)
                        if row.id != treeRows(snapshot).last?.id {
                            Divider().overlay(Theme.divider.opacity(0.4))
                        }
                    }
                }
            }
        }
    }

    private func treeRow(_ row: TreeRow, snapshot: StatisticsSnapshot) -> some View {
        HStack(spacing: 7) {
            if row.hasChildren {
                Button {
                    if expanded.contains(row.id) { expanded.remove(row.id) } else { expanded.insert(row.id) }
                } label: {
                    Image(systemName: expanded.contains(row.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.tertiary)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }

            Circle()
                .fill(row.color)
                .frame(width: 7, height: 7)

            Text(row.name)
                .font(.system(size: row.depth == 0 ? 11.5 : 11))
                .foregroundColor(Theme.text.opacity(row.depth == 0 ? 0.95 : 0.85))
                .lineLimit(1)

            if row.kind == .entry {
                Text("\(Fmt.timeOfDay(row.start)) – \(Fmt.timeOfDay(row.end))")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(Fmt.sidebar(row.seconds))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundColor(Theme.tertiary)
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private struct TreeRow: Identifiable {
        enum Kind { case project, entry }
        let id: String
        let name: String
        let depth: Int
        let seconds: TimeInterval
        let color: Color
        let hasChildren: Bool
        let kind: Kind
        let start: Date
        let end: Date
        var projectID: String?
    }

    private func treeRows(_ snapshot: StatisticsSnapshot) -> [TreeRow] {
        var shareByProject: [String: TimeInterval] = [:]
        for item in snapshot.projects {
            guard let projectID = item.projectID else { continue }
            shareByProject[projectID] = item.seconds
        }
        var childrenByParent: [String?: [Project]] = [:]
        for project in app.projects {
            childrenByParent[project.parentID, default: []].append(project)
        }

        func totalSeconds(_ project: Project) -> TimeInterval {
            let own = shareByProject[project.id] ?? 0
            let children = (childrenByParent[project.id] ?? []).reduce(0.0) { $0 + totalSeconds($1) }
            return own + children
        }

        var rows: [TreeRow] = []
        func walk(_ parentID: String?, depth: Int) {
            let nodes = (childrenByParent[parentID] ?? [])
                .filter { totalSeconds($0) > 0 }
                .sorted { totalSeconds($0) > totalSeconds($1) }
            let unassigned = snapshot.projects.first { $0.isUnassigned }

            for project in nodes {
                let seconds = totalSeconds(project)
                let hasChildren = !(childrenByParent[project.id] ?? []).isEmpty
                rows.append(TreeRow(
                    id: project.id,
                    name: project.name,
                    depth: depth,
                    seconds: seconds,
                    color: Color(hexString: project.colorHex),
                    hasChildren: hasChildren,
                    kind: .project,
                    start: snapshot.interval.start,
                    end: snapshot.interval.end,
                    projectID: project.id
                ))
                guard expanded.contains(project.id) else { continue }
                if hasChildren { walk(project.id, depth: depth + 1) }
                // 叶子项目展开后显示该项目的记录。
                if !hasChildren {
                    for entry in snapshot.entries.filter({ $0.projectID == project.id }).sorted(by: { $0.start < $1.start }) {
                        rows.append(TreeRow(
                            id: entry.id,
                            name: entry.title,
                            depth: depth + 1,
                            seconds: app.clampedDuration(entry),
                            color: Color(hexString: project.colorHex).opacity(0.7),
                            hasChildren: false,
                            kind: .entry,
                            start: entry.start,
                            end: entry.end,
                            projectID: project.id
                        ))
                    }
                }
            }

            if depth == 0, let unassigned, unassigned.seconds > 0 {
                rows.append(TreeRow(
                    id: "__unassigned__",
                    name: "未分配",
                    depth: 0,
                    seconds: unassigned.seconds,
                    color: Color(hexString: "#8E8E93"),
                    hasChildren: true,
                    kind: .project,
                    start: snapshot.interval.start,
                    end: snapshot.interval.end,
                    projectID: nil
                ))
                if expanded.contains("__unassigned__") {
                    for entry in snapshot.entries.filter({ $0.projectID == nil }).sorted(by: { $0.start < $1.start }) {
                        rows.append(TreeRow(
                            id: entry.id,
                            name: entry.title,
                            depth: 1,
                            seconds: app.clampedDuration(entry),
                            color: Color(hexString: "#8E8E93").opacity(0.7),
                            hasChildren: false,
                            kind: .entry,
                            start: entry.start,
                            end: entry.end,
                            projectID: nil
                        ))
                    }
                }
            }
        }
        walk(nil, depth: 0)
        return rows
    }

    // MARK: - 通用

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
        )
    }

    private func rangeText(_ snapshot: StatisticsSnapshot) -> String {
        let calendar = Calendar.current
        switch snapshot.range {
        case .day:
            return Fmt.dayLong(snapshot.interval.start)
        case .week:
            let start = snapshot.interval.start
            let end = snapshot.interval.end.addingTimeInterval(-1)
            return "\(calendar.component(.month, from: start))/\(calendar.component(.day, from: start)) – \(calendar.component(.month, from: end))/\(calendar.component(.day, from: end))"
        case .month:
            let components = calendar.dateComponents([.year, .month], from: snapshot.interval.start)
            return "\(components.year ?? 0)年\(components.month ?? 1)月"
        case .year:
            return "\(calendar.component(.year, from: snapshot.interval.start))年"
        }
    }

    private func unitName(_ unit: StatisticsUnit) -> String {
        switch unit {
        case .hour: return "小时"
        case .day: return "天"
        case .week: return "周"
        case .month: return "月"
        }
    }

    private func bucketLabel(_ date: Date, unit: StatisticsUnit) -> String {
        let calendar = Calendar.current
        switch unit {
        case .hour:
            return String(format: "%02d:00", calendar.component(.hour, from: date))
        case .day:
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
        case .week:
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) 周"
        case .month:
            return "\(calendar.component(.month, from: date))月"
        }
    }
}

// MARK: - 堆叠柱状图

struct StackedBarChart: View {
    let snapshot: StatisticsSnapshot
    let dimension: StatisticsDimension
    let color: (String) -> Color
    @Binding var hovered: String?

    var body: some View {
        GeometryReader { geo in
            let maxTotal = max(snapshot.buckets.map(\.total).max() ?? 0, 1)
            let count = max(snapshot.buckets.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let barWidth = max(3, min(26, slot * 0.62))
            let labelHeight: CGFloat = 16
            let chartHeight = max(40, geo.size.height - labelHeight - 4)

            ZStack(alignment: .bottomLeading) {
                Canvas { context, size in
                    for (index, bucket) in snapshot.buckets.enumerated() {
                        let x = slot * CGFloat(index) + (slot - barWidth) / 2
                        var y = size.height - labelHeight
                        let isHovered = hovered == bucket.id
                        for part in bucket.parts {
                            let height = chartHeight * CGFloat(part.seconds / maxTotal)
                            guard height > 0.4 else { continue }
                            let rect = CGRect(x: x, y: y - height, width: barWidth, height: height)
                            context.fill(
                                Path(rect),
                                with: .color(color(part.id).opacity(isHovered ? 1 : 0.85))
                            )
                            y -= height
                        }
                    }
                }

                // 横轴标签：按可用宽度抽稀。
                ForEach(Array(snapshot.buckets.enumerated()), id: \.element.id) { index, bucket in
                    if index % labelStride(count: count, slot: slot) == 0 {
                        Text(label(bucket.start))
                            .font(.system(size: 8.5))
                            .foregroundColor(Theme.tertiary)
                            .position(
                                x: slot * CGFloat(index) + slot / 2,
                                y: geo.size.height - labelHeight / 2 - 1
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let index = min(max(Int(point.x / max(slot, 1)), 0), snapshot.buckets.count - 1)
                    hovered = snapshot.buckets.isEmpty ? nil : snapshot.buckets[index].id
                case .ended:
                    hovered = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let bucket = snapshot.buckets.first(where: { $0.id == hovered }) {
                    tooltip(bucket: bucket, slot: slot, count: count, width: geo.size.width)
                }
            }
        }
    }

    private func tooltip(bucket: StatisticsBucket, slot: CGFloat, count: Int, width: CGFloat) -> some View {
        let index = snapshot.buckets.firstIndex { $0.id == bucket.id } ?? 0
        let x = min(max(slot * CGFloat(index) - 60, 0), max(0, width - 172))
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(label(bucket.start)) · \(Fmt.human(bucket.total))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.text)
            ForEach(bucket.parts.prefix(3)) { part in
                HStack(spacing: 5) {
                    Circle()
                        .fill(color(part.id))
                        .frame(width: 5, height: 5)
                    Text(name(for: part.id))
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Fmt.sidebar(part.seconds))
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundColor(Theme.tertiary)
                }
            }
        }
        .padding(8)
        .frame(width: 172, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.window)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1)
                )
        )
        .offset(x: x, y: 0)
        .allowsHitTesting(false)
    }

    private func name(for id: String) -> String {
        if dimension == .application {
            return snapshot.applications.first { $0.id == id }?.name ?? id
        }
        if id == "__unassigned__" { return "未分配" }
        return snapshot.projects.first { $0.projectID == id }?.name ?? "项目"
    }

    private func labelStride(count: Int, slot: CGFloat) -> Int {
        max(1, Int(ceil(34 / max(slot, 1))))
    }

    private func label(_ date: Date) -> String {
        let calendar = Calendar.current
        switch snapshot.unit {
        case .hour:
            return String(format: "%02d", calendar.component(.hour, from: date))
        case .day:
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
        case .week:
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
        case .month:
            return "\(calendar.component(.month, from: date))月"
        }
    }
}

// MARK: - 环形图

struct DonutSlice: Identifiable {
    let id: String
    let name: String
    let color: Color
    let seconds: TimeInterval
    let icon: NSImage?
}

struct DonutChart: View {
    let slices: [DonutSlice]
    let caption: String
    @State private var localHover: String?

    private var items: [DonutSlice] {
        let sorted = slices.filter { $0.seconds > 0 }.sorted { $0.seconds > $1.seconds }
        guard sorted.count > 7 else { return sorted }
        let head = Array(sorted.prefix(6))
        let rest = sorted.dropFirst(6).reduce(0.0) { $0 + $1.seconds }
        return head + [DonutSlice(id: "__other__", name: "其他", color: Color(hexString: "#6E6E73"), seconds: rest, icon: nil)]
    }

    /// 环形图按自身分布归一化，避免「应用只覆盖部分时间」时出现半圈空白。
    private var sum: TimeInterval {
        items.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        let active = localHover
        HStack(spacing: 12) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let outer = side / 2 - 4
                let inner = outer * 0.6

                Canvas { context, _ in
                    var start = Angle.degrees(-90)
                    for item in items {
                        let fraction = item.seconds / max(sum, 1)
                        let sweep = Angle.degrees(360 * fraction)
                        var path = Path()
                        path.addArc(center: center, radius: outer, startAngle: start, endAngle: start + sweep, clockwise: false)
                        path.addArc(center: center, radius: inner, startAngle: start + sweep, endAngle: start, clockwise: true)
                        path.closeSubpath()
                        let dim = active != nil && active != item.id
                        context.fill(path, with: .color(item.color.opacity(dim ? 0.32 : 0.92)))

                        if sweep.degrees > 22, let icon = item.icon {
                            let mid = start.degrees + sweep.degrees / 2
                            let radius = (outer + inner) / 2
                            let point = CGPoint(
                                x: center.x + cos(mid * .pi / 180) * radius,
                                y: center.y + sin(mid * .pi / 180) * radius
                            )
                            context.draw(
                                Image(nsImage: icon),
                                in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                            )
                        }
                        start = start + sweep
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        localHover = sliceID(at: point, center: center, inner: inner, outer: outer)
                    case .ended:
                        localHover = nil
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(active.flatMap { id in items.first { $0.id == id } }.map { Fmt.human($0.seconds) } ?? Fmt.human(sum))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.text)
                Text(active.flatMap { id in items.first { $0.id == id } }?.name ?? caption)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.tertiary)
                    .lineLimit(1)

                ForEach(items.prefix(6)) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 6, height: 6)
                        Text(item.name)
                            .font(.system(size: 9.5))
                            .foregroundColor(Theme.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(percent(item.seconds))
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundColor(Theme.tertiary)
                    }
                    .opacity(active == nil || active == item.id ? 1 : 0.5)
                }
            }
            .frame(width: 132, alignment: .leading)
        }
    }

    private func percent(_ seconds: TimeInterval) -> String {
        guard sum > 0 else { return "0%" }
        return String(format: "%.0f%%", seconds / sum * 100)
    }

    private func sliceID(at point: CGPoint, center: CGPoint, inner: CGFloat, outer: CGFloat) -> String? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= inner, distance <= outer + 4 else { return nil }
        var angle = atan2(dy, dx) * 180 / .pi + 90
        if angle < 0 { angle += 360 }
        var cursor: Double = 0
        for item in items {
            let sweep = 360 * (item.seconds / max(sum, 1))
            if angle >= cursor, angle < cursor + sweep { return item.id }
            cursor += sweep
        }
        return items.last?.id
    }
}

/// 两个分布卡片：宽窗口左右并排，窄窗口上下排列。
/// 用 Layout 而不是 GeometryReader，避免在滚动视图里拿不到固有高度。
private struct DistributionLayout: Layout {
    var spacing: CGFloat = 14
    /// 单列最小宽度，低于两列之和就改为纵向排列。
    var minColumnWidth: CGFloat = 300

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? (minColumnWidth * 2 + spacing)
        guard !subviews.isEmpty else { return CGSize(width: width, height: 0) }
        if width >= minColumnWidth * 2 + spacing {
            let columnWidth = (width - spacing) / 2
            let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
            return CGSize(width: width, height: heights.max() ?? 0)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let total = heights.reduce(0, +) + spacing * CGFloat(heights.count - 1)
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let width = bounds.width
        if width >= minColumnWidth * 2 + spacing {
            let columnWidth = (width - spacing) / 2
            var x = bounds.minX
            for subview in subviews {
                let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
                subview.place(
                    at: CGPoint(x: x, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: columnWidth, height: height)
                )
                x += columnWidth + spacing
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height)
            )
            y += height + spacing
        }
    }
}
