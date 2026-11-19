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

/// One pane, grouped like System Settings: hotkeys, permission, privacy, history, free-form instructions,
/// general.
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

    static let width: CGFloat = 540

    var body: some View {
        Form {
            HotkeysSection(model: model, actions: actions, drawsRecorders: drawsRecorders)
            PermissionSection(state: model.permission, actions: actions)
            if let policy { NeverCaptureSection(policy: policy, actions: policyActions) }
            HistorySection(model: model, actions: actions)
            FreeFormSection(model: freeForm)
            GeneralSection(model: model, updates: updates)
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
