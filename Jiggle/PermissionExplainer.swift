import SwiftUI

enum PermissionExplainer {
    static let windowID = "accessibility"

    @MainActor
    static func show() {
        WindowPresenter.show(id: windowID, title: "Accessibility Permission") {
            PermissionExplainerView()
        }
    }
}

struct PermissionExplainerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Jiggle needs Accessibility permission", systemImage: "hand.raised")
                .font(.headline)
            Text("""
                Jiggle and Jiggle + Click move the cursor with synthetic mouse events, which macOS only allows \
                for apps you approve in System Settings → Privacy & Security → Accessibility.
                """)
            Text("Until then Jiggle runs in Zen mode. Once you turn Jiggle on in that list, it switches over by itself on the next tick.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
                Spacer()
                Button("Not Now") { WindowPresenter.close(id: PermissionExplainer.windowID) }
                    .keyboardShortcut(.cancelAction)
                Button("Grant Access…") {
                    Permissions.requestAccessibility()
                    WindowPresenter.close(id: PermissionExplainer.windowID)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
