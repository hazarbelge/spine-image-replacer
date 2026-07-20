import AppKit

enum SpineApplicationLocator {
    private static let knownNames: Set<String> = ["spine", "spine trial", "spinetrial"]
    private static var lastActiveProcessIdentifier: pid_t?

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
        if let active = applications.first(where: \.isActive) {
            lastActiveProcessIdentifier = active.processIdentifier
            return active
        }
        if let lastActiveProcessIdentifier,
           let lastActive = applications.first(where: { $0.processIdentifier == lastActiveProcessIdentifier }) {
            return lastActive
        }
        if applications.count == 1 {
            lastActiveProcessIdentifier = applications[0].processIdentifier
            return applications[0]
        }
        return nil
    }

    static var detectionProcessIdentifiers: [pid_t] {
        let preferred = activeApplication
        var identifiers: [pid_t] = []
        if let preferred {
            identifiers.append(preferred.processIdentifier)
        }
        for application in runningApplications where !identifiers.contains(application.processIdentifier) {
            identifiers.append(application.processIdentifier)
        }
        return identifiers
    }
}
