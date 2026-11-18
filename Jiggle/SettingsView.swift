import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var engine: JiggleEngine
    @AppStorage(SettingsKey.intervalSeconds) private var interval = SettingsDefault.intervalSeconds
    @AppStorage(SettingsKey.jitterEnabled) private var jitter = SettingsDefault.jitterEnabled
    @AppStorage(SettingsKey.smartPause) private var smartPause = SettingsDefault.smartPause
    @AppStorage(SettingsKey.jiggleDistance) private var distance = SettingsDefault.jiggleDistance

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $engine.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                Text(engine.mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = engine.warning {
                    HStack {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") { PermissionExplainer.show() }
                    }
                }
            }
            Section {
                LabeledContent("Interval") {
                    HStack {
                        Slider(value: intervalBinding, in: intervalRange, step: 5)
                        Text(Self.format(seconds: interval))
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Toggle("Random jitter (±20%)", isOn: $jitter)
                Toggle("Smart pause: skip while I'm using the mouse or keyboard", isOn: $smartPause)
                Stepper(value: $distance, in: SettingsDefault.jiggleDistanceRange) {
                    Text("Jiggle distance: \(distance) px")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: interval) { _ in engine.intervalDidChange() }
    }

    private var intervalRange: ClosedRange<Double> {
        Double(SettingsDefault.intervalRange.lowerBound)...Double(SettingsDefault.intervalRange.upperBound)
    }

    private var intervalBinding: Binding<Double> {
        Binding(get: { Double(interval) }, set: { interval = Int($0) })
    }

    static func format(seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        let rest = seconds % 60
        return rest == 0 ? "\(seconds / 60) min" : "\(seconds / 60) m \(rest) s"
    }
}
