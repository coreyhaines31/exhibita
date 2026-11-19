import AppKit
import ExhibitShell
import UniformTypeIdentifiers

/// The apps Settings offers for the never-capture list.
@MainActor
enum AppPicker {
    static func runningApps() -> [NeverCaptureApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> NeverCaptureApp? in
            guard app.activationPolicy == .regular, app.processIdentifier != ownPID,
                  let name = app.localizedName else { return nil }
            return NeverCaptureApp(name: name, bundleIdentifier: app.bundleIdentifier)
        }
        return Array(Set(apps)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// An open panel for one application bundle. Shown only from the Settings button the person clicked.
    static func choose(then add: @escaping (NeverCaptureApp) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Never Capture"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        add(NeverCaptureApp(name: name, bundleIdentifier: bundle?.bundleIdentifier))
    }
}
