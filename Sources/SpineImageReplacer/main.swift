import AppKit

if CommandLine.arguments.contains("--headless-scan") ||
    CommandLine.arguments.contains("--headless-apply") ||
    CommandLine.arguments.contains("--headless-undo") {
    exit(HeadlessRunner.run(arguments: CommandLine.arguments))
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
