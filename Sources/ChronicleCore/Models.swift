import Foundation

public struct Project: Identifiable, Hashable, Codable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var parentID: String?
    public var isGroup: Bool
    public var sortOrder: Int
    public var isArchived: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String,
        parentID: String? = nil,
        isGroup: Bool = false,
        sortOrder: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.parentID = parentID
        self.isGroup = isGroup
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
}

public enum EntrySource: String, Codable {
    case manual
    case timer
    case temporary
    case app
}

public struct TimeEntry: Identifiable, Hashable {
    public var id: String
    public var projectID: String?
    public var title: String
    public var note: String
    public var start: Date
    public var end: Date
    public var source: EntrySource

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(
        id: String = UUID().uuidString,
        projectID: String? = nil,
        title: String,
        note: String = "",
        start: Date,
        end: Date,
        source: EntrySource = .manual
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.note = note
        self.start = start
        self.end = end
        self.source = source
    }
}

public struct AppUsageRecord: Identifiable, Hashable {
    public var id: String
    public var bundleID: String
    public var appName: String
    public var start: Date
    public var end: Date
    /// 前台窗口标题（需要屏幕录制权限，取不到时为 nil）
    public var windowTitle: String?

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(
        id: String = UUID().uuidString,
        bundleID: String,
        appName: String,
        start: Date,
        end: Date,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.start = start
        self.end = end
        self.windowTitle = windowTitle
    }
}

public struct AppUsageTotal: Identifiable, Hashable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String
    public var seconds: TimeInterval

    public init(bundleID: String, appName: String, seconds: TimeInterval) {
        self.bundleID = bundleID
        self.appName = appName
        self.seconds = seconds
    }
}

public struct ProjectTotal: Identifiable, Hashable {
    public var id: String
    public var seconds: TimeInterval

    public init(id: String, seconds: TimeInterval) {
        self.id = id
        self.seconds = seconds
    }
}
