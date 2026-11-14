import AppKit
import Foundation
import UniformTypeIdentifiers

/// 一个 bundle 的版本信息：短版本号 + 构建号。
struct AppVersion {
    let short: String
    let build: String

    var display: String {
        build.isEmpty ? short : "\(short) (\(build))"
    }
}

/// 从本地安装包更新：挂载 → 复制新版本 → 退出后替换并重启。
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private init() {}

    func chooseDMG() {
        let panel = NSOpenPanel()
        panel.title = "从本地文件更新"
        panel.message = "选择 Chronicle 的安装包（.dmg），安装完成后会自动重启。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: "dmg") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        install(from: url)
    }

    private func install(from dmgURL: URL) {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("ChronicleMount-\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        } catch {
            fail("无法准备安装目录：\(error.localizedDescription)")
            return
        }

        guard runProcess("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, dmgURL.path
        ]) else {
            try? fm.removeItem(at: mountPoint)
            fail("无法挂载这个文件，请确认它是有效的安装包。")
            return
        }

        defer {
            _ = runProcess("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? fm.removeItem(at: mountPoint)
        }

        guard let appURL = findApp(in: mountPoint) else {
            fail("安装包里没有找到 Chronicle.app。")
            return
        }

        let staging = fm.temporaryDirectory.appendingPathComponent("ChronicleUpdate-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = staging.appendingPathComponent("Chronicle.app", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.copyItem(at: appURL, to: stagedApp)
        } catch {
            fail("复制新版本失败：\(error.localizedDescription)")
            return
        }

        let destination = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            try? fm.removeItem(at: staging)
            fail("当前版本所在目录不可写。请先把 Chronicle.app 移到「应用程序」文件夹，再使用本地文件更新。")
            return
        }

        let newVersion = version(at: stagedApp)
        let currentVersion = version(at: destination)

        // 已经是最新（或更旧）就不走替换流程，避免同一版本反复安装。
        if let newVersion, let currentVersion, !isNewer(newVersion, than: currentVersion) {
            try? fm.removeItem(at: staging)
            let alert = NSAlert()
            alert.messageText = "已是最新版本"
            alert.informativeText = """
            当前版本 \(currentVersion.display)，选择的安装包是 \(newVersion.display)，无需更新。

            当前副本：\(destination.path)
            """
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "安装 Chronicle \(newVersion?.display ?? "未知版本")？"
        alert.informativeText = """
        当前版本 \(currentVersion?.display ?? "未知版本")
        当前副本：\(destination.path)

        安装完成后 Chronicle 会自动重启，本地记录不会丢失。
        """
        alert.addButton(withTitle: "安装并重启")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            try? fm.removeItem(at: staging)
            return
        }

        let script = """
        #!/bin/sh
        sleep 1
        rm -rf "\(destination.path)"
        /usr/bin/ditto "\(stagedApp.path)" "\(destination.path)"
        /usr/bin/xattr -cr "\(destination.path)" 2>/dev/null
        /usr/bin/open "\(destination.path)"
        rm -rf "\(staging.path)"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            fail("启动安装脚本失败：\(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }

    private func findApp(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let apps = contents.filter { $0.pathExtension.lowercased() == "app" }
        if let exact = apps.first(where: { bundleIdentifier(at: $0) == "com.chronicle.app" }) {
            return exact
        }
        if let named = apps.first(where: { $0.lastPathComponent.lowercased().contains("chronicle") }) {
            return named
        }
        return apps.first
    }

    /// 直接从 bundle 里的 Info.plist 读取版本。
    /// 不用 `Bundle(url:)`：它可能返回进程内已缓存的 bundle，导致读到的版本号和磁盘上的不一致。
    private func version(at url: URL) -> AppVersion? {
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let short = (plist["CFBundleShortVersionString"] as? String) ?? ""
        let build = (plist["CFBundleVersion"] as? String) ?? ""
        guard !short.isEmpty || !build.isEmpty else { return nil }
        return AppVersion(short: short, build: build)
    }

    /// 1.11 > 1.9，而字符串比较会得出相反结论，所以按点分段转成数字比较。
    private func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? 1 : -1 }
        }
        return 0
    }

    private func isNewer(_ candidate: AppVersion, than current: AppVersion) -> Bool {
        let byShort = compare(candidate.short, current.short)
        if byShort != 0 { return byShort > 0 }
        return compare(candidate.build, current.build) > 0
    }

    private func bundleIdentifier(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    @discardableResult
    private func runProcess(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func fail(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "更新失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
