import SwiftUI

struct ClickSettingsView: View {
    @EnvironmentObject private var capture: ClickPointCapture
    @AppStorage(SettingsKey.clickEveryNTicks) private var everyN = SettingsDefault.clickEveryNTicks
    @AppStorage(SettingsKey.clickButton) private var button = SettingsDefault.clickButton
    @AppStorage(SettingsKey.clickTarget) private var target = SettingsDefault.clickTarget
    @AppStorage(SettingsKey.clickPoint) private var clickPoint: String?
    @AppStorage(SettingsKey.clickBlocklist) private var blocklistText = ListCoding.encode(SettingsDefault.clickBlocklist)
    @AppStorage(SettingsKey.clickOnlyWhenLinkedFrontmost) private var onlyWhenLinkedFrontmost =
        SettingsDefault.clickOnlyWhenLinkedFrontmost
    @State private var newBundleID = ""

    var body: some View {
        Form {
            Section {
                Stepper(value: $everyN, in: SettingsDefault.clickEveryNTicksRange) {
                    Text(everyN == 1 ? "Click every tick" : "Click every \(everyN) ticks")
                }
                Picker("Button", selection: $button) {
                    Text("Left").tag(ClickButton.left)
                    Text("Right").tag(ClickButton.right)
                }
                Picker("Click at", selection: $target) {
                    Text("Pinned point").tag(ClickTarget.pinnedPoint)
                    Text("Current cursor position").tag(ClickTarget.currentPosition)
                }
                if target == .pinnedPoint {
                    LabeledContent("Pinned point") {
                        HStack {
                            Text(pointDescription)
                                .monospacedDigit()
                                .foregroundStyle(clickPoint == nil ? .secondary : .primary)
                            Button(capture.countdown.map { "Capturing in \($0)…" } ?? "Set…") {
                                capture.capturePoint()
                            }
                            .disabled(capture.countdown != nil)
                        }
                    }
                    Text("Move the cursor to empty space during the 3-second countdown. Clicks are real.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Only click when a linked app is frontmost", isOn: $onlyWhenLinkedFrontmost)
            }
            Section("Never click when the frontmost app is") {
                ForEach(blocklist, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        Button {
                            blocklistText = ListCoding.encode(blocklist.filter { $0 != id })
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from blocklist")
                    }
                }
                HStack {
                    TextField("Bundle ID", text: $newBundleID, prompt: Text("com.example.app"))
                        .onSubmit(addBundleID)
                    Button("Add", action: addBundleID)
                        .disabled(trimmedNewID.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var blocklist: [String] { ListCoding.decode(blocklistText) }
    private var trimmedNewID: String { newBundleID.trimmingCharacters(in: .whitespaces) }

    private var pointDescription: String {
        guard let point = PointCoding.decode(clickPoint) else { return "Not set" }
        return "x \(Int(point.x)), y \(Int(point.y))"
    }

    private func addBundleID() {
        let id = trimmedNewID
        guard !id.isEmpty, !blocklist.contains(id) else { return }
        blocklistText = ListCoding.encode(blocklist + [id])
        newBundleID = ""
    }
}
