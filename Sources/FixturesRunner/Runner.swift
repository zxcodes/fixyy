import Foundation
import FixyyCore

@main
struct FixturesRunner {
    static func main() async {
        let client = await MainActor.run { ModelClient() }
        let availability = await MainActor.run { client.availability }
        guard availability == .available else {
            fputs("Model unavailable: \(availability.settingsLabel)\n", stderr)
            exit(1)
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Fixtures/prompts")
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            fputs("Could not read \(root.path): \(error)\n", stderr)
            exit(1)
        }

        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("== \(file.lastPathComponent) ==")
            print("in:  \(trimmed)")
            do {
                let result = try await client.fixGrammar(text: trimmed, styleNote: "")
                print("hasChanges: \(result.hasChanges)")
                print("out: \(result.text)")
            } catch {
                print("error: \(error)")
            }
            print()
        }
    }
}
