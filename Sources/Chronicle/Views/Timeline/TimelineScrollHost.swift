import SwiftUI
import AppKit

/// 承载时间轴内容的滚动容器。
///
/// 缩放必须「同一次更新」里改完三样东西：画布尺寸、滚动偏移、可见内容。
/// 交给 SwiftUI 的 ScrollView 时，内容尺寸一改会先按旧尺寸把偏移裁一遍，
/// 再等下一次事件纠正，中间那一帧就是用户看到的「跑位」。这里自己管 NSScrollView，
/// 先算好偏移再一次性写入，中间没有可见的过渡状态。
final class TimelineScrollView: NSScrollView {
    /// 捏合倍数交回 SwiftUI（缩放值统一由 AppState 持有）。
    var onMagnify: ((CGFloat) -> Void)?
    /// 捏合中点（滚动视图坐标）在主轴上的位置，作为缩放锚点。
    var anchorPointer: CGFloat?
    var scrollsHorizontally = true
    private var isPinching = false

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch event.phase {
        case .began, .changed:
            isPinching = true
            anchorPointer = scrollsHorizontally ? point.x : point.y
        case .ended, .cancelled:
            isPinching = false
        default:
            break
        }
        onMagnify?(event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        // 捏合时双指的移动会带出滚动事件，吞掉，否则时间轴会被手指带着跑。
        guard !isPinching else { return }
        super.scrollWheel(with: event)
    }
}

/// 拖拽到视口边缘时由画布调用，按需微调滚动位置。
final class TimelineScrollProxy {
    weak var scrollView: NSScrollView?

    func nudge(_ delta: CGFloat, horizontal: Bool) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        if horizontal {
            let maxValue = max(0, document.frame.width - clip.bounds.width)
            origin.x = min(max(0, origin.x + delta), maxValue)
        } else {
            let maxValue = max(0, document.frame.height - clip.bounds.height)
            origin.y = min(max(0, origin.y + delta), maxValue)
        }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}

/// 把画布尺寸与滚动偏移放在同一次更新里写的协调器。
final class TimelineScrollCoordinator {
    weak var scrollView: TimelineScrollView?
    /// 时间轴方向两端的留白，换算锚点时要扣掉。
    var timeInset: CGFloat = 8
    var orientation: TimelineOrientation = .horizontal
    var onOffsetChange: ((CGFloat) -> Void)?
    var proxy: TimelineScrollProxy?
    private var appliedSize: CGSize = .zero
    private var appliedOrientation: TimelineOrientation = .horizontal
    /// 上一次落在旧方向轴上的偏移，方向切换时用它换算旧视口中心时间。
    private var lastOffset: CGFloat = 0
    private var lastScopeID: String = ""
    private var observer: NSObjectProtocol?

    func attach(_ scrollView: TimelineScrollView) {
        guard self.scrollView !== scrollView else { return }
        self.scrollView = scrollView
        proxy?.scrollView = scrollView
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self, let scrollView = self.scrollView else { return }
            let offset = self.currentOffset(scrollView)
            self.lastOffset = offset
            self.onOffsetChange?(offset)
        }
    }

    private func currentOffset(_ scrollView: NSScrollView) -> CGFloat {
        orientation.isHorizontal
            ? scrollView.contentView.bounds.origin.x
            : scrollView.contentView.bounds.origin.y
    }

    /// 内容尺寸、方向或展示范围变化时调用：先算锚点时间，再同批写画布尺寸和偏移。
    func apply(
        contentSize: CGSize,
        orientation: TimelineOrientation,
        hostingView: NSView,
        rangeStart: Date,
        pixelsPerHour: CGFloat,
        focusTime: Date?,
        scopeID: String
    ) {
        guard let scrollView else { return }
        let horizontal = orientation.isHorizontal
        scrollView.scrollsHorizontally = horizontal

        let clip = scrollView.contentView
        let visible = horizontal ? clip.bounds.width : clip.bounds.height
        let rawOffset = horizontal ? clip.bounds.origin.x : clip.bounds.origin.y
        let oldAxisLength = appliedOrientation.isHorizontal ? appliedSize.width : appliedSize.height
        let newAxisLength = horizontal ? contentSize.width : contentSize.height
        let sizeChanged = abs(contentSize.width - appliedSize.width) > 0.01
            || abs(contentSize.height - appliedSize.height) > 0.01
        let orientationChanged = appliedOrientation != orientation
        let scopeChanged = scopeID != lastScopeID
        guard sizeChanged || orientationChanged || scopeChanged, visible > 0 else { return }

        // 锚点：捏合时用双指中点，按钮 / 窗口变化时用视口中心。
        var pointer = min(max(scrollView.anchorPointer ?? visible / 2, 0), visible)
        var oldOffset = rawOffset
        if orientationChanged {
            // 旧偏移在另一根轴上，直接读会跳位；改用旧视口中心对应的偏移。
            pointer = visible / 2
            oldOffset = lastOffset
        }

        var target = oldOffset
        if scopeChanged, let focusTime {
            // 切换日期 / 筛选范围：把焦点时间放到视口中心。
            let axis = timeInset + CGFloat(focusTime.timeIntervalSince(rangeStart) / 3600) * pixelsPerHour
            target = axis - visible / 2
        } else {
            let oldSpan = oldAxisLength - timeInset * 2
            let newSpan = newAxisLength - timeInset * 2
            if oldSpan > 1, newSpan > 1 {
                let fraction = (oldOffset + pointer - timeInset) / oldSpan
                target = timeInset + fraction * newSpan - pointer
            }
        }

        // 画布尺寸与偏移在同一批里写，中间不会出现被旧尺寸裁过的偏移。
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        appliedSize = contentSize
        appliedOrientation = orientation
        self.orientation = orientation
        scrollView.anchorPointer = nil
        lastScopeID = scopeID

        let clamped = min(max(0, target), max(0, newAxisLength - visible))
        lastOffset = clamped
        clip.scroll(to: horizontal ? NSPoint(x: clamped, y: 0) : NSPoint(x: 0, y: clamped))
        scrollView.reflectScrolledClipView(clip)
        onOffsetChange?(clamped)
    }
}

struct TimelineScrollHost: NSViewRepresentable {
    let contentSize: CGSize
    let orientation: TimelineOrientation
    let timeInset: CGFloat
    let rangeStart: Date
    let pixelsPerHour: CGFloat
    /// 进入某个日期 / 筛选范围时希望居中的时间。
    let focusTime: Date?
    /// 日期 + 筛选的标识，变化时执行新的初始定位。
    let scopeID: String
    let content: AnyView
    let onMagnify: (CGFloat) -> Void
    let onOffsetChange: (CGFloat) -> Void
    let proxy: TimelineScrollProxy

    func makeCoordinator() -> TimelineScrollCoordinator {
        let coordinator = TimelineScrollCoordinator()
        coordinator.orientation = orientation
        coordinator.timeInset = timeInset
        coordinator.onOffsetChange = onOffsetChange
        coordinator.proxy = proxy
        return coordinator
    }

    func makeNSView(context: Context) -> TimelineScrollView {
        let scrollView = TimelineScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollsHorizontally = orientation.isHorizontal
        scrollView.onMagnify = onMagnify

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        scrollView.documentView = hosting

        context.coordinator.attach(scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: TimelineScrollView, context: Context) {
        nsView.onMagnify = onMagnify
        context.coordinator.orientation = orientation
        context.coordinator.timeInset = timeInset
        context.coordinator.onOffsetChange = onOffsetChange
        guard let hosting = nsView.documentView as? NSHostingView<AnyView> else { return }
        hosting.rootView = content
        context.coordinator.apply(
            contentSize: contentSize,
            orientation: orientation,
            hostingView: hosting,
            rangeStart: rangeStart,
            pixelsPerHour: pixelsPerHour,
            focusTime: focusTime,
            scopeID: scopeID
        )
    }
}
