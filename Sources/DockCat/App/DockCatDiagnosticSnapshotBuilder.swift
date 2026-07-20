import AppKit
import DockCatCore
import Foundation

@MainActor
final class DockCatDiagnosticSnapshotBuilder {
    let state: AppState
    let recorder: DockCatDiagnosticEventRecorder
    init(state: AppState, recorder: DockCatDiagnosticEventRecorder) { self.state = state; self.recorder = recorder }

    func snapshot() async -> DockCatDiagnosticSnapshot {
        let first = await state.diagnosticProjection()
        let events = await recorder.snapshot()
        let secondQueue = await state.queueDiagnosticSnapshot()
        return DockCatDiagnosticSnapshot(
            generatedAt: Date(),
            consistency: .init(queueRevisionStable: first.queueRevision == secondQueue.revision, initialQueueRevision: first.queueRevision, finalQueueRevision: secondQueue.revision),
            application: applicationInfo(), runtime: first.runtime, sources: first.sources, queue: first.queue, presentation: first.presentation,
            placement: first.placement, accessibility: first.accessibility, recentEvents: events
        )
    }

    func encodedSnapshot() async throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(await snapshot()), as: UTF8.self)
    }

    private func applicationInfo() -> DiagnosticApplicationInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        #if DEBUG
        let config = "Debug"
        #else
        let config = "Release"
        #endif
        return .init(productName: (info["CFBundleName"] as? String) ?? DockCatProductIdentity.productName,
                     bundleIdentifier: Bundle.main.bundleIdentifier ?? DockCatProductIdentity.fallbackBundleIdentifier,
                     marketingVersion: (info["CFBundleShortVersionString"] as? String) ?? "0.1.0",
                     buildNumber: (info["CFBundleVersion"] as? String) ?? "1",
                     macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                     processArchitecture: Self.architecture, buildConfiguration: config)
    }
    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
