import ExhibitShell
import SwiftUI

/// What Settings' buttons do. The app supplies these; renders pass no-ops.
struct SettingsActions {
    var openKeyboardSettings: () -> Void = {}
    var openScreenRecordingSettings: () -> Void = {}
    var checkPermissionAgain: () -> Void = {}
    var revealCaptures: () -> Void = {}
    var purgeAll: () -> Void = {}
}

/// Sections Settings can be opened at.
enum SettingsAnchor: String {
    case hotkeys
    case shortcuts
}

/// Where the open Settings window should scroll. The window sets it; the view scrolls when it changes.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var anchor: SettingsAnchor?
    /// Counts requests, so asking for the same section twice scrolls twice.
    private(set) var requests = 0

    func go(to anchor: SettingsAnchor) {
        self.anchor = anchor
        requests += 1
    }
}

/// One pane, grouped like System Settings: hotkeys, editor shortcuts, permission, privacy, history, free-form
/// instructions, command line, general.
struct SettingsView: View {
    let model: AppModel
    let actions: SettingsActions
    /// Renders draw a plain label where the live key recorder would be; it is an AppKit control.
    var drawsRecorders = true
    /// The never-capture list and auto-blur. Nil leaves the section out.
    var policy: CapturePolicyModel?
    var policyActions = PolicyActions()
    var freeForm = FreeFormSettings.shared
    var updates = UpdateSettings()
    var commandLine = CommandLineTool.app
    var navigation = SettingsNavigation()
    /// True sizes the view to all of its content, for renders. The window passes false: it caps its height to
    /// the screen and the form scrolls inside it.
    var fitsContent = true

    static let width: CGFloat = 540
    static let preferredWindowHeight: CGFloat = 720
    static let minimumWindowHeight: CGFloat = 360

    /// The window's content height on a screen whose visible area is `screenHeight` tall: the preferred height,
    /// or less so the title bar and a margin still fit.
    static func windowHeight(onScreenOfHeight screenHeight: CGFloat?) -> CGFloat {
        guard let screenHeight else { return preferredWindowHeight }
        return max(minimumWindowHeight, min(preferredWindowHeight, screenHeight - 80))
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onChange(of: navigation.requests) { scroll(proxy) }
                .onAppear { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let anchor = navigation.anchor else { return }
        withAnimation { proxy.scrollTo(anchor, anchor: .top) }
    }

    private var form: some View {
        Form {
            HotkeysSection(model: model, actions: actions, drawsRecorders: drawsRecorders)
                .id(SettingsAnchor.hotkeys)
            ShortcutsSection(model: model)
                .id(SettingsAnchor.shortcuts)
            PermissionSection(state: model.permission, actions: actions)
            if let policy { NeverCaptureSection(policy: policy, actions: policyActions) }
            HistorySection(model: model, actions: actions)
            FreeFormSection(model: freeForm)
            CommandLineSection(tool: commandLine)
            GeneralSection(model: model, updates: updates)
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: fitsContent)
    }
}
