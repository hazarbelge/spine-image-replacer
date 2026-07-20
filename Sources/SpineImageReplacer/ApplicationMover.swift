import AppKit

final class ApplicationMover {
    private let fileManager = FileManager.default

    var destinationURL: URL {
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let applicationsDirectory: URL
        if fileManager.isWritableFile(atPath: systemApplications.path) {
            applicationsDirectory = systemApplications
        } else {
            applicationsDirectory = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        }
        return applicationsDirectory.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
    }

    var destinationExists: Bool {
        fileManager.fileExists(atPath: destinationURL.path)
    }

    func installCurrentApplication() throws -> URL {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        let applicationsDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: applicationsDirectory,
            withIntermediateDirectories: true
        )

        let stagingURL = applicationsDirectory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).installing-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: stagingURL) }

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                var trashedURL: NSURL?
                try fileManager.trashItem(at: destinationURL, resultingItemURL: &trashedURL)
            }
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            throw NSError(
                domain: "SpineImageReplacer.ApplicationMover",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "The app could not be copied to \(applicationsDirectory.path).",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        return destinationURL
    }

    func relaunchInstalledApplication(
        at installedURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installedURL, configuration: configuration) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func trashOriginalApplicationIfPossible(installedURL: URL) {
        let originalURL = Bundle.main.bundleURL.standardizedFileURL
        guard originalURL != installedURL.standardizedFileURL else { return }
        var trashedURL: NSURL?
        try? fileManager.trashItem(at: originalURL, resultingItemURL: &trashedURL)
    }
}
