import Foundation

enum HeadlessRunner {
    static func run(arguments: [String]) -> Int32 {
        do {
            if arguments.contains("--headless-undo") {
                let project = try requiredURL("--project", arguments: arguments, directory: false)
                let backup = try ImageReplacementEngine.undoLast(projectURL: project)
                print("Restored backup: \(backup.path)")
                return 0
            }
            let original = try requiredURL("--original-images", arguments: arguments, directory: true)
            let replacement = try requiredURL("--replacement-images", arguments: arguments, directory: true)
            if arguments.contains("--headless-apply") {
                let project = try requiredURL("--project", arguments: arguments, directory: false)
                let result = try ImageReplacementEngine.apply(
                    projectURL: project,
                    originalRoot: original,
                    replacementRoot: replacement
                )
                print("Applied \(result.changedCount) PNGs; aligned \(result.alignedCount).")
                print("Backup: \(result.backupURL.path)")
                return 0
            }

            let result = try ImageReplacementEngine.scan(
                originalRoot: original,
                replacementRoot: replacement
            )
            print("Checked \(result.items.count) replacement PNGs.")
            print(
                "Will align: \(result.alignCount), ready: \(result.readyCount), " +
                "unchanged: \(result.unchangedCount), blocked: \(result.blockedCount), " +
                "originals untouched: \(result.untouchedOriginalCount)."
            )
            for item in result.items where item.status == .blocked {
                print("BLOCKED \(item.relativePath): \(item.message)")
            }
            return result.blockedCount == 0 ? 0 : 2
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func requiredURL(
        _ flag: String,
        arguments: [String],
        directory: Bool
    ) throws -> URL {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            throw NSError(
                domain: "SpineImageReplacer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing \(flag)"]
            )
        }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: directory).standardizedFileURL
    }
}
