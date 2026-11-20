@testable import ExhibitInterpret
import Foundation
import Testing

/// What Settings says each model is good at: measured facts for the models the eval ran, the server's own figures
/// for the rest, never made-up numbers.
struct ModelGuideTests {
    static let ollama = URL(string: "http://127.0.0.1:11434")!

    @Test func everyRecommendedModelHasMeasuredFacts() {
        for model in RecommendedModels.ordered {
            #expect(ModelGuide.measured[model] != nil, "\(model) is recommended but has no measured description")
        }
    }

    @Test func aMeasuredModelIsDescribedByWhatWasMeasured() {
        let text = ModelGuide.description(of: "qwen3.8:27b", installed: InstalledModel(parameterSize: "27.8B"))
        #expect(text.hasPrefix("Most accurate"))
        #expect(!text.contains("Not measured"))
    }

    @Test func anUnmeasuredModelSaysWhatTheServerReports() {
        let installed = InstalledModel(parameterSize: "8.0B", bytes: 5_300_000_000)
        #expect(ModelGuide.description(of: "granite4.2:8b", installed: installed)
                == "8.0B parameters, 5.3 GB on disk. Not measured by Exhibit A.")
        #expect(ModelGuide.description(of: "big:70b", installed: InstalledModel(bytes: 42_499_000_000))
                == "42 GB on disk. Not measured by Exhibit A.")
        #expect(ModelGuide.description(of: "lmstudio-model", installed: nil) == "Not measured by Exhibit A.")
    }

    @Test func sizesReadAsOllamaPrintsThem() {
        #expect(ModelGuide.size(18_000_000_000) == "18 GB")
        #expect(ModelGuide.size(6_600_000_000) == "6.6 GB")
        #expect(ModelGuide.size(950_000_000) == "950 MB")
    }

    @Test func ollamasListGivesEachModelsSizeAndParameters() {
        let body = Data(#"""
        {"models":[{"name":"granite4.2:8b","size":5300000000,"details":{"parameter_size":"8.0B"}},
                   {"name":"bare:1b"}]}
        """#.utf8)
        let details = ModelDiscovery.details(in: body)
        #expect(details["granite4.2:8b"] == InstalledModel(parameterSize: "8.0B", bytes: 5_300_000_000))
        #expect(details["bare:1b"] == nil)
    }

    @Test func settingsDescribeTheModelInUse() {
        let server = ModelServer(kind: .ollama, url: Self.ollama, models: ["granite4.2:8b", "ornith-1.5:9b"],
                                 details: ["granite4.2:8b": InstalledModel(parameterSize: "8.0B", bytes: 5_300_000_000)])
        let discovery = Discovery(probes: [.found(server)])
        let chosen = ModelSettings(choice: .installed(server: .ollama, url: Self.ollama.absoluteString,
                                                      model: "granite4.2:8b"))
        #expect(chosen.modelDescription(discovery: discovery)
                == "8.0B parameters, 5.3 GB on disk. Not measured by Exhibit A.")
        let byDefault = ModelSettings()
        #expect(byDefault.modelDescription(discovery: discovery) == ModelGuide.measured["ornith-1.5:9b"])
        #expect(ModelSettings(choice: ModelSettings.Choice.none).modelDescription(discovery: discovery) == nil)
        #expect(byDefault.modelDescription(discovery: nil) == nil, "nothing to describe while looking")
    }
}
