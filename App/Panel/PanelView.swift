import ExhibitShell
import PanelKit
import SwiftUI

/// What the panel's buttons do. The app supplies these; renders pass no-ops.
struct PanelActions {
    var openSettings: () -> Void = {}
    /// Opens Settings scrolled to the hotkeys, from the hotkey tiles.
    var openHotkeySettings: () -> Void = {}
    var quit: () -> Void = {}
    var allowScreenRecording: () -> Void = {}
    var checkPermissionAgain: () -> Void = {}
    var openKeyboardSettings: () -> Void = {}
    /// Opens the capture in the editor.
    var open: (UUID) -> Void = { _ in }
    var copy: (UUID) -> Void = { _ in }
    var reveal: (UUID) -> Void = { _ in }
    var delete: (UUID) -> Void = { _ in }
    /// Where a row or one of its buttons was laid out, by name ("row <id>", "open <id>", "delete <id>"),
    /// in the panel's top-left coordinates. Read by the end-to-end tests to aim their clicks.
    var reportFrame: (String, CGRect) -> Void = { _, _ in }
}

/// What opens from the menu bar: the hotkeys on the fascia, then the permission, the empty state or history.
struct PanelView: View {
    let model: AppModel
    let actions: PanelActions

    var body: some View {
        Panel(accent: Brand.accent) {
            Fascia(nameplate: Brand.name, timestamp: showsSummary ? model.summary : nil,
                   label: "Screenshot markup", isLit: model.permission == .granted) {
                HotkeyTiles(bindings: model.bindings, actions: actions)
            }
            if let refusal = model.captureRefusal {
                RefusedCaptureNotice(message: refusal, openSettings: actions.openSettings,
                                     dismiss: model.clearCaptureRefusal)
            }
            switch model.content {
            case .permission(let state):
                PermissionNotice(state: state, actions: actions)
                if !model.items.isEmpty { history }
            case .empty:
                EmptyHistory(hint: model.emptyHint, offerTakeover: model.bindings.takeoverSuggestion == .offer,
                             openKeyboardSettings: actions.openKeyboardSettings)
            case .history:
                history
            }
        } footer: {
            Footer(appName: Brand.name, openSettings: actions.openSettings, quit: actions.quit)
        }
        .reportingFrame("panel", to: actions)
    }

    private var showsSummary: Bool {
        model.permission == .granted && !model.items.isEmpty
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("History", detail: "Newest first")
            if model.rows.count > Self.rowsWithoutScrolling {
                ScrollView { rows }
                    .frame(height: Self.scrollHeight)
            } else {
                rows
            }
        }
    }

    /// Up to this many rows sit in the panel as they are; more scroll in a fixed height.
    static let rowsWithoutScrolling = 5
    static let scrollHeight: CGFloat = 330

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.rows) { row in
                HistoryRowView(row: row, thumbnail: model.thumbnails[row.id], actions: actions) {
                    model.selected = model.selected == row.id ? nil : row.id
                }
            }
        }
        .padding(.bottom, 8)
    }
}

/// The two hotkeys as readouts on the fascia, each saying what it does. Clicking one opens Settings at Hotkeys,
/// where they are changed or swapped.
struct HotkeyTiles: View {
    let bindings: HotkeyBindings
    var actions = PanelActions()

    var body: some View {
        HStack(spacing: 8) {
            tile(.captureAndEdit, label: "Capture and edit", does: "Select, then mark it up")
            tile(.captureToClipboard, label: "To clipboard", does: "Select, then it's copied")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ action: HotkeyAction, label: String, does: String) -> some View {
        let combo = bindings.combo(for: action).display
        return Button(action: actions.openHotkeySettings) {
            ReadingTile(label, value: combo) {
                Text(does).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change or swap the hotkeys in Settings")
        .accessibilityLabel("\(action.title), \(combo). \(does). Opens Settings to change it.")
        .reportingFrame("hotkey \(action.rawValue)", to: actions)
    }
}

/// No captures yet: the hotkeys, and the offer to take over ⇧⌘4.
struct EmptyHistory: View {
    let hint: String
    let offerTakeover: Bool
    let openKeyboardSettings: () -> Void

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No captures yet").font(PanelFont.body(13, .semibold))
                Text(hint)
                    .font(PanelFont.body(12))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Then drag for a region, press Space to pick a window, or ↩ for the whole screen.")
                    .font(PanelFont.body(12))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            if offerTakeover {
                Notice("Want ⇧⌘4 instead?", message: "Turn off the screenshot shortcuts in Keyboard Shortcuts, "
                    + "Screenshots. Exhibit A moves to ⇧⌘4 and ⌃⇧⌘4 by itself.", status: .off) {
                    Button("Open Keyboard Settings…", action: openKeyboardSettings)
                }
            }
        }
    }
}

/// A window pick the never-capture list refused: which app, and where the list is.
struct RefusedCaptureNotice: View {
    let message: String
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        Notice("Not captured", message: message, status: .stop) {
            HStack(spacing: 8) {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.panelSecondary)
                Button("Dismiss", action: dismiss)
                    .buttonStyle(.panelSecondary)
            }
            .controlSize(.small)
        }
        .padding(.top, 10)
    }
}

/// Screen Recording is not on: the one permission, why, and the way to it.
struct PermissionNotice: View {
    let state: ScreenRecordingState
    let actions: PanelActions

    var body: some View {
        Notice(state.title, message: state.message, status: state == .denied ? .stop : .caution) {
            HStack(spacing: 8) {
                Button(state.buttonTitle, action: actions.allowScreenRecording)
                    .buttonStyle(.panelPrimary)
                Button("Check Again", action: actions.checkPermissionAgain)
                    .buttonStyle(.panelSecondary)
            }
            .controlSize(.small)
        }
        .padding(.top, 10)
    }
}
