import DockCatCore
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
                    .disabled(state.isPauseTransitioning)
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
            SystemNotificationsSettingsView(state: state)
                .padding()
                .tabItem { Label("System", systemImage: "bell.badge") }
                .tag(3)
            Form {
                Slider(value: binding(\.animationSpeed), in: 0.25...3) { Text("Animation speed") }
                Toggle("Reduced motion", isOn: binding(\.reducedMotion))
                Toggle("Disable walking", isOn: binding(\.disableWalking))
                Toggle("Idle breathing", isOn: binding(\.idleAnimation))
            }.padding().tabItem { Label("Animation", systemImage: "figure.walk") }.tag(4)
            NotificationSimulatorView(state: state).padding().tabItem { Label("Developer", systemImage: "hammer") }.tag(5)
        }
        .frame(width: 560, height: 430)
        .onChange(of: state.settings.preferences) { _, _ in state.refreshPlacement() }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<DockCatPreferences, T>) -> Binding<T> {
        Binding(get: { state.settings.preferences[keyPath: keyPath] }, set: { state.settings.preferences[keyPath: keyPath] = $0 })
    }
}

private struct SystemNotificationsSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var access: SystemNotificationAccessController
    @State private var exclusionIdentifier = ""

    init(state: AppState) {
        self.state = state
        _access = ObservedObject(wrappedValue: state.systemNotificationAccess)
    }

    var body: some View {
        Form {
            Section("System Notifications (Experimental)") {
                Toggle("Enable experimental System Notifications", isOn: Binding(
                    get: { state.settings.preferences.systemNotificationsEnabled },
                    set: { state.setSystemNotificationsEnabled($0) }
                ))
                Label(statusTitle, systemImage: statusIcon)
                Text(statusDetail).font(.caption).foregroundStyle(.secondary)
            }
            Section("Accessibility permission") {
                Text("Accessibility access is needed so a future observer can read visible notification text locally. Permission is never requested automatically.")
                HStack {
                    Button("Request Accessibility Permission") { access.requestPermission() }
                        .disabled(!state.settings.preferences.systemNotificationsEnabled)
                    Button("Recheck") { access.refresh() }
                }
                if access.health.reason == .permissionRevoked {
                    Text("Permission was revoked. Re-enable DockCat in System Settings, then choose Recheck.")
                        .foregroundStyle(.orange)
                }
            }
            Section("Original banner (Experimental)") {
                Toggle("Best-effort close original banner after capture", isOn: Binding(
                    get: { state.settings.preferences.closeOriginalBannerAfterCapture },
                    set: { state.settings.preferences.closeOriginalBannerAfterCapture = $0 }
                ))
                .disabled(!state.settings.preferences.systemNotificationsEnabled || !access.health.isHealthy)
                Text("DockCat acts only after a mirrored notification is accepted. The native banner may appear briefly or may remain visible. Close-control compatibility can change across macOS versions.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Bundle identifier (for example, com.example.app)", text: $exclusionIdentifier)
                    Button("Add") { addExclusion() }.disabled(normalizedExclusion.isEmpty || isOwnBundleIdentifier)
                }
                ForEach(state.settings.preferences.nativeBannerDismissalExcludedBundleIdentifiers, id: \.self) { identifier in
                    HStack {
                        Text(friendlyName(for: identifier)).fontWeight(.medium)
                        Text(identifier).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { removeExclusion(identifier) }
                    }
                }
                Text("Exclusions affect closing the original only; notifications are still mirrored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Limitations") {
                Text("Close detection deliberately fails closed and never runs reply, open, options, destructive, or content actions. This is not pre-display suppression.")
            }
        }
        .onAppear { access.refresh() }
    }

    private var normalizedExclusion: String { DockCatPreferences.normalizeBundleIdentifier(exclusionIdentifier) }
    private var isOwnBundleIdentifier: Bool {
        normalizedExclusion == DockCatPreferences.normalizeBundleIdentifier(Bundle.main.bundleIdentifier ?? "com.example.DockCat")
    }
    private func addExclusion() {
        guard !normalizedExclusion.isEmpty, !isOwnBundleIdentifier else { return }
        state.settings.preferences.nativeBannerDismissalExcludedBundleIdentifiers = DockCatPreferences.normalizedBundleIdentifiers(
            state.settings.preferences.nativeBannerDismissalExcludedBundleIdentifiers + [normalizedExclusion]
        )
        exclusionIdentifier = ""
    }
    private func removeExclusion(_ identifier: String) {
        state.settings.preferences.nativeBannerDismissalExcludedBundleIdentifiers.removeAll { $0 == identifier }
    }
    private func friendlyName(for identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
              let bundle = Bundle(url: url) else { return "Unknown application" }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown application"
    }

    private var statusTitle: String {
        switch access.health.state {
        case .disabled: "Disabled"
        case .permissionRequired: "Accessibility permission required"
        case .starting: "Starting"
        case .active: "Active"
        case .degraded: "Degraded"
        case .unavailable: "Unavailable"
        }
    }

    private var statusDetail: String {
        switch access.health.reason {
        case .permissionMissing: "Enable the source, then request permission when you are ready."
        case .permissionRevoked: "The source has stopped because Accessibility permission is no longer available."
        case .observerNotImplemented: "Permission is available, but notification observation is deferred to issue #68."
        case .compatibilityProblem: "The source reported a compatibility problem and may be retried."
        case .startupFailed: "The source could not start and may be retried."
        case nil: access.health.state == .disabled ? "This setting is independent from Enable DockCat." : "Source lifecycle status."
        }
    }

    private var statusIcon: String {
        access.health.isHealthy ? "checkmark.circle.fill" : "info.circle"
    }
}
