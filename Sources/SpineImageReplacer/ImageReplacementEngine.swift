import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ReplacementStatus: String, Codable {
    case ready = "Ready"
    case align = "Will Align"
    case unchanged = "Unchanged"
    case blocked = "Blocked"
}

struct PixelBounds: Codable, Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var text: String { "\(width)×\(height) at \(x),\(y)" }
}

struct ImageGeometry: Codable, Equatable {
    let width: Int
    let height: Int
    let visibleBounds: PixelBounds?

    var canvasText: String { "\(width)×\(height)" }
}

struct ReplacementItem {
    let relativePath: String
    let status: ReplacementStatus
    let message: String
    let originalURL: URL?
    let replacementURL: URL
    let originalGeometry: ImageGeometry?
    let replacementGeometry: ImageGeometry?
}

struct ScanResult {
    let originalRoot: URL
    let replacementRoot: URL
    let items: [ReplacementItem]
    let untouchedOriginalCount: Int

    var blockedCount: Int { items.filter { $0.status == .blocked }.count }
    var alignCount: Int { items.filter { $0.status == .align }.count }
    var readyCount: Int { items.filter { $0.status == .ready }.count }
    var unchangedCount: Int { items.filter { $0.status == .unchanged }.count }
    var actionableCount: Int { alignCount + readyCount }
}

struct ApplyResult {
    let changedCount: Int
    let alignedCount: Int
    let backupURL: URL
    let oldImagesURL: URL
}

enum ReplacementError: LocalizedError {
    case invalidFolder(String)
    case duplicatePath(String)
    case unreadableImage(String)
    case blocked(Int)
    case nothingToApply
    case noBackup
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .invalidFolder(let path): return "Image folder does not exist: \(path)"
        case .duplicatePath(let path): return "Two PNG paths differ only by capitalization: \(path)"
        case .unreadableImage(let path): return "Could not read PNG: \(path)"
        case .blocked(let count): return "\(count) replacement image(s) are unsafe. Resolve them before applying."
        case .nothingToApply: return "There are no changed replacement images to apply."
        case .noBackup: return "No active replacement backup was found for this project."
        case .invalidBackup(let message): return "The backup cannot be restored: \(message)"
        }
    }
}

enum ImageReplacementEngine {
    private static let fileManager = FileManager.default

    static func scan(originalRoot: URL, replacementRoot: URL) throws -> ScanResult {
        let originals = try collectPNGs(in: originalRoot)
        let replacements = try collectPNGs(in: replacementRoot)
        var items: [ReplacementItem] = []

        for relativePath in replacements.keys.sorted() {
            let replacementURL = replacements[relativePath]!
            guard let originalURL = originals[relativePath] else {
                items.append(
                    ReplacementItem(
                        relativePath: relativePath,
                        status: .blocked,
                        message: "No original PNG has this exact relative path.",
                        originalURL: nil,
                        replacementURL: replacementURL,
                        originalGeometry: nil,
                        replacementGeometry: try? PixelImage(url: replacementURL).geometry
                    )
                )
                continue
            }

            do {
                let original = try PixelImage(url: originalURL)
                let replacement = try PixelImage(url: replacementURL)
                let statusAndMessage = classify(
                    originalURL: originalURL,
                    replacementURL: replacementURL,
                    original: original,
                    replacement: replacement
                )
                items.append(
                    ReplacementItem(
                        relativePath: relativePath,
                        status: statusAndMessage.0,
                        message: statusAndMessage.1,
                        originalURL: originalURL,
                        replacementURL: replacementURL,
                        originalGeometry: original.geometry,
                        replacementGeometry: replacement.geometry
                    )
                )
            } catch {
                items.append(
                    ReplacementItem(
                        relativePath: relativePath,
                        status: .blocked,
                        message: error.localizedDescription,
                        originalURL: originalURL,
                        replacementURL: replacementURL,
                        originalGeometry: nil,
                        replacementGeometry: nil
                    )
                )
            }
        }

        return ScanResult(
            originalRoot: originalRoot,
            replacementRoot: replacementRoot,
            items: items,
            untouchedOriginalCount: max(0, originals.count - replacements.count)
        )
    }

    static func apply(projectURL: URL, originalRoot: URL, replacementRoot: URL) throws -> ApplyResult {
        let scanResult = try scan(originalRoot: originalRoot, replacementRoot: replacementRoot)
        guard scanResult.blockedCount == 0 else { throw ReplacementError.blocked(scanResult.blockedCount) }
        let actionable = scanResult.items.filter { $0.status == .ready || $0.status == .align }
        guard !actionable.isEmpty else { throw ReplacementError.nothingToApply }

        let backupURL = try createBackupDirectory(for: projectURL)
        let originalsBackup = backupURL.appendingPathComponent("originals", isDirectory: true)
        let staged = backupURL.appendingPathComponent("staged", isDirectory: true)
        try fileManager.createDirectory(at: originalsBackup, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)

        for item in actionable {
            guard let originalURL = item.originalURL else { continue }
            let backupFile = originalsBackup.appendingPathComponent(item.relativePath)
            let stagedFile = staged.appendingPathComponent(item.relativePath)
            try createParentDirectory(for: backupFile)
            try createParentDirectory(for: stagedFile)
            try fileManager.copyItem(at: originalURL, to: backupFile)
            if item.status == .ready {
                try fileManager.copyItem(at: item.replacementURL, to: stagedFile)
            } else {
                let original = try PixelImage(url: originalURL)
                let replacement = try PixelImage(url: item.replacementURL)
                try writeAligned(original: original, replacement: replacement, to: stagedFile)
            }
        }

        let oldImagesURL = try createVisibleOldImagesSnapshot(for: originalRoot)
        var manifest = BackupManifest(
            projectPath: projectURL.path,
            originalImagesPath: originalRoot.path,
            visibleBackupPath: oldImagesURL.path,
            files: actionable.map(\.relativePath),
            createdAt: ISO8601DateFormatter().string(from: Date()),
            undoneAt: nil
        )
        try writeManifest(manifest, to: backupURL)

        var applied: [ReplacementItem] = []
        do {
            for item in actionable {
                let stagedFile = staged.appendingPathComponent(item.relativePath)
                let destination = originalRoot.appendingPathComponent(item.relativePath)
                try atomicReplace(destination: destination, with: stagedFile)
                applied.append(item)
            }
        } catch {
            for item in applied.reversed() {
                let backupFile = originalsBackup.appendingPathComponent(item.relativePath)
                let destination = originalRoot.appendingPathComponent(item.relativePath)
                try? atomicReplace(destination: destination, with: backupFile)
            }
            throw error
        }

        try? fileManager.removeItem(at: staged)
        manifest.undoneAt = nil
        try writeManifest(manifest, to: backupURL)
        return ApplyResult(
            changedCount: actionable.count,
            alignedCount: actionable.filter { $0.status == .align }.count,
            backupURL: backupURL,
            oldImagesURL: oldImagesURL
        )
    }

    static func undoLast(projectURL: URL) throws -> URL {
        let projectBackups = backupRoot(for: projectURL)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: projectBackups,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw ReplacementError.noBackup }

        for backupURL in directories.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard var manifest = try? readManifest(from: backupURL), manifest.undoneAt == nil else { continue }
            let originalRoot = URL(fileURLWithPath: manifest.originalImagesPath, isDirectory: true)
            let originalsBackup = backupURL.appendingPathComponent("originals", isDirectory: true)
            guard fileManager.fileExists(atPath: originalRoot.path) else {
                throw ReplacementError.invalidBackup("the original images folder no longer exists")
            }
            for relativePath in manifest.files {
                let backupFile = originalsBackup.appendingPathComponent(relativePath)
                let destination = originalRoot.appendingPathComponent(relativePath)
                guard fileManager.fileExists(atPath: backupFile.path) else {
                    throw ReplacementError.invalidBackup("missing \(relativePath)")
                }
                try atomicReplace(destination: destination, with: backupFile)
            }
            manifest.undoneAt = ISO8601DateFormatter().string(from: Date())
            try writeManifest(manifest, to: backupURL)
            return backupURL
        }
        throw ReplacementError.noBackup
    }

    static func alignedPreview(originalURL: URL, replacementURL: URL) throws -> (
        image: CGImage,
        geometry: ImageGeometry
    ) {
        let original = try PixelImage(url: originalURL)
        let replacement = try PixelImage(url: replacementURL)
        guard let oldBounds = original.geometry.visibleBounds,
              let newBounds = replacement.geometry.visibleBounds,
              oldBounds.width == newBounds.width,
              oldBounds.height == newBounds.height
        else { throw ReplacementError.unreadableImage(replacementURL.path) }
        let canvas = alignedPixels(
            original: original,
            replacement: replacement,
            oldBounds: oldBounds,
            newBounds: newBounds
        )
        guard let image = makeCGImage(
            pixels: canvas,
            width: original.width,
            height: original.height
        ) else { throw ReplacementError.unreadableImage(replacementURL.path) }
        return (image, original.geometry)
    }

    private static func classify(
        originalURL: URL,
        replacementURL: URL,
        original: PixelImage,
        replacement: PixelImage
    ) -> (ReplacementStatus, String) {
        let originalBounds = original.geometry.visibleBounds
        let replacementBounds = replacement.geometry.visibleBounds

        if originalBounds == nil && replacementBounds == nil {
            if original.width != replacement.width || original.height != replacement.height {
                return (.blocked, "Both images are blank, but their canvases differ.")
            }
            return filesAreIdentical(originalURL, replacementURL)
                ? (.unchanged, "Replacement is identical.")
                : (.ready, "Both images are blank and use the same canvas.")
        }
        guard let oldBounds = originalBounds else {
            return (.blocked, "The original is blank, but the replacement contains artwork.")
        }
        guard let newBounds = replacementBounds else {
            return (.blocked, "The replacement is blank, but the original contains artwork.")
        }
        guard oldBounds.width == newBounds.width, oldBounds.height == newBounds.height else {
            return (
                .blocked,
                "Visible artwork differs: \(oldBounds.width)×\(oldBounds.height) → \(newBounds.width)×\(newBounds.height)."
            )
        }
        if filesAreIdentical(originalURL, replacementURL) {
            return (.unchanged, "Replacement is identical.")
        }
        if original.artworkMatches(replacement, ownBounds: oldBounds, otherBounds: newBounds) {
            return (.unchanged, "Replacement artwork is already applied.")
        }
        if original.width == replacement.width,
           original.height == replacement.height,
           oldBounds == newBounds {
            return (.ready, "Canvas and artwork position already match.")
        }
        return (
            .align,
            "Will use the original \(original.width)×\(original.height) canvas and position artwork at \(oldBounds.x),\(oldBounds.y)."
        )
    }

    private static func collectPNGs(in root: URL) throws -> [String: URL] {
        let canonicalRoot = root.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonicalRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ReplacementError.invalidFolder(root.path)
        }
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw ReplacementError.invalidFolder(root.path) }

        var result: [String: URL] = [:]
        var caseMap: [String: String] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "png" else { continue }
            let canonicalURL = url.resolvingSymlinksInPath()
            let rootComponents = canonicalRoot.pathComponents
            let fileComponents = canonicalURL.pathComponents
            guard fileComponents.starts(with: rootComponents) else { continue }
            let relative = fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
            let folded = relative.lowercased()
            if let existing = caseMap[folded], existing != relative {
                throw ReplacementError.duplicatePath("\(existing), \(relative)")
            }
            caseMap[folded] = relative
            result[relative] = canonicalURL
        }
        return result
    }

    private static func filesAreIdentical(_ first: URL, _ second: URL) -> Bool {
        guard let firstData = try? Data(contentsOf: first, options: .mappedIfSafe),
              let secondData = try? Data(contentsOf: second, options: .mappedIfSafe)
        else { return false }
        return firstData == secondData
    }

    private static func writeAligned(original: PixelImage, replacement: PixelImage, to url: URL) throws {
        guard let oldBounds = original.geometry.visibleBounds,
              let newBounds = replacement.geometry.visibleBounds,
              oldBounds.width == newBounds.width,
              oldBounds.height == newBounds.height
        else { throw ReplacementError.unreadableImage(url.path) }

        let canvas = alignedPixels(
            original: original,
            replacement: replacement,
            oldBounds: oldBounds,
            newBounds: newBounds
        )
        try writePNG(pixels: canvas, width: original.width, height: original.height, to: url)
    }

    private static func alignedPixels(
        original: PixelImage,
        replacement: PixelImage,
        oldBounds: PixelBounds,
        newBounds: PixelBounds
    ) -> [UInt8] {
        var canvas = [UInt8](repeating: 0, count: original.width * original.height * 4)
        canvas.withUnsafeMutableBytes { destination in
            replacement.pixels.withUnsafeBytes { source in
                guard let destinationBase = destination.baseAddress,
                      let sourceBase = source.baseAddress else { return }
                for row in 0..<oldBounds.height {
                    let sourceOffset = ((newBounds.y + row) * replacement.width + newBounds.x) * 4
                    let destinationOffset = ((oldBounds.y + row) * original.width + oldBounds.x) * 4
                    destinationBase.advanced(by: destinationOffset).copyMemory(
                        from: sourceBase.advanced(by: sourceOffset),
                        byteCount: oldBounds.width * 4
                    )
                }
            }
        }
        return canvas
    }

    private static func writePNG(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let image = makeCGImage(pixels: pixels, width: width, height: height),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              )
        else { throw ReplacementError.unreadableImage(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ReplacementError.unreadableImage(url.path)
        }
    }

    private static func makeCGImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: PixelImage.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func createParentDirectory(for file: URL) throws {
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func atomicReplace(destination: URL, with source: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).spine-replacer-\(UUID().uuidString).tmp"
        )
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        do {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func backupRoot(for projectURL: URL) -> URL {
        let projectName = projectURL.deletingPathExtension().lastPathComponent
        return projectURL.deletingLastPathComponent()
            .appendingPathComponent(".spine-image-replacer-backups", isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
    }

    private static func createBackupDirectory(for projectURL: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
        let directory = backupRoot(for: projectURL).appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func createVisibleOldImagesSnapshot(for originalRoot: URL) throws -> URL {
        let source = originalRoot.standardizedFileURL.resolvingSymlinksInPath()
        let parent = source.deletingLastPathComponent()
        let baseName = "\(source.lastPathComponent)_old"
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName)_\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.copyItem(at: source, to: candidate)
        return candidate
    }

    private static func writeManifest(_ manifest: BackupManifest, to backupURL: URL) throws {
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: backupURL.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func readManifest(from backupURL: URL) throws -> BackupManifest {
        let data = try Data(contentsOf: backupURL.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(BackupManifest.self, from: data)
    }
}

private struct PixelImage {
    static let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )

    let width: Int
    let height: Int
    let pixels: [UInt8]
    let geometry: ImageGeometry

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ReplacementError.unreadableImage(url.path) }

        let imageWidth = image.width
        let imageHeight = image.height
        var decoded = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let rendered = decoded.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: Self.bitmapInfo.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard rendered else { throw ReplacementError.unreadableImage(url.path) }
        width = imageWidth
        height = imageHeight
        pixels = decoded
        geometry = ImageGeometry(
            width: imageWidth,
            height: imageHeight,
            visibleBounds: Self.findVisibleBounds(
                pixels: decoded,
                width: imageWidth,
                height: imageHeight
            )
        )
    }

    func artworkMatches(
        _ other: PixelImage,
        ownBounds: PixelBounds,
        otherBounds: PixelBounds
    ) -> Bool {
        guard ownBounds.width == otherBounds.width,
              ownBounds.height == otherBounds.height else { return false }
        return pixels.withUnsafeBytes { ownBytes in
            other.pixels.withUnsafeBytes { otherBytes in
                guard let ownBase = ownBytes.baseAddress,
                      let otherBase = otherBytes.baseAddress else { return false }
                for row in 0..<ownBounds.height {
                    let ownOffset = ((ownBounds.y + row) * width + ownBounds.x) * 4
                    let otherOffset = ((otherBounds.y + row) * other.width + otherBounds.x) * 4
                    if memcmp(
                        ownBase.advanced(by: ownOffset),
                        otherBase.advanced(by: otherOffset),
                        ownBounds.width * 4
                    ) != 0 { return false }
                }
                return true
            }
        }
    }

    private static func findVisibleBounds(pixels: [UInt8], width: Int, height: Int) -> PixelBounds? {
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] != 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return PixelBounds(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

private struct BackupManifest: Codable {
    let projectPath: String
    let originalImagesPath: String
    let visibleBackupPath: String?
    let files: [String]
    let createdAt: String
    var undoneAt: String?
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
