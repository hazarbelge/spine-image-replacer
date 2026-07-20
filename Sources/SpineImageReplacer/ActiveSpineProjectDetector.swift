import Foundation
import CoreGraphics

enum ProjectDetectionSource: String {
    case openFile = "open file"
    case processArgument = "launch argument"
    case windowTitle = "Spine window title"
}

struct DetectedSpineProject {
    let url: URL
    let source: ProjectDetectionSource
}

enum SpineProjectDetectionResult {
    case detected(DetectedSpineProject)
    case noSpineApplication
    case notFound
    case ambiguous([URL])
}

enum ActiveSpineProjectDetector {
    static func detectActiveProject() -> SpineProjectDetectionResult {
        let processIdentifiers = SpineApplicationLocator.detectionProcessIdentifiers
        guard !processIdentifiers.isEmpty else {
            return .noSpineApplication
        }
        return detect(processIdentifiers: processIdentifiers)
    }

    static func detect(processIdentifiers: [pid_t]) -> SpineProjectDetectionResult {
        var detectedProjects: [DetectedSpineProject] = []
        var ambiguousProjects: [URL] = []
        for processIdentifier in processIdentifiers {
            switch detect(processIdentifier: processIdentifier) {
            case .detected(let project):
                detectedProjects.append(project)
            case .ambiguous(let projects):
                ambiguousProjects.append(contentsOf: projects)
            case .notFound, .noSpineApplication:
                break
            }
        }

        let allURLs = uniqueURLs(detectedProjects.map(\.url) + ambiguousProjects)
        if allURLs.count > 1 {
            return .ambiguous(allURLs)
        }
        if let onlyURL = allURLs.first {
            let source = detectedProjects.first(where: {
                $0.url.resolvingSymlinksInPath() == onlyURL.resolvingSymlinksInPath()
            })?.source ?? .windowTitle
            return .detected(DetectedSpineProject(url: onlyURL, source: source))
        }
        return .notFound
    }

    static func detect(processIdentifier pid: pid_t) -> SpineProjectDetectionResult {
        let openFiles = projectURLsFromOpenFiles(pid: pid)
        if openFiles.count == 1 {
            return .detected(DetectedSpineProject(url: openFiles[0], source: .openFile))
        }

        let titleMatches = projectURLsFromWindowTitle(pid: pid)
        if titleMatches.count == 1 {
            return .detected(DetectedSpineProject(url: titleMatches[0], source: .windowTitle))
        }

        let arguments = projectURLsFromProcessArguments(pid: pid)
        if arguments.count == 1 {
            return .detected(DetectedSpineProject(url: arguments[0], source: .processArgument))
        }

        let ambiguous = uniqueURLs(openFiles + arguments + titleMatches)
        return ambiguous.count > 1 ? .ambiguous(ambiguous) : .notFound
    }

    private static func projectURLsFromOpenFiles(pid: pid_t) -> [URL] {
        guard let output = run("/usr/sbin/lsof", arguments: ["-Fn", "-a", "-p", String(pid)]) else {
            return []
        }
        let paths = output.split(separator: "\n").compactMap { line -> String? in
            guard line.first == "n" else { return nil }
            return String(line.dropFirst())
        }
        return validProjectURLs(paths)
    }

    private static func projectURLsFromProcessArguments(pid: pid_t) -> [URL] {
        guard let output = run("/bin/ps", arguments: ["-ww", "-p", String(pid), "-o", "command="]) else {
            return []
        }
        let pattern = #"(?:\"([^\"]+\.spine)\"|'([^']+\.spine)'|([^\s]+\.spine))(?:\s|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let paths = expression.matches(in: output, range: range).compactMap { match -> String? in
            for index in 1..<match.numberOfRanges {
                let group = match.range(at: index)
                if group.location != NSNotFound, let swiftRange = Range(group, in: output) {
                    return String(output[swiftRange])
                }
            }
            return nil
        }
        return validProjectURLs(paths)
    }

    private static func projectURLsFromWindowTitle(pid: pid_t) -> [URL] {
        guard let title = largestWindowTitle(pid: pid), !title.isEmpty else { return [] }

        let projectNames = possibleProjectFilenames(from: title)
        var matches: [URL] = []
        for name in projectNames {
            let escaped = name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            guard let output = run(
                "/usr/bin/mdfind",
                arguments: ["kMDItemFSName == \"\(escaped)\"c"]
            ) else { continue }
            matches.append(contentsOf: validProjectURLs(output.split(separator: "\n").map(String.init)))
        }
        return uniqueURLs(matches)
    }

    private static func possibleProjectFilenames(from title: String) -> [String] {
        var names: [String] = []
        let spinePattern = #"([^/\\]+?\.spine)"#
        if let expression = try? NSRegularExpression(pattern: spinePattern, options: [.caseInsensitive]) {
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            for match in expression.matches(in: title, range: range) {
                if let swiftRange = Range(match.range(at: 1), in: title) {
                    names.append(URL(fileURLWithPath: String(title[swiftRange])).lastPathComponent)
                }
            }
        }

        if names.isEmpty {
            var base = title.trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in [" — Spine", " – Spine", " - Spine", " | Spine"] where base.hasSuffix(suffix) {
                base.removeLast(suffix.count)
                base = base.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            if !base.isEmpty,
               base.caseInsensitiveCompare("Spine") != .orderedSame,
               base.caseInsensitiveCompare("Spine Launcher") != .orderedSame {
                names.append(base.hasSuffix(".spine") ? base : "\(base).spine")
            }
        }
        return Array(Set(names))
    }

    private static func largestWindowTitle(pid: pid_t) -> String? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        return windows.compactMap { info -> (String, CGFloat)? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == pid,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let title = info[kCGWindowName as String] as? String,
                  frame.width > 400,
                  frame.height > 300
            else { return nil }
            return (title, frame.width * frame.height)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private static func validProjectURLs<S: Sequence>(_ paths: S) -> [URL] where S.Element == String {
        uniqueURLs(paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard url.pathExtension.lowercased() == "spine",
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return nil }
            return url
        })
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }

    private static func run(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
