import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    let settingsPresenter: SettingsWindowPresenter

    var body: some View {
        Button("Show Settings") { settingsPresenter.present(source: .menu) }
        Divider()
        Button(state.runtimeMode.isEnabled ? "Disable DockCat" : "Enable DockCat") {
            state.setDockCatEnabled(!state.runtimeMode.isEnabled)
        }
        .disabled(state.runtimeMode.isTransitioning || state.runtimeMode == .shuttingDown)
        Text("Runtime: \(runtimeTitle)").font(.caption)
        Divider()
        Button("Send Test Transient Notification") { state.sendTest() }
            .disabled(!state.canSubmitNotifications)
        Button("Send Test Persistent Notification") { state.sendTest(persistent: true) }
            .disabled(!state.canSubmitNotifications)
        Divider()
        Button(state.runtimeMode == .deliveryPaused ? "Resume Delivery" : "Pause Delivery") {
            state.setPaused(state.runtimeMode != .deliveryPaused)
        }
            .disabled(!state.canMutatePause)
        Text("Cat: \(state.catState.rawValue)").font(.caption)
        Text("System Notifications: \(systemSourceTitle)").font(.caption)
        Divider()
        Button("Quit DockCat") { NSApp.terminate(nil) }
    }

    private var runtimeTitle: String {
        switch state.runtimeMode {
        case .enabling: "Enabling"
        case .running: "Running"
        case .deliveryPaused: "Delivery paused"
        case .disabling: "Disabling"
        case .disabled: "Disabled"
        case .shuttingDown: "Shutting down"
        }
    }

    private var systemSourceTitle: String {
        if state.systemNotificationAccess.health.reason == .globallyDisabled {
            return "Stopped while DockCat is disabled"
        }
        return state.systemNotificationAccess.health.state.rawValue.capitalized
    }
}
