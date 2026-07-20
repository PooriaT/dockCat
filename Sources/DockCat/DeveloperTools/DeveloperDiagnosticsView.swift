import AppKit
import DockCatCore
import SwiftUI

struct DeveloperDiagnosticsView: View {
    @ObservedObject var state: AppState
    let recorder: DockCatDiagnosticEventRecorder
    @Binding var status: String?

    var body: some View {
        Form {
            NotificationSimulatorView(state: state)
            Section("Diagnostic Summary") {
                Text("Diagnostic summaries include runtime, queue, source, placement, accessibility, and event metadata. They do not include notification title, body, source text, URLs, AX text, OSLog archives, analytics, or automatic uploads.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Copy Diagnostic Summary") { copyDiagnostics() }
                    Button("Save Diagnostic Summary…") { saveDiagnostics() }
                    Button("Clear Diagnostic History") { clearHistory() }
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func builder() -> DockCatDiagnosticSnapshotBuilder { DockCatDiagnosticSnapshotBuilder(state: state, recorder: recorder) }
    private func copyDiagnostics() { Task { @MainActor in do { let json = try await builder().encodedSnapshot(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(json, forType: .string); status = "Diagnostic summary copied." } catch { status = "Could not copy diagnostics: sanitized export failed." } } }
    private func saveDiagnostics() { Task { @MainActor in do { let json = try await builder().encodedSnapshot(); let panel = NSSavePanel(); panel.nameFieldStringValue = "DockCat-Diagnostics-\(Self.timestamp()).json"; panel.allowedContentTypes = [.json]; if panel.runModal() == .OK, let url = panel.url { try json.write(to: url, atomically: true, encoding: .utf8); status = "Diagnostic summary saved." } else { status = "Save cancelled." } } catch { status = "Could not save diagnostics: sanitized export failed." } } }
    private func clearHistory() { Task { await recorder.clear(); await MainActor.run { status = "Diagnostic history cleared." } } }
    private static func timestamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }
}
