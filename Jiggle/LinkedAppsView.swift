import SwiftUI
import UniformTypeIdentifiers

struct LinkedAppsView: View {
    @EnvironmentObject private var watcher: AppWatcher

    var body: some View {
        Form {
            Section {
                Toggle("Auto: start when a linked app is active, stop when none is", isOn: $watcher.autoEnabled)
                Picker("Active while a linked app", selection: $watcher.rule) {
                    Text("Is running").tag(LinkedRule.running)
                    Text("Is frontmost").tag(LinkedRule.frontmost)
                }
            }
            Section {
                if watcher.linkedApps.isEmpty {
                    Text("No linked apps yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($watcher.linkedApps) { $app in
                    LinkedAppRow(app: $app)
                }
                addMenu
            } header: {
                Text("Linked apps")
            } footer: {
                Text("When several linked apps are running, the strongest mode override wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var addMenu: some View {
        Menu {
            ForEach(watcher.addableApps) { app in
                Button(app.name) { watcher.link(app) }
            }
            if !watcher.addableApps.isEmpty { Divider() }
            Button("Choose from Applications…", action: chooseFromApplications)
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .fixedSize()
    }

    private func chooseFromApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Link"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            watcher.link(RunningApp(bundleID: bundleID, name: name))
        }
    }
}

private struct LinkedAppRow: View {
    @EnvironmentObject private var watcher: AppWatcher
    @Binding var app: LinkedApp

    var body: some View {
        HStack {
            if let icon = watcher.icon(for: app.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
            if watcher.isRunning(app) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.green)
                    .help("Running")
            }
            Spacer()
            Picker("Mode", selection: $app.modeOverride) {
                Text("Default").tag(Mode?.none)
                ForEach(Mode.allCases) { Text($0.title).tag(Mode?.some($0)) }
            }
            .labelsHidden()
            .frame(width: 140)
            Button {
                watcher.unlink(bundleID: app.bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Unlink \(app.name)")
        }
    }
}
