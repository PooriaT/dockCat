import DockCatCore
import SwiftUI

struct NotificationSimulatorView: View {
    @ObservedObject var state: AppState
    @State private var source = "Developer"
    @State private var title = "Build complete"
    @State private var message = "The project finished successfully."
    @State private var persistent = false
    @State private var duration = 5.0
    @State private var action = ""
    @State private var count = 1

    var body: some View {
        Form {
            TextField("Source", text: $source); TextField("Title", text: $title); TextField("Message", text: $message, axis: .vertical)
            Toggle("Persistent", isOn: $persistent)
            if !persistent { Stepper("Duration: \(duration, specifier: "%.0f") seconds", value: $duration, in: 1...60) }
            TextField("Optional HTTPS URL", text: $action)
            Stepper("Events: \(count)", value: $count, in: 1...20)
            HStack {
                Button("Send") { send(count: count) }.buttonStyle(.borderedProminent)
                Button("Short") { title = "Done"; message = "Task complete."; persistent = false; send(count: 1) }
                Button("Long") { title = "Long message"; message = String(repeating: "DockCat can carry longer notification text. ", count: 4); persistent = false; send(count: 1) }
                Button("Persistent") { persistent = true; title = "Action needed"; send(count: 1) }
                Button("Queue 3") { send(count: 3) }
            }
        }
    }
    private func send(count: Int) {
        for index in 0..<count {
            state.submit(.init(sourceName: source.isEmpty ? "Developer" : source,
                               title: count > 1 ? "\(title) #\(index + 1)" : title,
                               message: message,
                               presentation: persistent ? .persistent : .transient(duration: duration),
                               actionURL: URL(string: action).flatMap { $0.scheme == "https" ? $0 : nil }))
        }
    }
}
