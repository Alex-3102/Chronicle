import SwiftUI
import ChronicleCore

/// 时间轴方向。
enum TimelineOrientation: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }
    var isHorizontal: Bool { self == .horizontal }
    var title: String { isHorizontal ? "横向时间轴" : "竖向时间轴" }
    var icon: String { isHorizontal ? "rectangle.split.2x1" : "rectangle.split.1x2" }
}

/// 三条轨道：同一段时间的三种描述，时长不能相加。
enum TimelineTrack: String, CaseIterable {
    case app
    case project
    case entry

    var title: String {
        switch self {
        case .app: return "应用"
        case .project: return "项目"
        case .entry: return "条目"
        }
    }
}

/// 统一坐标层：u 是时间主轴，v 是轨道副轴。
/// 轨道、刻度、当前时间线、悬浮线、拖拽边界全部走这一组转换。
struct TimelineGeometry {
    let orientation: TimelineOrientation
    let rangeStart: Date
    let rangeEnd: Date
    let pixelsPerHour: CGFloat
    /// 时间方向两端留白（放得下首尾刻度）
    let timeInset: CGFloat

    var rangeSeconds: TimeInterval { max(1, rangeEnd.timeIntervalSince(rangeStart)) }
    var rangeHours: CGFloat { CGFloat(rangeSeconds / 3600) }

    /// 内容主轴长度（含两端留白）
    var contentAxisLength: CGFloat { timeInset * 2 + rangeHours * pixelsPerHour }

    func timeToAxis(_ time: Date) -> CGFloat {
        let seconds = min(max(time.timeIntervalSince(rangeStart), 0), rangeSeconds)
        return timeInset + CGFloat(seconds / 3600) * pixelsPerHour
    }

    func axisToTime(_ u: CGFloat) -> Date {
        rangeStart.addingTimeInterval(TimeInterval((u - timeInset) / pixelsPerHour * 3600))
    }

    func pointToAxis(_ point: CGPoint) -> CGFloat {
        orientation.isHorizontal ? point.x : point.y
    }

    func pointToCrossAxis(_ point: CGPoint) -> CGFloat {
        orientation.isHorizontal ? point.y : point.x
    }

    func point(u: CGFloat, v: CGFloat) -> CGPoint {
        orientation.isHorizontal ? CGPoint(x: u, y: v) : CGPoint(x: v, y: u)
    }

    /// uStart/uLength 是时间方向，vStart/vThickness 是轨道方向。
    func rect(uStart: CGFloat, uLength: CGFloat, vStart: CGFloat, vThickness: CGFloat) -> CGRect {
        orientation.isHorizontal
            ? CGRect(x: uStart, y: vStart, width: uLength, height: vThickness)
            : CGRect(x: vStart, y: uStart, width: vThickness, height: uLength)
    }

    /// 记录按展示范围裁剪后再布局，原始起止时间保持不变。
    func rect(start: Date, end: Date, vStart: CGFloat, vThickness: CGFloat) -> CGRect? {
        let from = max(start, rangeStart)
        let to = min(end, rangeEnd)
        guard to > from else { return nil }
        let uStart = timeToAxis(from)
        let uLength = max(1, timeToAxis(to) - uStart)
        return rect(uStart: uStart, uLength: uLength, vStart: vStart, vThickness: vThickness)
    }

    /// 当前时间线 / 悬浮线：横穿三轨。
    func line(at time: Date, crossStart: CGFloat, crossLength: CGFloat, thickness: CGFloat = 1) -> CGRect {
        let u = timeToAxis(time)
        return rect(uStart: u, uLength: thickness, vStart: crossStart, vThickness: crossLength)
    }
}

/// 三轨在副轴上的排布（横向=上下排，竖向=左右排）。
struct TimelineTrackLayout {
    /// 轨道区在副轴上的起点（横向要给顶部刻度让位）
    let crossStart: CGFloat
    /// 轨道区可用的副轴长度
    let crossLength: CGFloat
    let appThickness: CGFloat
    let projectThickness: CGFloat
    let gap: CGFloat
    let entryMinThickness: CGFloat
    let entryLaneThickness: CGFloat
    let entryLaneGap: CGFloat

    init(
        crossStart: CGFloat,
        crossLength: CGFloat,
        appThickness: CGFloat = 24,
        projectThickness: CGFloat = 24,
        gap: CGFloat = 4,
        entryMinThickness: CGFloat = 40,
        entryLaneThickness: CGFloat = 16,
        entryLaneGap: CGFloat = 2
    ) {
        self.crossStart = crossStart
        self.crossLength = max(crossLength, 0)
        self.appThickness = appThickness
        self.projectThickness = projectThickness
        self.gap = gap
        self.entryMinThickness = entryMinThickness
        self.entryLaneThickness = entryLaneThickness
        self.entryLaneGap = entryLaneGap
    }

    var projectOrigin: CGFloat { crossStart + appThickness + gap }
    var entryOrigin: CGFloat { projectOrigin + projectThickness + gap }
    var entryThickness: CGFloat { max(entryMinThickness, crossLength - (entryOrigin - crossStart)) }

    func origin(for track: TimelineTrack) -> CGFloat {
        switch track {
        case .app: return crossStart
        case .project: return projectOrigin
        case .entry: return entryOrigin
        }
    }

    func thickness(for track: TimelineTrack) -> CGFloat {
        switch track {
        case .app: return appThickness
        case .project: return projectThickness
        case .entry: return entryThickness
        }
    }

    /// 时间条目重叠时分子轨道，最多能放下几条。
    var entryLaneCount: Int {
        max(1, Int((entryThickness + entryLaneGap) / (entryLaneThickness + entryLaneGap)))
    }

    func entryLaneOrigin(_ lane: Int) -> CGFloat {
        entryOrigin + CGFloat(lane) * (entryLaneThickness + entryLaneGap)
    }
}

/// 整个时间轴区域的尺寸换算：主视口、副轴长度、每小时像素。
struct TimelineMetrics {
    let size: CGSize
    let orientation: TimelineOrientation
    let rulerThickness: CGFloat
    let labelThickness: CGFloat

    /// 滚动视口（不含固定标签区与刻度区）
    var scrollFrame: CGRect {
        if orientation.isHorizontal {
            let width = max(60, size.width - labelThickness)
            let height = max(60, size.height)
            return CGRect(x: labelThickness, y: 0, width: width, height: height)
        } else {
            let width = max(60, size.width)
            let height = max(60, size.height - labelThickness)
            return CGRect(x: 0, y: labelThickness, width: width, height: height)
        }
    }

    /// 内容副轴长度（横向=高度；竖向=宽度，末尾给刻度留 48pt）
    var contentCrossLength: CGFloat {
        orientation.isHorizontal ? scrollFrame.height : scrollFrame.width
    }

    /// 轨道区副轴起点：横向刻度在最上面
    var trackCrossStart: CGFloat {
        orientation.isHorizontal ? rulerThickness : 0
    }

    /// 轨道区副轴可用长度
    var trackCrossLength: CGFloat {
        orientation.isHorizontal ? max(40, scrollFrame.height - rulerThickness) : max(60, scrollFrame.width - rulerThickness)
    }

    var axisViewportLength: CGFloat {
        orientation.isHorizontal ? scrollFrame.width : scrollFrame.height
    }

    /// 1 倍缩放时每小时像素：扣掉两端留白后正好铺满视口
    func basePixelsPerHour(timeInset: CGFloat) -> CGFloat {
        max(axisViewportLength - timeInset * 2, 60) / 24
    }

    func pixelsPerHour(zoom: Double, timeInset: CGFloat) -> CGFloat {
        basePixelsPerHour(timeInset: timeInset) * CGFloat(min(max(zoom, 1), 24))
    }
}
