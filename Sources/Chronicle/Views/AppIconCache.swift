import AppKit

/// 按 bundle id 缓存真实的应用图标，避免时间轴频繁缩放时重复查询。
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var cache: [String: NSImage?] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] {
            return cached
        }
        var image: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache[bundleID] = image
        return image
    }
}
