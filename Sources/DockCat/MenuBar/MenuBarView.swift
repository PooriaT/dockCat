import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Button("Show Settings") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Send Test Transient Notification") { state.sendTest() }
        Button("Send Test Persistent Notification") { state.sendTest(persistent: true) }
        Divider()
        Button(state.isPaused ? "Resume DockCat" : "Pause DockCat") { state.setPaused(!state.isPaused) }
        Text("Cat: \(state.catState.rawValue)").font(.caption)
        Divider()
        Button("Quit DockCat") { NSApp.terminate(nil) }
    }
}
