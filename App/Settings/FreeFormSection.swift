import AppKit
import ExhibitInterpret
import PanelKit
import SwiftUI

/// Instructions in your own words: which local model, if any, reads what the built-in commands can't. The
/// models found on this Mac are offered in one menu with the recommended one marked; never chosen means that one
/// is used. One status line says what is in use, or what is wrong and how to fix it.
struct FreeFormSection: View {
    @Bindable var model: FreeFormSettings

    /// A menu item. `unset` stands for "never chosen, nothing found", which is not a choice.
    enum Pick: Hashable {
        case installed(ModelServer.Kind, url: String, model: String)
        case none
        case other
        case unset
    }

    var body: some View {
        Section {
            Text("Dictation and typed instructions already work with no setup for commands like \u{201C}blur the "
                 + "emails\u{201D}. A local model adds looser requests, like \u{201C}hide anything that identifies "
                 + "the customer\u{201D}.")
                .fixedSize(horizontal: false, vertical: true)
            Picker(selection: pick) {
                menuItems
            } label: {
                Text("Model")
                Text("The models found on this Mac, or none.")
            }
            if model.settings.effectiveChoice == .other { otherFields }
            statusRow
        } header: {
            Text("Instructions in your own words")
        } footer: {
            Label("Exhibit A looks for a model server only on this Mac (127.0.0.1). The model gets your words and the "
                  + "text read from the capture, with secrets masked; never the image. Nothing leaves this Mac. Expect "
                  + "several seconds per instruction on a new screen: a 27B model took 5 to 8 s on an M4 Pro.",
                  systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { model.refresh() }
    }

    // MARK: - The menu

    @ViewBuilder private var menuItems: some View {
        let servers = model.discovery?.servers ?? []
        let recommended = model.discovery?.defaultChoice
        ForEach(servers, id: \.url) { server in
            Section(server.name) {
                ForEach(server.models, id: \.self) { name in
                    let marked = recommended?.server.url == server.url && recommended?.model == name
                    Text(marked ? "\(name) (recommended)" : name)
                        .tag(Pick.installed(server.kind, url: server.url.absoluteString, model: name))
                }
            }
        }
        if case let .installed(kind, url, name)? = model.settings.effectiveChoice,
           !servers.contains(where: { $0.url.absoluteString == url && $0.models.contains(name) }) {
            Text("\(name) (not found)").tag(Pick.installed(kind, url: url, model: name))
        }
        if model.settings.effectiveChoice == nil, recommended == nil {
            Text(model.discovery == nil ? "Looking…" : "No model found").tag(Pick.unset)
        }
        Divider()
        Text("None: built-in commands only").tag(Pick.none)
        Text("Other…").tag(Pick.other)
    }

    /// The menu's selection: the choice, or the default in use when never chosen. Picking writes a choice, so
    /// from then on it is never overridden.
    private var pick: Binding<Pick> {
        Binding {
            switch model.settings.effectiveChoice {
            case let .installed(kind, url, name)?: return .installed(kind, url: url, model: name)
            case .none?: return .none
            case .other?: return .other
            case nil:
                guard let picked = model.discovery?.defaultChoice else { return .unset }
                return .installed(picked.server.kind, url: picked.server.url.absoluteString, model: picked.model)
            }
        } set: { pick in
            switch pick {
            case let .installed(kind, url, name): model.settings.choice = .installed(server: kind, url: url, model: name)
            case .none: model.settings.choice = ModelSettings.Choice.none
            case .other: model.settings.choice = .other
            case .unset: break
            }
        }
    }

    // MARK: - Other

    @ViewBuilder private var otherFields: some View {
        LabeledContent {
            TextField("", text: $model.settings.endpoint, prompt: Text(ModelSettings.defaultEndpoint))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        } label: {
            Text("Endpoint")
            Text("On this Mac only: localhost, 127.0.0.1 or ::1. A URL with /v1 is OpenAI-compatible.")
        }
        LabeledContent {
            TextField("", text: $model.settings.model, prompt: Text(RecommendedModels.preferred))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        } label: {
            Text("Model name")
            Text("The model's name on the server.")
        }
        Picker(selection: $model.settings.api) {
            ForEach(ModelSettings.APIChoice.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Text("API")
            Text("Ollama's own, or OpenAI-compatible (LM Studio, llama.cpp). Automatic reads the URL.")
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        let status = model.status
        return LabeledContent {
            HStack(spacing: 6) {
                if model.isDiscovering { ProgressView().controlSize(.small) }
                Button("Check Again") { model.refresh() }
                    .disabled(model.isDiscovering)
                Button(model.isTesting ? "Testing…" : "Test", action: model.test)
                    .disabled(model.isTesting || model.currentInterpreter() == nil || status.isProblem)
            }
        } label: {
            Text("\(Image(systemName: Self.symbol(for: status))) \(status.message)")
                .foregroundStyle(status.isProblem ? Color.orange : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let description = model.modelDescription {
                Text(description).fixedSize(horizontal: false, vertical: true)
            }
            if let command = status.command {
                HStack(spacing: 6) {
                    Text(command).font(.system(size: 12).monospaced()).textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy the command, then paste it in Terminal")
                }
            }
            if let probe = model.probe {
                let symbol = probe.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                Text("\(Image(systemName: symbol)) \(probe.message)")
                    .foregroundStyle(probe.isReachable ? Color.green : Color.orange)
            }
        }
    }

    private static func symbol(for status: ModelStatus) -> String {
        switch status {
        case .checking: "magnifyingglass"
        case .using, .usingOther: "checkmark.circle.fill"
        case .builtInOnly: "text.bubble"
        default: "exclamationmark.triangle.fill"
        }
    }
}
