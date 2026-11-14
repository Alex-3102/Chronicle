import SwiftUI
import AppKit

@main
struct ChronicleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Chronicle", id: "main") {
            RootView()
                .environmentObject(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Chronicle") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .appInfo) {
                Button("从本地文件更新…") {
                    AppUpdater.shared.chooseDMG()
                }
            }

            CommandGroup(after: .sidebar) {
                Button("放大时间轴") {
                    app.adjustTimelineZoom(by: 1.5)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("缩小时间轴") {
                    app.adjustTimelineZoom(by: 1 / 1.5)
                }
                .keyboardShortcut("-", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("新建时间条目") {
                    app.newEntryPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("新建项目") {
                    app.newProjectPresented = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("临时计时") {
                    app.openTempTimer()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        Window("关于 Chronicle", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 468)

        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
