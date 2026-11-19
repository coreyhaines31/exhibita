import ExhibitInterpret
import PanelKit
import SwiftUI

/// Free-form instructions: an optional local model for what the built-in grammar can't read. Off by default.
struct FreeFormSection: View {
    @Bindable var model: FreeFormSettings

    var body: some View {
        Section {
            Toggle(isOn: $model.settings.enabled) {
                Text("Use a local model")
                Text("For instructions the built-in grammar can't read, like \u{201C}hide anything that identifies "
                     + "the customer\u{201D}. Commands like \u{201C}blur the emails\u{201D} never need one.")
            }
            LabeledContent {
                TextField("", text: $model.settings.endpoint, prompt: Text(ModelSettings.defaultEndpoint))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            } label: {
                Text("Endpoint")
                Text("On this Mac only: localhost, 127.0.0.1 or ::1. A URL with /v1 is OpenAI-compatible.")
            }
            LabeledContent {
                TextField("", text: $model.settings.model, prompt: Text("qwen3:8b"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            } label: {
                Text("Model")
                Text("The model's name on the server.")
            }
            Picker(selection: $model.settings.api) {
                ForEach(ModelSettings.APIChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("API")
                Text("Ollama's own, or OpenAI-compatible (LM Studio, llama.cpp). Automatic reads the URL.")
            }
            LabeledContent {
                Button(model.isTesting ? "Testing…" : "Test", action: model.test)
                    .disabled(model.isTesting || model.settings.model.trimmingCharacters(in: .whitespaces).isEmpty)
            } label: {
                Text("Check the model")
                if let probe = model.probe {
                    let symbol = probe.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    Text("\(Image(systemName: symbol)) \(probe.message)")
                        .foregroundStyle(probe.isReachable ? Color.green : Color.orange)
                } else {
                    Text("Sends one short request. The first can take a while if the model has to load.")
                }
            }
        } header: {
            Text("Free-form instructions")
        } footer: {
            Label("The model gets your words and the text read from the capture, with secrets masked; never the "
                  + "image. Nothing leaves this Mac. Expect several seconds per instruction on a new screen: a 27B "
                  + "model took 5 to 8 s on an M4 Pro. Smaller models should be faster; none were measured.",
                  systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
