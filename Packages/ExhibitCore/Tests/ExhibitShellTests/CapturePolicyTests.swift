import CoreGraphics
import ExhibitCore
import ExhibitShell
import Foundation
import Testing

@Suite struct CapturePolicyTests {
    @Test func defaultsRefusePasswordManagersAndKeychainAccess() {
        let policy = CapturePolicy()
        let refused = [
            CaptureSubject(bundleIdentifier: "com.apple.keychainaccess", appName: "Keychain Access"),
            CaptureSubject(bundleIdentifier: "com.1password.1password"),
            CaptureSubject(bundleIdentifier: "com.bitwarden.desktop", appName: "Bitwarden"),
            CaptureSubject(appName: "Dashlane"),
            CaptureSubject(appName: "LastPass"),
            CaptureSubject(bundleIdentifier: "org.keepassxc.keepassxc"),
            CaptureSubject(bundleIdentifier: "com.apple.Passwords", appName: "Passwords")
        ]
        for subject in refused {
            #expect(policy.decision(for: subject) != .allow, "\(subject)")
        }
        #expect(policy.decision(for: CaptureSubject(bundleIdentifier: "com.apple.Safari", appName: "Safari")) == .allow)
        #expect(policy.decision(for: CaptureSubject()) == .allow)
        #expect(policy.agentAutoBlur)
        #expect(policy.autoBlurKinds == [.email, .key, .card, .phone])
    }

    @Test func matchesByBundleIdentifierThenNameIgnoringCase() {
        let entry = NeverCaptureApp(name: "Vault", bundleIdentifier: "com.example.vault")
        #expect(entry.matches(CaptureSubject(bundleIdentifier: "COM.example.Vault")))
        // A renamed app is still caught by its identifier, and an unknown identifier falls back to the name.
        #expect(entry.matches(CaptureSubject(bundleIdentifier: "com.example.vault", appName: "Vault Pro")))
        #expect(entry.matches(CaptureSubject(bundleIdentifier: "com.example.vault2", appName: " vault ")))
        #expect(entry.matches(CaptureSubject(appName: "VAULT")))
        #expect(!entry.matches(CaptureSubject(bundleIdentifier: "com.example.other", appName: "Vaults")))
        #expect(!NeverCaptureApp(name: "").matches(CaptureSubject(appName: "")))
    }

    @Test func refusalReasonNamesTheApp() {
        let decision = CapturePolicy().decision(for: CaptureSubject(bundleIdentifier: "com.apple.keychainaccess",
                                                                    appName: "Keychain Access"))
        #expect(decision == .blackOut(reason: "Keychain Access is on the never-capture list"))
    }

    @Test func addSkipsDuplicatesAndRemoveDrops() {
        var policy = CapturePolicy(neverCapture: [])
        let app = NeverCaptureApp(name: "Vault", bundleIdentifier: "com.example.vault")
        policy.add(app)
        policy.add(NeverCaptureApp(name: "vault"))
        #expect(policy.neverCapture == [app])
        policy.remove(app)
        #expect(policy.neverCapture.isEmpty)
        #expect(policy.decision(for: CaptureSubject(appName: "Vault")) == .allow)
    }

    // MARK: The file

    func temporaryFile() -> CapturePolicyFile {
        CapturePolicyFile(supportDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ExhibitPolicyTests-\(UUID().uuidString)"))
    }

    @Test func missingFileIsTheDefaults() {
        let loaded = temporaryFile().load()
        #expect(loaded.policy == CapturePolicy())
        #expect(loaded.problem == nil)
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let file = temporaryFile()
        var policy = CapturePolicy(agentAutoBlur: false, autoBlurKinds: [.email])
        policy.add(NeverCaptureApp(name: "Vault", bundleIdentifier: "com.example.vault"))
        try file.save(policy)
        #expect(file.load() == CapturePolicyFile.Loaded(policy: policy))
        let text = try String(contentsOf: file.url, encoding: .utf8)
        #expect(text.contains("\"formatVersion\" : 1"))
        #expect(text.contains("\"agentAutoBlur\""))
    }

    @Test func missingFieldsTakeDefaultsAndEmptyListStaysEmpty() throws {
        let partial = try CapturePolicyFile.decode(Data(#"{"formatVersion": 1}"#.utf8))
        #expect(partial == CapturePolicy())
        let empty = try CapturePolicyFile.decode(Data(#"{"formatVersion": 1, "neverCapture": []}"#.utf8))
        #expect(empty.neverCapture.isEmpty)
        #expect(empty.agentAutoBlur)
        let off = try CapturePolicyFile.decode(Data(#"{"formatVersion":1,"agentAutoBlur":{"enabled":false}}"#.utf8))
        #expect(!off.agentAutoBlur)
        #expect(off.autoBlurKinds == CapturePolicy.defaultAutoBlurKinds)
    }

    @Test func damagedOrNewerFilesFallBackToTheDefaults() throws {
        for contents in ["not json", #"{"formatVersion": 2, "neverCapture": []}"#, #"{"neverCapture": []}"#] {
            let file = temporaryFile()
            try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file.url)
            let loaded = file.load()
            #expect(loaded.policy == CapturePolicy(), "\(contents)")
            #expect(loaded.problem != nil, "\(contents)")
        }
    }

    @Test func supportDirectoryOverride() {
        let url = ExhibitPaths.supportDirectory(environment: [ExhibitPaths.supportOverrideVariable: "/tmp/x"])
        #expect(url.path == "/tmp/x")
        #expect(ExhibitPaths.supportDirectory(environment: [:]).path.hasSuffix("Application Support/Exhibit A"))
        #expect(ExhibitPaths.capturesDirectory(in: url).path == "/tmp/x/Captures")
    }
}
