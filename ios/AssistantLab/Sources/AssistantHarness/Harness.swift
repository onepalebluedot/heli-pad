import Foundation
import AssistantKit
import AssistantMocks
import AssistantDevRelay

/// Command-line driver for the assistant work stream.
///
///     swift run AssistantHarness            scripted scenarios, printed as cards
///     swift run AssistantHarness --repl     type your own messages
///     swift run AssistantHarness --attacks  the refusal and isolation cases
///     swift run AssistantHarness --live     answer with a real model (needs a key)
///     swift run AssistantHarness --suggest  the shortcut-suggestion pass (add --live)
///
/// It runs the real engine against the mock household, so what prints is what
/// the SwiftUI sheet would draw. `--live` swaps only the model; every other
/// part of the path is the same one the app will use.
@main
struct Harness {
    static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())

        let lab: Lab
        if arguments.contains("--live") {
            do {
                let client = try DirectOpenAIClient.fromEnvironment()
                lab = Lab(client: client, label: "live \(client.model)")
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
        } else {
            lab = Lab()
        }

        if arguments.contains("--suggest") {
            let client: LunaClient
            if arguments.contains("--live") {
                client = (try? DirectOpenAIClient.fromEnvironment()) ?? ScriptedLunaClient()
            } else {
                client = ScriptedLunaClient()
            }
            await lab.suggestions(client: client)
            await lab.weakSuggestions(client: client)
        } else if arguments.contains("--repl") {
            await lab.repl()
        } else if arguments.contains("--attacks") {
            await lab.attacks()
        } else if arguments.contains("--live") {
            await lab.liveScenarios()
        } else {
            await lab.scenarios()
            print("")
            await lab.attacks()
        }
    }
}
