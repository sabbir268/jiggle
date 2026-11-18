import SwiftUI

enum UntilPicker {
    static let windowID = "until"

    @MainActor
    static func show(engine: JiggleEngine) {
        WindowPresenter.show(id: windowID, title: "Start Until") {
            UntilPickerView { date in
                engine.start(until: date)
                WindowPresenter.close(id: windowID)
            } onCancel: {
                WindowPresenter.close(id: windowID)
            }
        }
    }
}

struct UntilPickerView: View {
    let onStart: (Date) -> Void
    let onCancel: () -> Void

    @State private var time = Date().addingTimeInterval(60 * 60)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep the Mac active until")
                .font(.headline)
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Text(resolvedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start") { onStart(resolved) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    private var resolved: Date {
        TickScheduling.nextOccurrence(of: time, after: Date())
    }

    private var resolvedDescription: String {
        let day = Calendar.current.isDateInToday(resolved) ? "today" : "tomorrow"
        return "Stops \(day) at \(resolved.formatted(date: .omitted, time: .shortened))."
    }
}
