import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var tab = 0
    @AppStorage("DockCat.menuBarVisible") private var menuBarVisible = true
    var body: some View {
        TabView(selection: $tab) {
            Form {
                Toggle("Enable DockCat", isOn: binding(\.enabled))
                Toggle("Pause DockCat", isOn: Binding(get: { state.isPaused }, set: { state.setPaused($0) }))
                Toggle("Show menu-bar icon", isOn: $menuBarVisible)
                Toggle("Launch at login", isOn: Binding(get: { state.settings.launchAtLogin }, set: { enabled in state.settings.setLaunchAtLogin(enabled) }))
                if let error = state.settings.loginItemError { Text(error).foregroundStyle(.red).font(.caption) }
            }.padding().tabItem { Label("General", systemImage: "gear") }.tag(0)
            Form {
                Picker("Display", selection: binding(\.displaySelection)) {
                    Text("Automatic").tag("automatic")
                    Text("Main display").tag("main")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(DockLocator.identifier(for: screen))
                    }
                }
                Picker("Sleeping corner", selection: binding(\.sleepingCorner)) { Text("Start of Dock").tag(DockCatPreferences.SleepingCorner.start); Text("End of Dock").tag(DockCatPreferences.SleepingCorner.end) }
                LabeledContent("Distance from Dock") { Slider(value: binding(\.positionOffset), in: -20...80).frame(width: 220) }
                LabeledContent("Trash-side adjustment") { Slider(value: binding(\.dockEndOffset), in: -300...300).frame(width: 220) }
                Slider(value: binding(\.cardOffset), in: 0...100) { Text("Card offset") }
                Slider(value: binding(\.catScale), in: 0.5...2) { Text("Cat scale") }
            }.padding().tabItem { Label("Position", systemImage: "dock.rectangle") }.tag(1)
            Form {
                Stepper("Default duration: \(state.settings.preferences.defaultTransientDuration, specifier: "%.0f") seconds", value: binding(\.defaultTransientDuration), in: 1...60)
                Stepper("Queue limit: \(state.settings.preferences.queueLimit)", value: binding(\.queueLimit), in: 1...100)
                Toggle("Allow manual transient dismissal", isOn: binding(\.transientManuallyDismissible))
                Toggle("Open action when requested", isOn: binding(\.clickCardOpensAction))
                Toggle("Stay at queued messages", isOn: binding(\.remainForQueuedMessages))
            }.padding().tabItem { Label("Notifications", systemImage: "bell") }.tag(2)
            Form {
                Slider(value: binding(\.animationSpeed), in: 0.25...3) { Text("Animation speed") }
                Toggle("Reduced motion", isOn: binding(\.reducedMotion))
                Toggle("Disable walking", isOn: binding(\.disableWalking))
                Toggle("Idle breathing", isOn: binding(\.idleAnimation))
            }.padding().tabItem { Label("Animation", systemImage: "figure.walk") }.tag(3)
            NotificationSimulatorView(state: state).padding().tabItem { Label("Developer", systemImage: "hammer") }.tag(4)
        }
        .frame(width: 560, height: 430)
        .onChange(of: state.settings.preferences) { _, _ in state.refreshPlacement() }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<DockCatPreferences, T>) -> Binding<T> {
        Binding(get: { state.settings.preferences[keyPath: keyPath] }, set: { state.settings.preferences[keyPath: keyPath] = $0 })
    }
}
