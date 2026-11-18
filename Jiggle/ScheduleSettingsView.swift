import SwiftUI

struct ScheduleSettingsView: View {
    @AppStorage(SettingsKey.scheduleEnabled) private var enabled = SettingsDefault.scheduleEnabled
    @AppStorage(SettingsKey.scheduleDays) private var daysText = SettingsDefault.scheduleDays
    @AppStorage(SettingsKey.scheduleStart) private var start = SettingsDefault.scheduleStart
    @AppStorage(SettingsKey.scheduleEnd) private var end = SettingsDefault.scheduleEnd

    /// Monday first.
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section {
                Toggle("Keep the Mac active on a schedule", isOn: $enabled)
            }
            Section {
                LabeledContent("Days") {
                    HStack(spacing: 4) {
                        ForEach(Self.weekdayOrder, id: \.self) { day in
                            Toggle(Calendar.current.veryShortWeekdaySymbols[day - 1], isOn: dayBinding(day))
                                .toggleStyle(.button)
                        }
                    }
                }
                DatePicker("From", selection: timeBinding($start), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: timeBinding($end), displayedComponents: .hourAndMinute)
            } footer: {
                Text("""
                    Starts when the window opens and stops when it closes. A manual Stop holds until the next \
                    window. If "To" is earlier than "From", the window runs overnight.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding {
            DayCoding.decode(daysText).contains(day)
        } set: { isOn in
            var days = DayCoding.decode(daysText)
            if isOn { days.insert(day) } else { days.remove(day) }
            daysText = DayCoding.encode(days)
        }
    }

    /// Minutes after midnight ⇄ a `Date` today, for `DatePicker`.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()
            ) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
