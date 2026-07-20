import AppKit
import UniformTypeIdentifiers

final class ReplacementWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let projectPicker = PathPickerControl(
        title: "Spine project",
        placeholder: "Choose or drop a .spine project",
        mode: .spineProject
    )
    private let originalPicker = PathPickerControl(
        title: "Current images",
        placeholder: "Choose or drop the live images folder",
        mode: .folder
    )
    private let replacementPicker = PathPickerControl(
        title: "New images",
        placeholder: "Choose or drop the replacement images folder",
        mode: .folder
    )
    private let scanButton = NSButton(title: "Scan Images", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply with Backup", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo Last Replacement", target: nil, action: nil)
    private let openSpineButton = NSButton(title: "Open Project in Spine", target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "Choose the three inputs, then scan.")
    private let statusLabel = NSTextField(wrappingLabelWithString: "No source files are changed until you click Apply with Backup.")
    private let tableView = NSTableView()
    private let originalPreview = PreviewPane(title: "Current")
    private let replacementPreview = PreviewPane(title: "Replacement after alignment")
    private var scanResult: ScanResult?
    private var isWorking = false
    private var projectInputRevision = 0
    private var detectionRequestID = UUID()
    private let imagesFoldersDefaultsKey = "imagesFoldersByProject"

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spine Image Replacer"
        window.minSize = NSSize(width: 760, height: 650)
        window.center()
        super.init(window: window)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int {
        scanResult?.items.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = scanResult?.items[row], let identifier = tableColumn?.identifier else { return nil }
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingMiddle
        field.toolTip = item.message
        switch identifier.rawValue {
        case "status":
            field.stringValue = item.status.rawValue
            field.font = .systemFont(ofSize: 12, weight: .semibold)
            field.textColor = color(for: item.status)
        case "path":
            field.stringValue = item.relativePath
        default:
            field.stringValue = item.message
            field.textColor = .secondaryLabelColor
        }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }

    func prepareForActiveSpineProject() {
        let requestID = UUID()
        detectionRequestID = requestID
        let startingRevision = projectInputRevision
        let processIdentifiers = SpineApplicationLocator.detectionProcessIdentifiers
        guard !processIdentifiers.isEmpty else {
            handleProjectDetection(.noSpineApplication)
            return
        }
        statusLabel.stringValue = "Looking for the project open in Spine…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ActiveSpineProjectDetector.detect(processIdentifiers: processIdentifiers)
            DispatchQueue.main.async {
                guard let self,
                      self.detectionRequestID == requestID,
                      self.projectInputRevision == startingRevision
                else { return }
                self.handleProjectDetection(result)
            }
        }
    }

    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Replace artwork in the open Spine project")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: "The attached Spine button opens this panel. Apply creates a backup first, then updates the live PNG folder so Spine 4.2 reloads it.")
        subtitle.textColor = .secondaryLabelColor

        projectPicker.onChange = { [weak self] in self?.projectDidChange() }
        projectPicker.onDetect = { [weak self] in self?.prepareForActiveSpineProject() }
        originalPicker.onChange = { [weak self] in
            self?.inputsDidChange()
            self?.rememberCurrentImagesFolder()
        }
        replacementPicker.onChange = { [weak self] in self?.inputsDidChange() }

        scanButton.target = self
        scanButton.action = #selector(scanImages)
        scanButton.bezelStyle = .rounded
        scanButton.keyEquivalent = "\r"

        applyButton.target = self
        applyButton.action = #selector(applyImages)
        applyButton.bezelStyle = .rounded
        applyButton.contentTintColor = .systemOrange
        applyButton.isEnabled = false

        undoButton.target = self
        undoButton.action = #selector(undoLastReplacement)
        undoButton.bezelStyle = .rounded

        openSpineButton.target = self
        openSpineButton.action = #selector(openProjectInSpine)
        openSpineButton.bezelStyle = .rounded

        let actionRow = NSStackView(views: [scanButton, applyButton, undoButton, openSpineButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        actionRow.distribution = .fillProportionally

        summaryLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        summaryLabel.lineBreakMode = .byTruncatingTail

        configureTable()
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

        let previewRow = NSStackView(views: [originalPreview, replacementPreview])
        previewRow.orientation = .horizontal
        previewRow.distribution = .fillEqually
        previewRow.spacing = 12
        previewRow.translatesAutoresizingMaskIntoConstraints = false
        previewRow.heightAnchor.constraint(equalToConstant: 190).isActive = true

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            title,
            subtitle,
            projectPicker,
            originalPicker,
            replacementPicker,
            actionRow,
            summaryLabel,
            scrollView,
            previewRow,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        for view in [subtitle, projectPicker, originalPicker, replacementPicker, actionRow, summaryLabel, scrollView, previewRow, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    private func configureTable() {
        let status = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        status.title = "Result"
        status.width = 105
        status.minWidth = 90
        let path = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        path.title = "PNG"
        path.width = 300
        path.minWidth = 180
        let details = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("details"))
        details.title = "What will happen"
        details.width = 430
        details.minWidth = 240
        tableView.addTableColumn(status)
        tableView.addTableColumn(path)
        tableView.addTableColumn(details)
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 25
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
    }

    private func color(for status: ReplacementStatus) -> NSColor {
        switch status {
        case .ready: return .systemGreen
        case .align: return .systemOrange
        case .unchanged: return .secondaryLabelColor
        case .blocked: return .systemRed
        }
    }

    private func inputsDidChange() {
        scanResult = nil
        tableView.reloadData()
        applyButton.isEnabled = false
        originalPreview.clear()
        replacementPreview.clear()
        summaryLabel.stringValue = "Inputs changed. Scan again before applying."
    }

    private func projectDidChange() {
        projectInputRevision += 1
        inputsDidChange()
        guard let project = validProjectURL(projectPicker.url) else { return }
        restoreCurrentImagesFolder(for: project, clearWhenMissing: false)
    }

    private func handleProjectDetection(_ result: SpineProjectDetectionResult) {
        switch result {
        case .detected(let project):
            let previousProject = validProjectURL(projectPicker.url)
            let changedProject = previousProject?.resolvingSymlinksInPath() != project.url.resolvingSymlinksInPath()
            projectPicker.setURL(project.url)
            if changedProject {
                restoreCurrentImagesFolder(for: project.url, clearWhenMissing: true)
                replacementPicker.clear()
                inputsDidChange()
                summaryLabel.stringValue = originalPicker.url == nil
                    ? "Project detected. Choose the current and new images folders, then scan."
                    : "Project and current images detected. Choose the new images folder, then scan."
            }
            statusLabel.stringValue = "Detected open project: \(project.url.lastPathComponent) (\(project.source.rawValue))."
        case .ambiguous:
            statusLabel.stringValue = "More than one open .spine project was found. Choose the project manually."
        case .notFound:
            statusLabel.stringValue = "The open Spine project could not be identified. Choose it manually."
        case .noSpineApplication:
            statusLabel.stringValue = "Open a Spine project, or choose the .spine file manually."
        }
    }

    private func validProjectURL(_ url: URL?) -> URL? {
        guard let url, url.pathExtension.lowercased() == "spine" else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func rememberCurrentImagesFolder() {
        guard let project = validProjectURL(projectPicker.url),
              let images = originalPicker.url
        else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: images.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        var folders = UserDefaults.standard.dictionary(forKey: imagesFoldersDefaultsKey) as? [String: String] ?? [:]
        folders[project.path] = images.standardizedFileURL.resolvingSymlinksInPath().path
        UserDefaults.standard.set(folders, forKey: imagesFoldersDefaultsKey)
    }

    private func restoreCurrentImagesFolder(for project: URL, clearWhenMissing: Bool) {
        let folders = UserDefaults.standard.dictionary(forKey: imagesFoldersDefaultsKey) as? [String: String] ?? [:]
        if let storedPath = folders[project.resolvingSymlinksInPath().path] {
            let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: storedURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                originalPicker.setURL(storedURL)
                return
            }
        }

        let conventionalImages = project.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: conventionalImages.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            originalPicker.setURL(conventionalImages)
        } else if clearWhenMissing {
            originalPicker.clear()
        }
    }

    @objc private func scanImages() {
        guard let inputs = validatedInputs(requireProject: false) else { return }
        setWorking(true, message: "Scanning PNGs…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try ImageReplacementEngine.scan(
                    originalRoot: inputs.original,
                    replacementRoot: inputs.replacement
                )
                DispatchQueue.main.async { self?.showScanResult(result) }
            } catch {
                DispatchQueue.main.async { self?.showError(error) }
            }
        }
    }

    @objc private func applyImages() {
        guard let inputs = validatedInputs(requireProject: true), let result = scanResult else { return }
        guard result.blockedCount == 0, result.actionableCount > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "Apply \(result.actionableCount) replacement image(s)?"
        alert.informativeText = "A timestamped backup will be created first. Spine may reload the images immediately."
        alert.addButton(withTitle: "Apply with Backup")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setWorking(true, message: "Creating backup and applying images…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let applyResult = try ImageReplacementEngine.apply(
                    projectURL: inputs.project!,
                    originalRoot: inputs.original,
                    replacementRoot: inputs.replacement
                )
                let refreshed = try ImageReplacementEngine.scan(
                    originalRoot: inputs.original,
                    replacementRoot: inputs.replacement
                )
                DispatchQueue.main.async {
                    self?.scanResult = refreshed
                    self?.tableView.reloadData()
                    self?.setWorking(
                        false,
                        message: "Applied \(applyResult.changedCount) PNGs. Old images: \(applyResult.oldImagesURL.path)"
                    )
                    self?.updateSummary()
                }
            } catch {
                DispatchQueue.main.async { self?.showError(error) }
            }
        }
    }

    @objc private func undoLastReplacement() {
        guard let inputs = validatedInputs(requireProject: true) else { return }
        let alert = NSAlert()
        alert.messageText = "Undo the last replacement?"
        alert.informativeText = "The most recent active backup for this project will be restored to the live images folder."
        alert.addButton(withTitle: "Restore Backup")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setWorking(true, message: "Restoring the last backup…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let backup = try ImageReplacementEngine.undoLast(projectURL: inputs.project!)
                let refreshed = try ImageReplacementEngine.scan(
                    originalRoot: inputs.original,
                    replacementRoot: inputs.replacement
                )
                DispatchQueue.main.async {
                    self?.scanResult = refreshed
                    self?.tableView.reloadData()
                    self?.setWorking(false, message: "Restored backup: \(backup.path)")
                    self?.updateSummary()
                }
            } catch {
                DispatchQueue.main.async { self?.showError(error) }
            }
        }
    }

    @objc private func openProjectInSpine() {
        guard let project = projectPicker.url else {
            showErrorMessage("Choose a .spine project first.")
            return
        }
        if let spine = SpineApplicationLocator.activeApplication, let appURL = spine.bundleURL {
            NSWorkspace.shared.open(
                [project],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(project)
        }
    }

    private func showScanResult(_ result: ScanResult) {
        scanResult = result
        tableView.reloadData()
        if !result.items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        setWorking(false, message: result.blockedCount == 0
            ? "Scan complete. Review the list before applying."
            : "Nothing was changed. Resolve the blocked files before applying.")
        updateSummary()
    }

    private func updateSummary() {
        guard let result = scanResult else { return }
        summaryLabel.stringValue = "\(result.items.count) replacements — \(result.alignCount) align, \(result.readyCount) ready, \(result.unchangedCount) unchanged, \(result.blockedCount) blocked; \(result.untouchedOriginalCount) originals untouched."
        applyButton.isEnabled = !isWorking && result.blockedCount == 0 && result.actionableCount > 0
        updatePreview()
    }

    private func updatePreview() {
        guard let result = scanResult,
              tableView.selectedRow >= 0,
              tableView.selectedRow < result.items.count
        else {
            originalPreview.clear()
            replacementPreview.clear()
            return
        }
        let item = result.items[tableView.selectedRow]
        originalPreview.show(url: item.originalURL, geometry: item.originalGeometry)
        if item.status == .align,
           let originalURL = item.originalURL,
           let preview = try? ImageReplacementEngine.alignedPreview(
                originalURL: originalURL,
                replacementURL: item.replacementURL
           ) {
            replacementPreview.show(
                image: NSImage(cgImage: preview.image, size: .zero),
                geometry: preview.geometry
            )
        } else {
            replacementPreview.show(url: item.replacementURL, geometry: item.replacementGeometry)
        }
    }

    private func setWorking(_ working: Bool, message: String) {
        isWorking = working
        statusLabel.stringValue = message
        scanButton.isEnabled = !working
        undoButton.isEnabled = !working
        openSpineButton.isEnabled = !working
        applyButton.isEnabled = !working && (scanResult?.blockedCount == 0) && ((scanResult?.actionableCount ?? 0) > 0)
    }

    private func validatedInputs(requireProject: Bool) -> (
        project: URL?, original: URL, replacement: URL
    )? {
        guard let original = originalPicker.url else {
            showErrorMessage("Choose the current images folder.")
            return nil
        }
        guard let replacement = replacementPicker.url else {
            showErrorMessage("Choose the new images folder.")
            return nil
        }
        let project = projectPicker.url
        if requireProject && project == nil {
            showErrorMessage("Choose the .spine project so the backup can be associated with it.")
            return nil
        }
        return (project, original, replacement)
    }

    private func showError(_ error: Error) {
        setWorking(false, message: "Nothing was changed.")
        showErrorMessage(error.localizedDescription)
    }

    private func showErrorMessage(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Spine Image Replacer"
        alert.informativeText = message
        alert.runModal()
    }
}

private enum PickerMode {
    case spineProject
    case folder
}

private final class PathPickerControl: NSView, NSTextFieldDelegate {
    var onChange: (() -> Void)?
    var onDetect: (() -> Void)?
    var url: URL? {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: mode == .folder).standardizedFileURL
    }

    private let field = NSTextField()
    private let mode: PickerMode
    private var isDragHighlighted = false {
        didSet {
            guard oldValue != isDragHighlighted else { return }
            layer?.borderWidth = isDragHighlighted ? 2 : 0
            layer?.borderColor = isDragHighlighted ? NSColor.controlAccentColor.cgColor : nil
            layer?.backgroundColor = isDragHighlighted
                ? NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
                : nil
        }
    }

    init(title: String, placeholder: String, mode: PickerMode) {
        self.mode = mode
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        registerForDraggedTypes([.fileURL])

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right
        field.placeholderString = placeholder
        field.delegate = self
        field.lineBreakMode = .byTruncatingMiddle
        let choose = NSButton(title: "Choose…", target: self, action: #selector(choosePath))
        choose.bezelStyle = .rounded
        var rowViews: [NSView] = [label, field]
        var detectButton: NSButton?
        if mode == .spineProject {
            let detect = NSButton(title: "Detect", target: self, action: #selector(detectProject))
            detect.bezelStyle = .rounded
            rowViews.append(detect)
            detectButton = detect
        }
        rowViews.append(choose)

        let row = NSStackView(views: rowViews)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        var constraints = [
            label.widthAnchor.constraint(equalToConstant: 112),
            choose.widthAnchor.constraint(equalToConstant: 82),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 30)
        ]
        if let detectButton {
            constraints.append(detectButton.widthAnchor.constraint(equalToConstant: 68))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setURL(_ url: URL) {
        field.stringValue = url.standardizedFileURL.path
    }

    func clear() {
        field.stringValue = ""
    }

    func controlTextDidChange(_ obj: Notification) {
        onChange?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragState(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragState(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDragHighlighted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isDragHighlighted = false }
        guard let droppedURL = droppedURL(from: sender) else { return false }
        field.stringValue = droppedURL.path
        onChange?()
        return true
    }

    private func updateDragState(_ sender: NSDraggingInfo) -> NSDragOperation {
        let acceptsDrop = droppedURL(from: sender) != nil
        isDragHighlighted = acceptsDrop
        return acceptsDrop ? .copy : []
    }

    private func droppedURL(from sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL], urls.count == 1 else { return nil }

        let url = urls[0].standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        switch mode {
        case .spineProject:
            return !isDirectory.boolValue && url.pathExtension.lowercased() == "spine" ? url : nil
        case .folder:
            return isDirectory.boolValue ? url : nil
        }
    }

    @objc private func detectProject() {
        onDetect?()
    }

    @objc private func choosePath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = mode == .folder
        panel.canChooseFiles = mode == .spineProject
        panel.canCreateDirectories = false
        if mode == .spineProject {
            panel.allowedContentTypes = [UTType(filenameExtension: "spine") ?? .data]
        }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        field.stringValue = selected.path
        onChange?()
    }
}

private final class PreviewPane: NSView {
    private let imageView = NSImageView()
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel, imageView, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 125),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(url: URL?, geometry: ImageGeometry?) {
        show(image: url.flatMap(NSImage.init(contentsOf:)), geometry: geometry)
    }

    func show(image: NSImage?, geometry: ImageGeometry?) {
        imageView.image = image
        if let geometry {
            let visible = geometry.visibleBounds?.text ?? "blank"
            detailLabel.stringValue = "Canvas \(geometry.canvasText) · Visible \(visible)"
        } else {
            detailLabel.stringValue = "Not available"
        }
    }

    func clear() {
        imageView.image = nil
        detailLabel.stringValue = ""
    }
}
