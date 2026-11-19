import ExhibitShell
import ExhibitStore
import KeyboardShortcuts
import PanelKit
import SwiftUI

/// The two hotkeys, each remappable, and the state of macOS's own screenshot shortcuts.
struct HotkeysSection: View {
    let model: AppModel
    let actions: SettingsActions
    let drawsRecorders: Bool

    var body: some View {
        Section {
            ForEach(HotkeyAction.allCases) { action in
                LabeledContent {
                    HStack(spacing: 8) {
                        if model.bindings.isCustom(action) {
                            Button("Reset") { model.resetHotkey(action) }
                                .controlSize(.small)
                        }
                        recorder(for: action)
                    }
                } label: {
                    Text(action.title)
                    if let message = model.message(for: action) {
                        Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(message)")
                            .foregroundStyle(.orange)
                    } else {
                        Text(action.detail)
                    }
                }
            }
            LabeledContent {
                if model.bindings.takenOver {
                    StatusLight(.go, "Turned off")
                } else {
                    Button("Open Keyboard Settings…", action: actions.openKeyboardSettings)
                }
            } label: {
                Text("macOS screenshot shortcuts")
                Text(model.bindings.takenOver
                     ? "Exhibit A uses ⇧⌘4 and ⌃⇧⌘4 unless you pick other keys."
                     : "To give ⇧⌘4 to Exhibit A, turn off the shortcuts under Keyboard Shortcuts, Screenshots.")
            }
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("After either hotkey: drag for a region, Space to pick a window, ↩ for the whole screen, Esc to cancel.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func recorder(for action: HotkeyAction) -> some View {
        if drawsRecorders {
            KeyboardShortcuts.Recorder(for: action.shortcutName) { shortcut in
                model.record(shortcut.map(KeyCombo.init), for: action)
            }
        } else {
            Text(model.bindings.combo(for: action).display)
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(minWidth: 130)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

/// Screen Recording, the one permission capture needs.
struct PermissionSection: View {
    let state: ScreenRecordingState
    let actions: SettingsActions

    var body: some View {
        Section("Permission") {
            LabeledContent {
                if state == .granted {
                    StatusLight(.go, "Allowed")
                } else {
                    HStack(spacing: 8) {
                        Button("Check Again", action: actions.checkPermissionAgain)
                        Button("Open Privacy & Security…", action: actions.openScreenRecordingSettings)
                    }
                }
            } label: {
                Text("Screen Recording")
                Text(state == .granted ? "Needed to capture. Microphone is asked for only when you first dictate."
                     : state.message)
            }
        }
    }
}

/// How long captures are kept, where, and deleting them all.
struct HistorySection: View {
    let model: AppModel
    let actions: SettingsActions
    @State private var confirmingPurge = false

    var body: some View {
        Section {
            Picker(selection: Binding(get: { model.retention }, set: { model.setRetention($0) })) {
                ForEach(RetentionPolicy.choices, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("Keep captures")
                Text(model.retention.discardsOnExport
                     ? "Deleted once exported. Captures never exported go after \(RetentionPolicy.fallbackDays) days."
                     : "Originals stay so marks remain editable, then are deleted.")
            }
            LabeledContent {
                Button("Show in Finder", action: actions.revealCaptures)
            } label: {
                Text("Location")
                Text("~/Library/Application Support/Exhibit A/Captures, outside Time Machine")
            }
            LabeledContent {
                Button("Delete All…", role: .destructive) { confirmingPurge = true }
                    .disabled(model.items.isEmpty)
            } label: {
                Text("Delete all captures")
                Text(model.items.isEmpty ? "History is empty." : "\(model.summary). Deleted as files, not undoable.")
            }
        } header: {
            Text("History")
        }
        .confirmationDialog("Delete all captures?", isPresented: $confirmingPurge) {
            Button("Delete All", role: .destructive, action: actions.purgeAll)
        } message: {
            Text("Every original and its marks are deleted from this Mac. This can't be undone.")
        }
    }
}

/// Launch at login, and what Exhibit A does not do.
struct GeneralSection: View {
    let model: AppModel

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                Text("Launch at login")
                Text("The hotkeys work only while Exhibit A is running.")
            }
        } header: {
            Text("General")
        } footer: {
            Label("Exhibit A sends nothing off this Mac: no telemetry, no account. Captures stay here.",
                  systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
