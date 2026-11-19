import ExhibitShell
import SwiftUI

/// What the never-capture section asks the app for. Renders pass fixed lists and no-ops.
struct PolicyActions {
    /// Regular apps running now, offered in the Add menu.
    var runningApps: () -> [NeverCaptureApp] = { [] }
    /// Lets the person pick an app bundle; the app adds it.
    var chooseApp: () -> Void = {}
}

/// Agents and the never-capture list: apps whose windows are never captured, and auto-blur for agents.
struct NeverCaptureSection: View {
    let policy: CapturePolicyModel
    let actions: PolicyActions

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { policy.policy.agentAutoBlur }, set: { policy.setAgentAutoBlur($0) })) {
                Text("Blur secrets before agents see them")
                Text("Emails, keys, card and phone numbers found in a capture an agent asks for. The original stays "
                     + "in history.")
            }
            ForEach(policy.policy.neverCapture, id: \.self) { app in
                LabeledContent {
                    Button("Remove") { policy.remove(app) }
                        .controlSize(.small)
                } label: {
                    Text(app.name)
                    Text(app.bundleIdentifier ?? "Matched by name")
                }
            }
            LabeledContent {
                HStack(spacing: 8) {
                    Button("Restore Defaults") { policy.restoreDefaults() }
                        .disabled(policy.policy == CapturePolicy())
                    Menu("Add App") {
                        let running = actions.runningApps().filter { app in
                            policy.policy.entry(for: CaptureSubject(bundleIdentifier: app.bundleIdentifier,
                                                                    appName: app.name)) == nil
                        }
                        ForEach(running, id: \.self) { app in
                            Button(app.name) { policy.add(app) }
                        }
                        if !running.isEmpty { Divider() }
                        Button("Choose App…", action: actions.chooseApp)
                    }
                    .fixedSize()
                }
            } label: {
                Text("Never capture")
                if let problem = policy.problem {
                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(problem)")
                        .foregroundStyle(.orange)
                } else {
                    Text("Refused for you and for agents. Inside a larger capture their windows are drawn black.")
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Agents capture through the exhibit command while Exhibit A runs. The menu bar icon flashes and "
                 + "the capture shows \u{201C}by agent\u{201D} in history.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
