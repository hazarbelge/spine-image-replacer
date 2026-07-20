import AppKit

enum SpineApplicationLocator {
    private static let knownNames: Set<String> = ["spine", "spine trial", "spinetrial"]

    static func isSpineApplication(_ application: NSRunningApplication) -> Bool {
        let name = application.localizedName?.lowercased() ?? ""
        let bundleName = application.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() ?? ""
        let identifier = application.bundleIdentifier?.lowercased() ?? ""
        return knownNames.contains(name)
            || knownNames.contains(bundleName)
            || identifier.contains("esotericsoftware.spine")
    }

    static var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter(isSpineApplication)
    }

    static var activeApplication: NSRunningApplication? {
        let applications = runningApplications
        return applications.first(where: \.isActive) ?? (applications.count == 1 ? applications[0] : nil)
    }
}
