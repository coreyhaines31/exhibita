import AppKit
import ExhibitEditor
import ExhibitShell
import SwiftUI

/// Settings, Shortcuts: every editor key that can change, each with a recorder and Reset, and Reset All.
struct ShortcutsSection: View {
    let model: AppModel

    var body: some View {
        Section {
            ForEach(model.shortcutRows) { row in
                LabeledContent {
                    HStack(spacing: 8) {
                        if row.isCustom {
                            Button("Reset") { model.resetShortcut(row.command) }
                                .controlSize(.small)
                                .accessibilityLabel("Reset \(row.title)")
                        }
                        ShortcutRecorder(title: row.title, key: row.key) { key, modifiers in
                            model.recordShortcut(key, modifiers: modifiers, for: row.command)
                        }
                    }
                } label: {
                    Text(row.title)
                    if let message = row.message {
                        Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(message)")
                            .foregroundStyle(.orange)
                    } else {
                        Text(row.detail)
                    }
                }
            }
        } header: {
            HStack {
                Text("Editor shortcuts")
                Spacer()
                Button("Reset All", action: model.resetAllShortcuts)
                    .controlSize(.small)
                    .disabled(model.keymap.isStandard)
            }
        } footer: {
            Text("Click a key, then press the new one, with or without ⌘ ⌥ ⌃ ⇧. Esc stops recording. "
                 + "Esc, ⌫, ⌘Z and ⇧⌘Z always close, delete, undo and redo.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A key field for one editor command. Click it and the next key pressed is offered to the command; Esc stops
/// without changing anything. `KeyboardShortcuts.Recorder` is for global hotkeys and refuses a bare letter, so
/// this reads the key itself, from a local event monitor that lives only while recording.
struct ShortcutRecorder: View {
    let title: String
    let key: String
    /// Offers a key; returns whether it was taken. A refusal is shown on the row by the model.
    let record: (EditorKey, KeyModifiers) -> Bool

    @State private var monitor = KeyMonitor()

    var body: some View {
        Button {
            monitor.isRecording ? monitor.stop() : monitor.start { key, modifiers in
                _ = record(key, modifiers)
            }
        } label: {
            Text(monitor.isRecording ? "Press a key" : key)
                .font(.system(size: 12, weight: monitor.isRecording ? .regular : .semibold).monospacedDigit())
                .foregroundStyle(monitor.isRecording ? .secondary : .primary)
                .frame(minWidth: 96)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(monitor.isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: monitor.isRecording ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) shortcut, \(key)")
        .accessibilityHint(monitor.isRecording ? "Press the new key, or Esc to stop" : "Records a new key")
        .onDisappear { monitor.stop() }
    }
}

/// Takes the next key press in the app while recording, so it never reaches the window or another control.
@MainActor
@Observable
final class KeyMonitor {
    private(set) var isRecording = false
    @ObservationIgnored private var token: Any?

    func start(_ handle: @escaping (EditorKey, KeyModifiers) -> Void) {
        stop()
        isRecording = true
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.take(event, handle)
            }
            return nil
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        isRecording = false
    }

    private func take(_ event: NSEvent, _ handle: (EditorKey, KeyModifiers) -> Void) {
        let modifiers = KeyModifiers(event)
        defer { stop() }
        guard let key = EditorKey(event), !(key == .escape && modifiers.isEmpty) else { return }
        handle(key, modifiers)
    }
}
