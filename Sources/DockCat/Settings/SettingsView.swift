import DockCatCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var menuBarVisibility: MenuBarVisibilityController
    let settingsPresenter: SettingsWindowPresenter
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Form {
                Toggle("Enable DockCat", isOn: Binding(
                    get: { state.runtimeMode.isEnabled },
                    set: { state.setDockCatEnabled($0) }
                ))
                .disabled(state.runtimeMode.isTransitioning || state.runtimeMode == .shuttingDown)
                LabeledContent("Runtime", value: runtimeTitle)
                Toggle("Pause notification delivery", isOn: Binding(
                    get: { state.runtimeMode == .deliveryPaused },
                    set: { state.setPaused($0) }
                ))
                    .disabled(!state.canMutatePause)
                Text("Delivery pause preserves the active notification and queue. Disabling clears all delivery work and hides overlays.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show menu-bar icon", isOn: Binding(
                    get: { menuBarVisibility.isVisible },
                    set: { menuBarVisibility.requestVisibility($0) }
                ))
                .disabled(menuBarVisibility.isChanging)
                Toggle("Launch at login", isOn: Binding(get: { state.settings.launchAtLogin }, set: { enabled in state.settings.setLaunchAtLogin(enabled) }))
                if let error = state.settings.loginItemError { Text(error).foregroundStyle(.red).font(.caption) }
            }.padding().tabItem { Label("General", systemImage: "gear") }.tag(0)
            Form {
                Section("Placement") {
                    Picker("Display", selection: placementBinding(\.displaySelection)) {
                        Text("Automatic (stable)").tag(DisplaySelection.automatic)
                        Text("Main display").tag(DisplaySelection.main)
                        ForEach(state.displayCatalog.descriptors, id: \.identity) { display in
                            Text(displayPickerTitle(display)).tag(DisplaySelection.specific(display.identity))
                        }
                        if selectedSpecificDisplayIsDisconnected,
                           case .specific(let identity) = state.settings.preferences.displaySelection {
                            Text("Selected display (disconnected)")
                                .tag(DisplaySelection.specific(identity))
                        }
                    }
                    if let placement = state.currentPlacement {
                        LabeledContent("Resolved display", value: placement.displayName)
                        LabeledContent("Dock edge", value: placement.edge.rawValue.capitalized)
                        LabeledContent("Geometry", value: confidenceTitle(placement.geometryConfidence))
                        if !placement.requestedDisplayAvailable {
                            Label(
                                "The selected display is disconnected. DockCat is using a temporary fallback without changing your preference.",
                                systemImage: "exclamationmark.triangle.fill"
                            ).foregroundStyle(.orange)
                        } else if placement.usedDisplayFallback,
                                  case .specific = state.settings.preferences.displaySelection {
                            Label(
                                "The selected display has reconnected. DockCat will restore it after the active presentation finishes.",
                                systemImage: "clock.arrow.circlepath"
                            ).foregroundStyle(.orange)
                        }
                    }
                    Picker("Sleeping corner", selection: placementBinding(\.sleepingCorner)) {
                        Text("Start of Dock").tag(DockCatPreferences.SleepingCorner.start)
                        Text("End of Dock").tag(DockCatPreferences.SleepingCorner.end)
                    }
                    LabeledContent("Distance from Dock") {
                        Slider(value: placementBinding(\.positionOffset), in: -20...80).frame(width: 220)
                    }
                    LabeledContent("Trash-side adjustment") {
                        Slider(value: placementBinding(\.dockEndOffset), in: -300...300).frame(width: 220)
                    }
                    Slider(value: placementBinding(\.cardOffset), in: 0...100) { Text("Card offset") }
                    Slider(value: Binding(
                        get: { state.settings.preferences.catScale },
                        set: { state.setCatScale($0) }
                    ), in: 0.5...2) { Text("Cat scale") }
                }

                Section("Dock anchor calibration") {
                    Text("macOS public APIs expose the Dock edge and an estimated inset, not its exact visual ends. Calibrate the current display and Dock edge in points.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let placement = state.currentPlacement,
                       placement.geometryConfidence != .observedVisibleFrameInset {
                        Label("Calibration is recommended for this estimated geometry.", systemImage: "ruler")
                            .foregroundStyle(.orange)
                    }
                    calibrationSlider("Home along Dock", anchor: .home, axis: .alongDock, range: DockAnchorCalibration.alongDockRange)
                    calibrationSlider("Home away from Dock", anchor: .home, axis: .awayFromDock, range: DockAnchorCalibration.awayFromDockRange)
                    calibrationSlider("Presentation along Dock", anchor: .presentation, axis: .alongDock, range: DockAnchorCalibration.alongDockRange)
                    calibrationSlider("Presentation away from Dock", anchor: .presentation, axis: .awayFromDock, range: DockAnchorCalibration.awayFromDockRange)
                    HStack {
                        Button("Reset Current") { resetCurrentCalibration() }
                            .disabled(!canCalibrate)
                        Button("Reset All") {
                            state.settings.preferences.resetAllCalibrations()
                            state.refreshPlacement()
                        }
                            .disabled(state.settings.preferences.dockCalibrations.isEmpty)
                        Spacer()
                        if state.isCalibrationPreviewActive {
                            Button("Stop Preview") { state.stopCalibrationPreview() }
                        } else {
                            Button("Start Preview") { state.startCalibrationPreview() }
                                .disabled(!canCalibrate || !state.runtimeMode.acceptsSubmissions)
                        }
                    }
                }
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
                Slider(value: Binding(
                    get: { state.settings.preferences.animationSpeed },
                    set: { state.setAnimationSpeed($0) }
                ), in: 0.25...3) { Text("Animation speed") }
                Toggle("Reduced motion", isOn: Binding(
                    get: { state.settings.preferences.reducedMotion },
                    set: { state.setAppReducedMotion($0) }
                ))
                Toggle("Disable walking", isOn: Binding(
                    get: { state.settings.preferences.disableWalking },
                    set: { state.setDisableWalking($0) }
                ))
                Toggle("Idle breathing", isOn: Binding(
                    get: { state.settings.preferences.idleAnimation },
                    set: { state.setIdleAnimation($0) }
                ))
                Toggle("Pause visual animations", isOn: Binding(
                    get: { state.settings.preferences.pauseAnimations },
                    set: { state.setPauseAnimations($0) }
                ))
                Text("Notifications continue to be delivered; visual transitions complete immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }.padding().tabItem { Label("Animation", systemImage: "figure.walk") }.tag(4)
            NotificationSimulatorView(state: state).padding().tabItem { Label("Developer", systemImage: "hammer") }.tag(5)
        }
        .frame(width: 600, height: 580)
        .onDisappear { state.stopCalibrationPreview() }
        .alert(
            "Hide DockCat’s Menu Item?",
            isPresented: Binding(
                get: { menuBarVisibility.isHideConfirmationPending },
                set: { if !$0 { menuBarVisibility.cancelHide() } }
            )
        ) {
            Button("Copy Recovery Command") {
                copyRecoveryCommand()
                menuBarVisibility.cancelHide()
            }
            Button("Cancel", role: .cancel) { menuBarVisibility.cancelHide() }
            Button("Hide Menu Item", role: .destructive) { menuBarVisibility.confirmHide() }
        } message: {
            Text("DockCat is an accessory app and has no normal Dock icon. Hiding this item does not pause notifications or disable DockCat. Reopen Settings with dockcat://settings, or restore the paw with the recovery command.")
        }
        .alert(
            "Menu Item Cannot Be Hidden",
            isPresented: Binding(
                get: { menuBarVisibility.recoveryConfigurationError != nil },
                set: { if !$0 { menuBarVisibility.dismissRecoveryConfigurationError() } }
            )
        ) {
            Button("Open Settings", role: .cancel) {
                settingsPresenter.present(source: .hideConfirmationHelp)
                menuBarVisibility.dismissRecoveryConfigurationError()
            }
        } message: {
            Text(menuBarVisibility.recoveryConfigurationError?.userMessage ?? "Recovery is unavailable in this app build.")
        }
    }

    private func copyRecoveryCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            MenuBarVisibilityController.recoveryCommand,
            forType: .string
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DockCatPreferences, T>) -> Binding<T> {
        Binding(get: { state.settings.preferences[keyPath: keyPath] }, set: { state.settings.preferences[keyPath: keyPath] = $0 })
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

    private func placementBinding<T>(
        _ keyPath: WritableKeyPath<DockCatPreferences, T>
    ) -> Binding<T> {
        Binding(
            get: { state.settings.preferences[keyPath: keyPath] },
            set: {
                state.settings.preferences[keyPath: keyPath] = $0
                state.refreshPlacement()
            }
        )
    }

    private enum CalibrationAnchor { case home, presentation }
    private enum CalibrationAxis { case alongDock, awayFromDock }

    private var canCalibrate: Bool {
        state.isCalibrationAvailable
    }

    private var selectedSpecificDisplayIsDisconnected: Bool {
        guard case .specific(let selected) = state.settings.preferences.displaySelection else { return false }
        return !state.displayCatalog.descriptors.contains { $0.identity == selected }
    }

    private func displayPickerTitle(_ display: DisplayDescriptor) -> String {
        let builtIn = display.isBuiltIn ? " — Built-in" : ""
        return "\(display.localizedName)\(builtIn) · \(display.identity.diagnosticsToken)"
    }

    private func confidenceTitle(_ confidence: DockGeometryConfidence) -> String {
        switch confidence {
        case .observedVisibleFrameInset: "Observed visible-frame inset"
        case .autoHideFallbackEstimate: "Auto-hide estimate"
        case .ambiguousEstimate: "Ambiguous estimate"
        }
    }

    @ViewBuilder
    private func calibrationSlider(
        _ title: String,
        anchor: CalibrationAnchor,
        axis: CalibrationAxis,
        range: ClosedRange<Double>
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: calibrationBinding(anchor: anchor, axis: axis), in: range)
                    .frame(width: 190)
                Text("\(calibrationBinding(anchor: anchor, axis: axis).wrappedValue, specifier: "%.0f") pt")
                    .monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }.disabled(!canCalibrate)
    }

    private func calibrationBinding(
        anchor: CalibrationAnchor,
        axis: CalibrationAxis
    ) -> Binding<Double> {
        Binding(
            get: {
                guard let placement = state.currentPlacement else { return 0 }
                let calibration = state.settings.preferences.calibration(
                    for: placement.displayIdentity, edge: placement.edge
                )
                return switch (anchor, axis) {
                case (.home, .alongDock): calibration.home.alongDock
                case (.home, .awayFromDock): calibration.home.awayFromDock
                case (.presentation, .alongDock): calibration.presentation.alongDock
                case (.presentation, .awayFromDock): calibration.presentation.awayFromDock
                }
            },
            set: { value in
                guard state.isCalibrationAvailable,
                      let placement = state.currentPlacement else { return }
                var calibration = state.settings.preferences.calibration(
                    for: placement.displayIdentity, edge: placement.edge
                )
                switch (anchor, axis) {
                case (.home, .alongDock): calibration.home = .init(alongDock: value, awayFromDock: calibration.home.awayFromDock)
                case (.home, .awayFromDock): calibration.home = .init(alongDock: calibration.home.alongDock, awayFromDock: value)
                case (.presentation, .alongDock): calibration.presentation = .init(alongDock: value, awayFromDock: calibration.presentation.awayFromDock)
                case (.presentation, .awayFromDock): calibration.presentation = .init(alongDock: calibration.presentation.alongDock, awayFromDock: value)
                }
                state.settings.preferences.setCalibration(
                    calibration, for: placement.displayIdentity, edge: placement.edge
                )
                state.refreshPlacement()
            }
        )
    }

    private func resetCurrentCalibration() {
        guard state.isCalibrationAvailable,
              let placement = state.currentPlacement else { return }
        state.settings.preferences.resetCalibration(
            for: placement.displayIdentity, edge: placement.edge
        )
        state.refreshPlacement()
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
        case .processUnavailable: "Notification Center is not currently available and will be retried."
        case .noUsefulNotifications: "No compatible notification events were available."
        case .globallyDisabled: "Your System Notifications preference is preserved, but observation is stopped while DockCat is globally disabled."
        case nil: access.health.state == .disabled ? "Disabled by your System Notifications preference." : "Source lifecycle status."
        }
    }

    private var statusIcon: String {
        access.health.isHealthy ? "checkmark.circle.fill" : "info.circle"
    }
}
