import AppKit
import SwiftUI

final class FloatingTimerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TempTimerWindowController {
    private weak var appState: AppState?
    private var panel: FloatingTimerPanel?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard let appState else { return }

        if panel == nil {
            let content = TempTimerView(model: appState.tempTimer)
                .environmentObject(appState)
                .frame(width: 300, height: 372)

            let panel = FloatingTimerPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 372),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: content)
            panel.center()
            self.panel = panel
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
    }
}
