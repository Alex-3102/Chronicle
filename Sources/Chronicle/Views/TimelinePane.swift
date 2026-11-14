import SwiftUI
import AppKit
import ChronicleCore

struct TimelinePane: View {
    @EnvironmentObject var app: AppState

    private let headerHeight: CGFloat = 58

    @State private var hover: HoverCardData?

    var body: some View {
        GeometryReader { geo in
            let timelineH = timelineHeight(in: geo.size.height)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Theme.divider.opacity(0.6))
                    if app.hasAnyData {
                        DayTimelineView(entries: app.timelineEntries, usage: app.dayUsageRecords, hover: $hover)
                            .frame(height: timelineH)
                        Divider().overlay(Theme.divider.opacity(0.6))
                        ActivityOutlineSection()
                    } else {
                        WelcomeView()
                    }
                }

                if let hover {
                    let position = cardPosition(
                        hover,
                        paneWidth: geo.size.width,
                        paneHeight: geo.size.height,
                        timelineHeight: timelineH
                    )
                    HoverCardView(hover: hover)
                        .offset(x: position.x, y: position.y)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }

    /// 悬浮卡片：横向放在时间轴下方，竖向放在指针右侧，都限制在面板内。
    private func cardPosition(
        _ hover: HoverCardData,
        paneWidth: CGFloat,
        paneHeight: CGFloat,
        timelineHeight: CGFloat
    ) -> CGPoint {
        let cardWidth: CGFloat = 452
        let cardHeight: CGFloat = 190

        if app.timelineOrientation.isHorizontal {
            var x = hover.point.x - cardWidth / 2
            x = max(12, min(x, max(12, paneWidth - cardWidth - 34)))
            let timelineBottom = headerHeight + 1 + timelineHeight
            let maxY = max(headerHeight + 8, paneHeight - cardHeight - 12)
            var y = timelineBottom + 8
            if y > maxY { y = maxY }
            return CGPoint(x: x, y: y)
        }

        var x = hover.point.x + 16
        if x + cardWidth > paneWidth - 12 {
            x = max(12, hover.point.x - cardWidth - 16)
        }
        let y = max(headerHeight + 8, min(hover.point.y - 60, paneHeight - cardHeight - 12))
        return CGPoint(x: x, y: y)
    }

    /// 时间轴高度：横向按三轨 + 重叠层数；竖向给更高的时间轴，方便看清细节。
    private func timelineHeight(in paneHeight: CGFloat) -> CGFloat {
        if app.timelineOrientation.isHorizontal {
            return min(340, max(196, 118 + CGFloat(laneCount) * 18))
        }
        return min(520, max(260, paneHeight * 0.5))
    }

    private var laneCount: Int {
        let start = app.dayInterval.start
        let dayEnd = app.dayInterval.end
        var laneEnds: [Date] = []
        for entry in app.timelineEntries.sorted(by: { $0.start < $1.start }) {
            let from = max(entry.start, start)
            let to = min(entry.end, dayEnd)
            guard to > from else { continue }
            var lane = 0
            while lane < laneEnds.count, laneEnds[lane] > from {
                lane += 1
            }
            if lane == laneEnds.count {
                laneEnds.append(to)
            } else {
                laneEnds[lane] = to
            }
        }
        return max(1, laneEnds.count)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.dayLong(app.selectedDay))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(summary)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let filter = app.filterDescription {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.orange)
                        .frame(width: 4, height: 4)
                    Text(filter)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Button {
                        app.selectAllActivity()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Theme.panelAlt))
            }

            orientationButton
            zoomControls

            if app.isToday {
                Text("现在 \(Fmt.preciseTime(app.now))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(Theme.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: headerHeight)
    }

    private var orientationButton: some View {
        Button {
            app.toggleTimelineOrientation()
        } label: {
            Image(systemName: app.timelineOrientation.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.panelAlt.opacity(0.7))
        )
        .help(app.timelineOrientation.isHorizontal ? "切换为竖向时间轴" : "切换为横向时间轴")
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                app.adjustTimelineZoom(by: 1 / 1.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(app.timelineZoom > 1 ? Theme.secondary : Theme.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.timelineZoom <= 1)
            .help("缩小时间轴（⌘-）")

            Text("\(Int((app.timelineZoom * 100).rounded()))%")
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundColor(Theme.tertiary)
                .frame(width: 34)

            Button {
                app.adjustTimelineZoom(by: 1.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(app.timelineZoom < app.timelineMaxZoom ? Theme.secondary : Theme.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.timelineZoom >= app.timelineMaxZoom)
            .help("放大时间轴（⌘+，也可在时间轴上双指缩放）")
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.panelAlt.opacity(0.7))
        )
        .help("双指捏合可缩放时间轴")
    }

    private var summary: String {
        let shown = app.filteredEntries
        let total = shown.reduce(0) { $0 + app.clampedDuration($1) }
        var parts = ["\(shown.count) 条记录", Fmt.human(total)]
        if !app.searchQuery.isEmpty {
            parts.append("搜索「\(app.globalSearch)」")
        }
        return parts.joined(separator: " · ")
    }
}

struct UsageSegment: Identifiable {
    let id: String
    let name: String
    let color: Color
    let x: CGFloat
    let width: CGFloat
}

/// 悬浮卡片数据：指针位置（时间轴面板坐标）+ 该时刻的三轨记录。
struct HoverCardData {
    let point: CGPoint
    let time: Date
    let app: AppUsageRecord?
    let entry: TimeEntry?
    let projectID: String?
    /// 应用块是缩小时的聚合结果，卡片里的应用可能与块不一致
    let appIsBucketed: Bool
}

/// 拖拽状态：移动整条、拖起止边界、或空白处框选时间范围。
struct EntryDragState {
    enum Mode {
        case move
        case resizeStart
        case resizeEnd
        case select
    }

    var mode: Mode
    var entry: TimeEntry?
    var start: Date
    var end: Date
    var moved = false
    /// 当前吸附到的时间点，用于 12px 退出阈值形成迟滞
    var snapped: Date?
}

struct DayTimelineView: View {
    @EnvironmentObject var app: AppState

    let entries: [TimeEntry]
    let usage: [AppUsageRecord]
    @Binding var hover: HoverCardData?

    private let timeInset: CGFloat = 8

    @State private var scrollOffset: CGFloat = 0
    @State private var hoverTime: Date?
    @State private var lastHoverContentPoint: CGPoint?
    @State private var drag: EntryDragState?

    private var orientation: TimelineOrientation { app.timelineOrientation }

    /// 时间刻度区厚度：横向在顶部 18pt，竖向在右侧 48pt。
    private var rulerThickness: CGFloat {
        orientation.isHorizontal ? 18 : 48
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = TimelineMetrics(
                size: geo.size,
                orientation: orientation,
                rulerThickness: rulerThickness,
                labelThickness: orientation.isHorizontal ? 46 : 16
            )
            let geometry = TimelineGeometry(
                orientation: orientation,
                rangeStart: app.dayInterval.start,
                rangeEnd: app.dayInterval.end,
                pixelsPerHour: metrics.pixelsPerHour(zoom: app.timelineZoom, timeInset: timeInset),
                timeInset: timeInset
            )
            let layout = TimelineTrackLayout(
                crossStart: metrics.trackCrossStart,
                crossLength: metrics.trackCrossLength
            )
            let bands = makeBands(geometry: geometry, layout: layout)

            ZStack(alignment: .topLeading) {
                trackLabels(layout: layout, metrics: metrics)

                TimelineScrollHost(
                    contentSize: CGSize(
                        width: orientation.isHorizontal ? geometry.contentAxisLength : metrics.contentCrossLength,
                        height: orientation.isHorizontal ? metrics.contentCrossLength : geometry.contentAxisLength
                    ),
                    orientation: orientation,
                    timeInset: timeInset,
                    content: AnyView(
                        board(geometry: geometry, layout: layout, bands: bands)
                            .environmentObject(app)
                    ),
                    onMagnify: { magnification in
                        app.setTimelineZoom(app.timelineZoom * (1 + magnification))
                    },
                    onOffsetChange: { value in
                        scrollOffset = value
                        refreshHover(geometry: geometry, layout: layout)
                    }
                )
                .frame(width: metrics.scrollFrame.width, height: metrics.scrollFrame.height)
                .offset(x: metrics.scrollFrame.minX, y: metrics.scrollFrame.minY)
            }
        }
    }

    // MARK: - 画布

    private func board(geometry: TimelineGeometry, layout: TimelineTrackLayout, bands: Bands) -> some View {
        let contentSize = CGSize(
            width: orientation.isHorizontal ? geometry.contentAxisLength : metricsCross(geometry, layout),
            height: orientation.isHorizontal ? metricsCross(geometry, layout) : geometry.contentAxisLength
        )
        let lanes = entryLanes(layout: layout, bands: bands)
        return ZStack(alignment: .topLeading) {
            lanesCanvas(geometry: geometry, layout: layout, bands: bands)

            ForEach(bands.entries) { block in
                if let rect = entryRect(block, geometry: geometry, lanes: lanes) {
                    TimelineEntryCard(
                        block: block,
                        orientation: orientation,
                        size: rect.size,
                        isDragging: drag?.entry?.id == block.id
                    )
                    .frame(width: rect.width, height: rect.height)
                    // 时间很短时卡片只有几 pt，必须裁掉溢出的内容，否则会盖住相邻条目
                    .clipped()
                    .offset(x: rect.minX, y: rect.minY)
                }
            }

            if bands.entries.isEmpty {
                Text("这一天还没有时间条目")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiary)
                    .offset(
                        x: orientation.isHorizontal ? timeInset + 10 : layout.entryOrigin + 10,
                        y: orientation.isHorizontal ? layout.entryOrigin + 12 : timeInset + 10
                    )
            }
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "timelineContent")
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("timelineContent"))
                .onChanged { value in dragChanged(value, geometry: geometry, layout: layout, blocks: bands.entries, lanes: lanes) }
                .onEnded { _ in dragEnded() }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                lastHoverContentPoint = point
                updateHover(point: point, geometry: geometry, layout: layout, bands: bands)
            case .ended:
                lastHoverContentPoint = nil
                hoverTime = nil
                hover = nil
            }
        }
        .contextMenu {
            if let entry = hover?.entry {
                Button("删除记录", role: .destructive) {
                    app.deleteEntry(entry)
                }
            }
        }
    }

    /// 内容副轴长度（横向=高度，竖向=宽度）。
    private func metricsCross(_ geometry: TimelineGeometry, _ layout: TimelineTrackLayout) -> CGFloat {
        layout.crossLength + rulerThickness
    }

    /// 网格、刻度、三轨色带、当前时间线、悬浮线都画在同一张 Canvas 上。
    private func lanesCanvas(geometry: TimelineGeometry, layout: TimelineTrackLayout, bands: Bands) -> some View {
        Canvas { context, size in
            drawTrackBackgrounds(&context, geometry: geometry, layout: layout, size: size)
            drawTicks(&context, geometry: geometry, layout: layout)
            drawAppBand(&context, geometry: geometry, layout: layout, segments: bands.apps)
            drawProjectBand(&context, geometry: geometry, layout: layout, spans: bands.projects)

            if app.isToday {
                let line = geometry.line(
                    at: app.now,
                    crossStart: layout.crossStart,
                    crossLength: layout.crossLength,
                    thickness: 1
                )
                context.fill(Path(line), with: .color(Theme.red.opacity(0.75)))
            }

            if let hoverTime {
                let line = geometry.line(
                    at: hoverTime,
                    crossStart: layout.crossStart,
                    crossLength: layout.crossLength,
                    thickness: 0.6
                )
                context.fill(Path(line), with: .color(Theme.text.opacity(0.30)))
            }

            if let drag, drag.mode == .select, drag.end > drag.start {
                if let rect = geometry.rect(
                    start: drag.start,
                    end: drag.end,
                    vStart: layout.entryOrigin,
                    vThickness: layout.entryThickness
                ) {
                    context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.blue.opacity(0.16)))
                    context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.blue.opacity(0.7)), lineWidth: 1)
                }
            }
        }
    }

    private func drawTrackBackgrounds(
        _ context: inout GraphicsContext,
        geometry: TimelineGeometry,
        layout: TimelineTrackLayout,
        size: CGSize
    ) {
        for track in TimelineTrack.allCases {
            let rect = geometry.rect(
                uStart: 0,
                uLength: geometry.contentAxisLength,
                vStart: layout.origin(for: track),
                vThickness: layout.thickness(for: track)
            )
            context.fill(Path(rect), with: .color(Theme.panelAlt.opacity(track == .entry ? 0.35 : 0.55)))
        }
    }

    private func drawTicks(_ context: inout GraphicsContext, geometry: TimelineGeometry, layout: TimelineTrackLayout) {
        let step = tickStep(pixelsPerHour: geometry.pixelsPerHour)
        let rulerStart = orientation.isHorizontal ? 0 : layout.crossLength
        let rulerCenter = rulerStart + rulerThickness / 2

        var hour = 0.0
        while hour <= 24.0001 {
            let date = geometry.rangeStart.addingTimeInterval(hour * 3600)
            let u = geometry.timeToAxis(date)
            let major = abs((hour / step).rounded() - hour / step) < 0.001

            // 网格线贯穿三轨
            let grid = geometry.line(
                at: date,
                crossStart: layout.crossStart,
                crossLength: layout.crossLength,
                thickness: major ? 0.6 : 0.4
            )
            context.fill(Path(grid), with: .color(Theme.divider.opacity(major ? 0.4 : 0.15)))

            // 刻度短线
            let tick = geometry.rect(uStart: u, uLength: 0.6, vStart: rulerStart, vThickness: rulerThickness)
            context.fill(Path(tick), with: .color(Theme.divider.opacity(0.55)))

            if major {
                let text = Text(label(forHour: hour))
                    .font(.system(size: 9))
                    .foregroundColor(Theme.tertiary)
                let position = orientation.isHorizontal
                    ? CGPoint(x: u, y: rulerCenter)
                    : CGPoint(x: rulerCenter, y: u)
                context.draw(text, at: position, anchor: .center)
            }
            hour += 0.5
        }
    }

    private func drawAppBand(
        _ context: inout GraphicsContext,
        geometry: TimelineGeometry,
        layout: TimelineTrackLayout,
        segments: [AppBandSegment]
    ) {
        for segment in segments {
            guard let rect = geometry.rect(
                start: segment.start,
                end: segment.end,
                vStart: layout.origin(for: .app),
                vThickness: layout.thickness(for: .app)
            ) else { continue }
            let radius = min(4, min(rect.width, rect.height) / 2)
            let shape = Path(roundedRect: rect, cornerRadius: radius)
            context.fill(shape, with: .color(segment.color.opacity(0.55)))

            let shortSide = min(rect.width, rect.height)
            if shortSide >= 16,
               let icon = AppIconCache.shared.icon(for: segment.bundleID) {
                let image = context.resolve(Image(nsImage: icon))
                let side = shortSide - 6
                let iconRect = orientation.isHorizontal
                    ? CGRect(x: rect.minX + 3, y: rect.midY - side / 2, width: side, height: side)
                    : CGRect(x: rect.midX - side / 2, y: rect.minY + 3, width: side, height: side)
                context.draw(image, in: iconRect)
            }
        }
    }

    private func drawProjectBand(
        _ context: inout GraphicsContext,
        geometry: TimelineGeometry,
        layout: TimelineTrackLayout,
        spans: [ProjectBandSpan]
    ) {
        for span in spans {
            guard let rect = geometry.rect(
                start: span.start,
                end: span.end,
                vStart: layout.origin(for: .project),
                vThickness: layout.thickness(for: .project)
            ) else { continue }
            let radius = min(4, min(rect.width, rect.height) / 2)
            context.fill(
                Path(roundedRect: rect, cornerRadius: radius),
                with: .color(span.isUnassigned ? Theme.secondary.opacity(0.18) : span.color.opacity(0.55))
            )
        }
    }

    // MARK: - 刻度

    private func tickStep(pixelsPerHour: CGFloat) -> Double {
        if pixelsPerHour >= 150 { return 0.5 }
        if pixelsPerHour >= 62 { return 1 }
        if pixelsPerHour >= 28 { return 2 }
        return 3
    }

    private func label(forHour hour: Double) -> String {
        let total = Int((hour * 60).rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - 轨道标签

    @ViewBuilder
    private func trackLabels(layout: TimelineTrackLayout, metrics: TimelineMetrics) -> some View {
        if orientation.isHorizontal {
            ZStack(alignment: .topLeading) {
                ForEach(TimelineTrack.allCases, id: \.rawValue) { track in
                    Text(track.title)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.tertiary)
                        .frame(width: 40, alignment: .trailing)
                        .offset(x: 0, y: metrics.scrollFrame.minY + layout.origin(for: track) + layout.thickness(for: track) / 2 - 6)
                }
            }
            .frame(width: metrics.labelThickness, height: metrics.size.height, alignment: .topLeading)
        } else {
            ZStack(alignment: .topLeading) {
                ForEach(TimelineTrack.allCases, id: \.rawValue) { track in
                    Text(track.title)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.tertiary)
                        .frame(width: max(24, layout.thickness(for: track)), height: 14, alignment: .leading)
                        .offset(x: layout.origin(for: track), y: 1)
                }
            }
            .frame(width: metrics.size.width, height: metrics.labelThickness, alignment: .topLeading)
        }
    }

    // MARK: - 数据

    struct Bands {
        var apps: [AppBandSegment]
        var projects: [ProjectBandSpan]
        var entries: [TimelineEntryBlock]
        var laneCount: Int
    }

    private func makeBands(geometry: TimelineGeometry, layout: TimelineTrackLayout) -> Bands {
        let range = DateInterval(start: geometry.rangeStart, end: geometry.rangeEnd)
        let apps = TimelineData.appSegments(
            records: usage,
            range: range,
            pixelsPerHour: geometry.pixelsPerHour,
            color: { Theme.appColor(for: $0) }
        )
        let projects = TimelineData.projectSpans(
            spans: app.accounting.spans,
            range: range,
            color: { app.color(for: $0) }
        )
        let blocks = TimelineData.entryBlocks(
            entries: entries,
            range: range,
            color: { app.color(for: $0) },
            dimmed: { !app.isInSelection($0) }
        )
        let lanes = (blocks.map(\.lane).max() ?? 0) + 1
        return Bands(apps: apps, projects: projects, entries: blocks, laneCount: blocks.isEmpty ? 1 : lanes)
    }

    /// 条目轨道内的子车道：横向按固定行高上下并排，竖向把整列按重叠数等分。
    struct EntryLaneMetrics {
        let count: Int
        let start: CGFloat
        let total: CGFloat
        let gap: CGFloat = 2

        func thickness(horizontal: Bool) -> CGFloat {
            let available = (total - CGFloat(max(0, count - 1)) * gap) / CGFloat(max(1, count))
            return horizontal ? min(16, max(8, available)) : max(12, available)
        }

        func origin(_ lane: Int, horizontal: Bool) -> CGFloat {
            start + CGFloat(lane) * (thickness(horizontal: horizontal) + gap)
        }
    }

    private func entryLanes(layout: TimelineTrackLayout, bands: Bands) -> EntryLaneMetrics {
        EntryLaneMetrics(count: bands.laneCount, start: layout.entryOrigin, total: layout.entryThickness)
    }

    private func entryRect(_ block: TimelineEntryBlock, geometry: TimelineGeometry, lanes: EntryLaneMetrics) -> CGRect? {
        var start = block.entry.start
        var end = block.entry.end
        if let drag, drag.entry?.id == block.id, drag.mode != .select {
            start = drag.start
            end = drag.end
        }
        return geometry.rect(
            start: start,
            end: end,
            vStart: lanes.origin(block.lane, horizontal: orientation.isHorizontal),
            vThickness: lanes.thickness(horizontal: orientation.isHorizontal)
        )
    }

    // MARK: - 悬浮

    private func updateHover(
        point: CGPoint,
        geometry: TimelineGeometry,
        layout: TimelineTrackLayout,
        bands: Bands
    ) {
        let time = geometry.axisToTime(geometry.pointToAxis(point))
        hoverTime = time

        let record = usage
            .filter { $0.start <= time && time < $0.end }
            .max { $0.start < $1.start }
        // 明确命中的条目优先；否则按开始时间较晚优先。
        let entry = entries
            .filter { $0.start <= time && time < $0.end }
            .max { $0.start < $1.start }
        let span = bands.projects.last { $0.start <= time && time < $0.end }

        let pane = panePoint(from: point, geometry: geometry)
        hover = HoverCardData(
            point: pane,
            time: time,
            app: record,
            entry: entry,
            projectID: span?.projectID,
            appIsBucketed: record.map { record in
                bands.apps.contains { $0.isBucketed && $0.start <= record.start && record.end <= $0.end }
            } ?? false
        )
    }

    /// 内容坐标 → 时间轴面板坐标（加上滚动偏移和标签区原点）。
    private func panePoint(from contentPoint: CGPoint, geometry: TimelineGeometry) -> CGPoint {
        if orientation.isHorizontal {
            return CGPoint(x: contentPoint.x - scrollOffset + 46, y: contentPoint.y)
        }
        return CGPoint(x: contentPoint.x, y: contentPoint.y - scrollOffset + 16)
    }

    private func refreshHover(geometry: TimelineGeometry, layout: TimelineTrackLayout) {
        guard let point = lastHoverContentPoint else { return }
        updateHover(point: point, geometry: geometry, layout: layout, bands: makeBands(geometry: geometry, layout: layout))
    }

    // MARK: - 拖拽

    private func dragChanged(
        _ value: DragGesture.Value,
        geometry: TimelineGeometry,
        layout: TimelineTrackLayout,
        blocks: [TimelineEntryBlock],
        lanes: EntryLaneMetrics
    ) {
        let startU = geometry.pointToAxis(value.startLocation)
        let currentU = geometry.pointToAxis(value.location)

        if drag == nil {
            drag = beginDrag(at: value.startLocation, geometry: geometry, layout: layout, blocks: blocks, lanes: lanes)
            if drag == nil { return }
        }
        guard var state = drag else { return }

        let rawDelta = TimeInterval((currentU - startU) / geometry.pixelsPerHour * 3600)
        if abs(currentU - startU) > 1 { state.moved = true }

        switch state.mode {
        case .select:
            state.start = geometry.axisToTime(min(startU, currentU))
            state.end = geometry.axisToTime(max(startU, currentU))

        case .move, .resizeStart, .resizeEnd:
            guard let entry = state.entry else { return }
            let step = stepSeconds(pixelsPerHour: geometry.pixelsPerHour)
            let delta = (rawDelta / step).rounded() * step
            switch state.mode {
            case .move:
                var start = entry.start.addingTimeInterval(delta)
                var end = entry.end.addingTimeInterval(delta)
                let snapped = snapRange(start: start, end: end, entry: entry, geometry: geometry, locked: state.snapped)
                start = snapped.start
                end = snapped.end
                state.snapped = snapped.snapped
                state.start = max(geometry.rangeStart, start)
                state.end = min(geometry.rangeEnd, max(state.start.addingTimeInterval(step), end))
            case .resizeStart:
                var start = entry.start.addingTimeInterval(delta)
                let result = snapTime(start, entry: entry, geometry: geometry, locked: state.snapped)
                start = result.time
                state.snapped = result.snapped
                state.start = max(geometry.rangeStart, min(start, entry.end.addingTimeInterval(-step)))
            case .resizeEnd:
                var end = entry.end.addingTimeInterval(delta)
                let result = snapTime(end, entry: entry, geometry: geometry, locked: state.snapped)
                end = result.time
                state.snapped = result.snapped
                state.end = min(geometry.rangeEnd, max(end, entry.start.addingTimeInterval(step)))
            default:
                break
            }
        }
        drag = state
    }

    private func beginDrag(
        at point: CGPoint,
        geometry: TimelineGeometry,
        layout: TimelineTrackLayout,
        blocks: [TimelineEntryBlock],
        lanes: EntryLaneMetrics
    ) -> EntryDragState? {
        let cross = geometry.pointToCrossAxis(point)
        let inEntryTrack = cross >= layout.entryOrigin && cross <= layout.entryOrigin + layout.entryThickness
        guard inEntryTrack else { return nil }

        let u = geometry.pointToAxis(point)
        for block in blocks {
            guard let rect = geometry.rect(
                start: block.entry.start,
                end: block.entry.end,
                vStart: lanes.origin(block.lane, horizontal: orientation.isHorizontal),
                vThickness: lanes.thickness(horizontal: orientation.isHorizontal)
            ) else { continue }
            let laneStart = geometry.pointToCrossAxis(CGPoint(x: rect.minX, y: rect.minY))
            let laneLength = orientation.isHorizontal ? rect.height : rect.width
            guard cross >= laneStart - 1, cross <= laneStart + laneLength + 1 else { continue }

            let uStart = geometry.timeToAxis(block.entry.start)
            let uEnd = geometry.timeToAxis(block.entry.end)
            guard u >= uStart - 1, u <= uEnd + 1 else { continue }

            let mode: EntryDragState.Mode
            if abs(u - uStart) <= 7, uEnd - uStart > 14 {
                mode = .resizeStart
            } else if abs(u - uEnd) <= 7, uEnd - uStart > 14 {
                mode = .resizeEnd
            } else {
                mode = .move
            }
            return EntryDragState(mode: mode, entry: block.entry, start: block.entry.start, end: block.entry.end)
        }

        let time = geometry.axisToTime(u)
        return EntryDragState(mode: .select, entry: nil, start: time, end: time)
    }

    private func dragEnded() {
        defer { drag = nil }
        guard let state = drag, state.moved else { return }
        guard state.mode != .select, let entry = state.entry else { return }
        guard state.end > state.start else { return }
        app.updateEntry(
            entry,
            projectID: entry.projectID,
            title: entry.title,
            note: entry.note,
            start: state.start,
            end: state.end
        )
    }

    /// 精度按每小时像素长度分级，按住 Option 精调到 1 秒。
    private func stepSeconds(pixelsPerHour: CGFloat) -> TimeInterval {
        if NSEvent.modifierFlags.contains(.option) { return 1 }
        if pixelsPerHour >= 1440 { return 5 }
        if pixelsPerHour >= 960 { return 10 }
        if pixelsPerHour >= 480 { return 15 }
        return 30
    }

    /// 吸附到其他条目的真实起止时间：进入 8px、退出 12px，形成迟滞。
    private func snapTime(
        _ time: Date,
        entry: TimeEntry,
        geometry: TimelineGeometry,
        locked: Date?
    ) -> (time: Date, snapped: Date?) {
        let enter = 8 / geometry.pixelsPerHour * 3600
        let exit = 12 / geometry.pixelsPerHour * 3600
        // 已经吸附住的时间点，在退出阈值内继续跟随，避免反复吸附 / 脱离。
        if let locked, abs(locked.timeIntervalSince(time)) <= exit {
            return (locked, locked)
        }
        let candidates = entries
            .filter { $0.id != entry.id }
            .flatMap { [$0.start, $0.end] }
            + [app.now]
        guard let best = candidates.min(by: {
            abs($0.timeIntervalSince(time)) < abs($1.timeIntervalSince(time))
        }) else { return (time, nil) }
        let distance = abs(best.timeIntervalSince(time))
        return distance <= enter ? (best, best) : (time, nil)
    }

    private func snapRange(
        start: Date,
        end: Date,
        entry: TimeEntry,
        geometry: TimelineGeometry,
        locked: Date?
    ) -> (start: Date, end: Date, snapped: Date?) {
        let startSnap = snapTime(start, entry: entry, geometry: geometry, locked: locked)
        let endSnap = snapTime(end, entry: entry, geometry: geometry, locked: locked)
        let startDistance = abs(startSnap.time.timeIntervalSince(start))
        let endDistance = abs(endSnap.time.timeIntervalSince(end))
        if startDistance == 0 && endDistance == 0 { return (start, end, nil) }
        if startDistance <= endDistance, startDistance > 0 {
            let shift = startSnap.time.timeIntervalSince(start)
            return (startSnap.time, end.addingTimeInterval(shift), startSnap.snapped)
        }
        if endDistance > 0 {
            let shift = endSnap.time.timeIntervalSince(end)
            return (start.addingTimeInterval(shift), endSnap.time, endSnap.snapped)
        }
        return (start, end, nil)
    }
}

/// 时间条目卡片：项目色半透明底 + 描边 + 起始边加粗色条。
struct TimelineEntryCard: View {
    @EnvironmentObject var app: AppState

    let block: TimelineEntryBlock
    let orientation: TimelineOrientation
    let size: CGSize
    let isDragging: Bool

    /// 时间方向放不下标题时只留色块，避免文字溢出到相邻条目上。
    private var showsTitle: Bool {
        orientation.isHorizontal ? size.width >= 44 && size.height >= 12 : size.height >= 20
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(block.color.opacity(block.dimmed ? 0.12 : 0.25))

            // 起始边加粗色条：横向在上边，竖向在左边。
            if orientation.isHorizontal {
                Rectangle()
                    .fill(block.color.opacity(0.9))
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Rectangle()
                    .fill(block.color.opacity(0.9))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsTitle {
                Text(block.entry.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.text.opacity(block.dimmed ? 0.6 : 0.92))
                    .lineLimit(1)
                    .padding(.horizontal, orientation.isHorizontal ? 6 : 9)
                    .padding(.top, orientation.isHorizontal ? 5 : 4)
                    .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(
            Rectangle()
                .strokeBorder(block.color.opacity(block.dimmed ? 0.35 : 0.8), lineWidth: 1.2)
        )
        .opacity(block.dimmed ? 0.55 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.25) : .clear, radius: 6, y: 2)
        .help("\(block.entry.title) · \(Fmt.timeOfDay(block.entry.start))–\(Fmt.timeOfDay(block.entry.end))")
    }
}

/// 悬浮卡片：大字时刻 + 应用程序 / 标题 / 时间条目 / 时间范围 / 项目路径。
struct HoverCardView: View {
    @EnvironmentObject var app: AppState
    let hover: HoverCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Fmt.preciseTime(hover.time))
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity, alignment: .center)

            if let record = hover.app {
                row("应用程序") {
                    HStack(spacing: 5) {
                        if let icon = AppIconCache.shared.icon(for: record.bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                        } else {
                            Circle()
                                .fill(Theme.appColor(for: record.bundleID))
                                .frame(width: 7, height: 7)
                        }
                        Text("\(record.appName) – \(Fmt.preciseTime(record.start)) – \(Fmt.preciseTime(record.end)) (\(Fmt.clock(record.duration)))")
                    }
                }

                row("标　题") {
                    Text(record.windowTitle ?? "—")
                }

                if hover.appIsBucketed {
                    row("说　明") {
                        Text("缩略图中这一格代表这段时间的主要应用，实际使用可能不同")
                            .foregroundColor(Theme.tertiary)
                    }
                }
            } else {
                row("应用程序") {
                    Text("这段时间没有记录")
                }
            }

            if let entry = hover.entry {
                row("时间条目") {
                    Text(entry.title)
                }

                row("时间范围") {
                    Text("\(Fmt.preciseTime(entry.start)) – \(Fmt.preciseTime(entry.end)) (\(Fmt.clock(app.clampedDuration(entry))))")
                }
            } else {
                row("时间条目") {
                    Text("无条目")
                        .foregroundColor(Theme.tertiary)
                }
            }

            row("项　目") {
                HStack(spacing: 5) {
                    Circle()
                        .fill(app.color(for: hover.projectID))
                        .frame(width: 7, height: 7)
                    Text(projectPathText(hover.projectID))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 452, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
                .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }

    private func projectPathText(_ id: String?) -> String {
        let names = app.projectPath(id).map(\.name)
        return names.isEmpty ? "未分配" : names.joined(separator: " › ")
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Theme.tertiary)
                .frame(width: 52, alignment: .leading)
            content()
                .font(.system(size: 10.5))
                .foregroundColor(Theme.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
