import AppKit
import AVFoundation
import AudioToolbox

final class PreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic view") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
}

final class RecorderDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class RecorderRootView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let parent = superview else { return }
        NSLog("Recorder root: %@ parent %@", NSStringFromRect(frame), NSStringFromRect(parent.bounds))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

final class TakeTable: NSTableView {
    var files: [URL] = []
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}

@objc(RecorderViewController)
final class RecorderViewController: NSViewController,
    AVCaptureFileOutputRecordingDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,
    NSTableViewDataSource, NSTableViewDelegate {
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "final-cut-tools.capture")
    private let output = AVCaptureMovieFileOutput()
    private let audioMeterOutput = AVCaptureAudioDataOutput()
    private let defaults = UserDefaults.standard
    // Final Cut instantiates the principal controller on an XPC queue. Create AppKit
    // controls lazily in loadView, after the host moves view creation to the main thread.
    private lazy var preview = PreviewView(frame: .zero)
    private lazy var cameras = NSPopUpButton()
    private lazy var microphones = NSPopUpButton()
    private lazy var folderButton = NSButton(title: "Choose recording folder…", target: nil, action: nil)
    private lazy var recordButton = NSButton(title: "● Record", target: nil, action: nil)
    private lazy var status = NSTextField(labelWithString: "Choose a recording folder to get started.")
    private lazy var timerLabel = NSTextField(labelWithString: "00:00")
    private lazy var level = NSLevelIndicator()
    private lazy var levelLabel = NSTextField(labelWithString: "Mic level")
    private lazy var table = TakeTable()
    private var videoDevices: [AVCaptureDevice] = []
    private var audioDevices: [AVCaptureDevice] = []
    private var folder: URL?
    private var scopedFolder = false
    private var configured = false
    private var busy = false
    private var startedAt: Date?
    private var timer: Timer?
    private var runtimeObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private var shouldStopAfterRecording = false
    private var lastLevelUpdate = Date.distantPast

    override func loadView() {
        view = RecorderRootView(frame: NSRect(x: 0, y: 0, width: 620, height: 660))
        view.autoresizingMask = [.width, .height]
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        preferredContentSize = NSSize(width: 620, height: 660)
        let title = NSTextField(labelWithString: "Record. Drop. Edit.")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Record yourself, then drag a take onto your timeline.")
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 5

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalToConstant: 240).isActive = true
        cameras.target = self; cameras.action = #selector(changeDevice)
        microphones.target = self; microphones.action = #selector(changeDevice)
        cameras.setAccessibilityLabel("Camera")
        microphones.setAccessibilityLabel("Microphone")
        let inputs = NSStackView(views: [labelled("Camera", cameras), labelled("Microphone", microphones)])
        inputs.distribution = .fillEqually; inputs.spacing = 12
        folderButton.target = self; folderButton.action = #selector(chooseFolder)
        folderButton.bezelStyle = .rounded
        folderButton.setAccessibilityLabel("Recording destination")
        recordButton.target = self; recordButton.action = #selector(toggleRecording)
        recordButton.bezelStyle = .rounded
        recordButton.controlSize = .large
        recordButton.font = .systemFont(ofSize: 16, weight: .semibold)
        recordButton.contentTintColor = .systemRed
        recordButton.isEnabled = false
        recordButton.setAccessibilityLabel("Record")
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        level.levelIndicatorStyle = .continuousCapacity
        level.minValue = 0; level.maxValue = 60
        level.warningValue = 48; level.criticalValue = 57
        level.isEditable = false
        level.setAccessibilityLabel("Microphone level")
        level.widthAnchor.constraint(equalToConstant: 150).isActive = true
        levelLabel.textColor = .secondaryLabelColor
        let controls = NSStackView(views: [recordButton, timerLabel, NSView(), levelLabel, level])
        controls.spacing = 12
        status.lineBreakMode = .byTruncatingMiddle
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Recording status")
        let takesLabel = NSTextField(labelWithString: "Your takes · drag to the timeline")
        takesLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("take"))
        column.title = "Take"; column.width = 560
        table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 42
        table.dataSource = self; table.delegate = self
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setAccessibilityLabel("Recorded takes")
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        let stack = NSStackView(views: [header, preview, inputs, folderButton, controls, status, takesLabel, scroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The host can restore a window smaller than our preferred size. A scrolling
        // document keeps the whole camera frame and all controls reachable in that case.
        let document = RecorderDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let contentScroll = NSScrollView()
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.hasVerticalScroller = true
        contentScroll.drawsBackground = false
        contentScroll.documentView = document
        document.addSubview(stack)
        view.addSubview(contentScroll)
        NSLayoutConstraint.activate([
            contentScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScroll.topAnchor.constraint(equalTo: view.topAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: contentScroll.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])
        for child in [preview, inputs, controls, scroll] as [NSView] {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        preview.preview.session = session
    }

    private func labelled(_ text: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        restoreFolder()
        discoverDevices()
        runtimeObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.configured = false
            self?.updateControls()
            self?.showError(error?.localizedDescription ?? "The capture session stopped. Check your devices and reopen the recorder.")
        }
        disconnectObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.output.isRecording { self.output.stopRecording() }
            self.configured = false
            self.updateControls()
            self.showError("A capture device was disconnected. Reconnect it and reopen the recorder.")
        }
        requestPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        NSLog("Recorder geometry: view %@ parent %@ window %@", NSStringFromRect(view.frame), NSStringFromRect(view.superview?.bounds ?? .zero), NSStringFromRect(view.window?.contentView?.bounds ?? .zero))
        if let parent = view.superview {
            view.frame = parent.bounds
        }
        shouldStopAfterRecording = false
        if configured { captureQueue.async { [weak self] in self?.session.startRunning() } }
    }

    override func viewWillTransition(to newSize: NSSize) {
        super.viewWillTransition(to: newSize)
        view.setFrameSize(newSize)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        shouldStopAfterRecording = true
        if output.isRecording { output.stopRecording() }
        else { captureQueue.async { [weak self] in self?.session.stopRunning() } }
    }

    deinit {
        timer?.invalidate()
        if let runtimeObserver { NotificationCenter.default.removeObserver(runtimeObserver) }
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
        if scopedFolder { folder?.stopAccessingSecurityScopedResource() }
    }

    private func discoverDevices() {
        videoDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
        audioDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        cameras.removeAllItems(); microphones.removeAllItems()
        cameras.addItems(withTitles: videoDevices.map(\.localizedName))
        microphones.addItems(withTitles: audioDevices.map(\.localizedName))
        let savedCamera = defaults.string(forKey: "cameraID")
        let savedMic = defaults.string(forKey: "microphoneID")
        let cameraIndex = videoDevices.firstIndex { $0.uniqueID == savedCamera }
            ?? videoDevices.firstIndex { $0.deviceType == .external } ?? 0
        let micIndex = audioDevices.firstIndex { $0.uniqueID == savedMic }
            ?? audioDevices.firstIndex { $0.localizedName.localizedCaseInsensitiveContains("Scarlett") }
            ?? audioDevices.firstIndex { $0.deviceType == .external } ?? 0
        if !videoDevices.isEmpty { cameras.selectItem(at: cameraIndex) }
        if !audioDevices.isEmpty { microphones.selectItem(at: micIndex) }
    }

    private func requestPermissions() {
        Task { [weak self] in
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                guard let self else { return }
                guard cameraGranted && microphoneGranted else {
                    self.showError("Allow camera and microphone access in System Settings → Privacy & Security, then reopen the recorder.")
                    return
                }
                self.configureCapture()
            }
        }
    }

    @objc private func changeDevice() { configureCapture() }

    private func configureCapture() {
        guard !busy && !output.isRecording else { return }
        guard videoDevices.indices.contains(cameras.indexOfSelectedItem), audioDevices.indices.contains(microphones.indexOfSelectedItem) else {
            showError("Connect a camera and microphone, then reopen the recorder."); return
        }
        let camera = videoDevices[cameras.indexOfSelectedItem]
        let mic = audioDevices[microphones.indexOfSelectedItem]
        defaults.set(camera.uniqueID, forKey: "cameraID")
        defaults.set(mic.uniqueID, forKey: "microphoneID")
        busy = true; configured = false; updateControls()
        captureQueue.async { [weak self] in
            guard let self else { return }
            var transactionOpen = false
            do {
                self.session.stopRunning()
                self.session.beginConfiguration()
                transactionOpen = true
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }
                let video = try AVCaptureDeviceInput(device: camera)
                let audio = try AVCaptureDeviceInput(device: mic)
                guard self.session.canAddInput(video), self.session.canAddInput(audio) else { throw RecorderError("These devices cannot be used together.") }
                self.session.addInput(video); self.session.addInput(audio)
                if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
                else { self.session.sessionPreset = .high }
                guard self.session.canAddOutput(self.output), self.session.canAddOutput(self.audioMeterOutput) else { throw RecorderError("The selected devices do not support movie recording.") }
                self.session.addOutput(self.output)
                self.audioMeterOutput.setSampleBufferDelegate(self, queue: self.captureQueue)
                self.session.addOutput(self.audioMeterOutput)
                if let videoConnection = self.output.connection(with: .video) {
                    self.output.setOutputSettings([
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000]
                    ], for: videoConnection)
                    if videoConnection.isVideoMirroringSupported { videoConnection.isVideoMirrored = false }
                }
                if let audioConnection = self.output.connection(with: .audio) {
                    self.output.setOutputSettings([
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: 48_000,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderBitRateKey: 192_000
                    ], for: audioConnection)
                }
                self.output.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
                self.output.minFreeDiskSpaceLimit = 1_000_000_000
                // Committing a preset can reset the camera's frame duration. Apply
                // the rate afterwards, so a 30 fps camera does not fall back to 24.
                self.session.commitConfiguration()
                transactionOpen = false
                if !self.shouldStopAfterRecording { self.session.startRunning() }
                try camera.lockForConfiguration()
                if let format = camera.formats.first(where: {
                    let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                    return size.width == 1920 && size.height == 1080 && $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30.1 && $0.maxFrameRate >= 29.9 }
                }) { camera.activeFormat = format }
                if let range = camera.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.minFrameRate <= 30.1 && $0.maxFrameRate >= 29.9 }) {
                    // USB webcams often advertise 30.00003 fps, not exactly 30.
                    // Use their supported duration rather than rejecting that range.
                    let duration = range.minFrameRate > 30 || range.maxFrameRate < 30 ? range.minFrameDuration : CMTime(value: 1, timescale: 30)
                    camera.activeVideoMinFrameDuration = duration
                    camera.activeVideoMaxFrameDuration = duration
                }
                camera.unlockForConfiguration()
                let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
                let fps = Int((1 / CMTimeGetSeconds(camera.activeVideoMinFrameDuration)).rounded())
                DispatchQueue.main.async {
                    self.busy = false; self.configured = true
                    self.status.stringValue = self.folder == nil ? "Choose a recording folder to get started." : "Ready · \(dimensions.width)×\(dimensions.height) · \(fps) fps · mono audio"
                    self.status.textColor = .secondaryLabelColor
                    self.updateControls()
                }
            } catch {
                // Balance the transaction if input/output configuration failed.
                if transactionOpen { self.session.commitConfiguration() }
                DispatchQueue.main.async { self.busy = false; self.showError(error.localizedDescription); self.updateControls() }
            }
        }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Use for recording"
        panel.message = "Choose a folder on your SSD. New recordings will be written directly here."
        panel.directoryURL = folder ?? URL(fileURLWithPath: "/Volumes", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if scopedFolder { folder?.stopAccessingSecurityScopedResource() }
            folder = url; scopedFolder = url.startAccessingSecurityScopedResource()
            defaults.set(bookmark, forKey: "folderBookmark")
            defaults.set(url.lastPathComponent, forKey: "folderName")
            folderButton.title = "Save to: \(url.lastPathComponent) · Change…"
            folderButton.toolTip = url.path
            status.stringValue = "Ready · recordings go directly to \(url.lastPathComponent)"
            status.textColor = .secondaryLabelColor
            loadTakes(); updateControls()
        } catch { showError("Could not remember this folder: \(error.localizedDescription)") }
    }

    private func restoreFolder() {
        guard let data = defaults.data(forKey: "folderBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            scopedFolder = url.startAccessingSecurityScopedResource()
            folder = url
            if stale { defaults.set(try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "folderBookmark") }
            folderButton.title = "Save to: \(url.lastPathComponent) · Change…"
            folderButton.toolTip = url.path
            loadTakes()
        } catch { showError("Choose your recording folder again. The previous destination is unavailable.") }
    }

    @objc private func toggleRecording() {
        if output.isRecording {
            busy = true; recordButton.title = "Finishing…"; updateControls()
            output.stopRecording(); return
        }
        guard configured, !busy, let folder else { return }
        do {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .volumeAvailableCapacityForImportantUsageKey])
            guard values.isDirectory == true, FileManager.default.isWritableFile(atPath: folder.path) else { throw RecorderError("Your recording folder is unavailable. Connect your SSD or choose another folder.") }
            if let available = values.volumeAvailableCapacityForImportantUsage, available < 2_000_000_000 {
                throw RecorderError("Less than 2 GB is available on your recording drive. Choose a folder with more space.")
            }
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let name = "Take \(formatter.string(from: Date())) \(UUID().uuidString.prefix(4))"
            let url = folder.appendingPathComponent(name).appendingPathExtension("mov")
            busy = true; updateControls()
            output.startRecording(to: url, recordingDelegate: self)
            status.stringValue = "Starting recording…"
        } catch { showError(error.localizedDescription) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.busy = false; self.startedAt = Date()
            self.recordButton.title = "■ Stop"; self.recordButton.setAccessibilityLabel("Stop recording")
            self.status.stringValue = "Recording directly to \(fileURL.deletingLastPathComponent().lastPathComponent)"
            self.status.textColor = .systemRed
            self.updateControls()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.busy = false; self.startedAt = nil
            self.recordButton.title = "● Record"; self.recordButton.setAccessibilityLabel("Record")
            let nsError = error as NSError?
            let successfullyFinished = nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            if let error, !successfullyFinished { self.showError("Recording stopped: \(error.localizedDescription). Any saved media remains in your recording folder.") }
            else { self.status.stringValue = "Saved. Drag your take onto the timeline."; self.status.textColor = .secondaryLabelColor }
            self.loadTakes(); self.updateControls()
            if self.shouldStopAfterRecording { self.captureQueue.async { self.session.stopRunning() } }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastLevelUpdate) > 0.1 else { return }
        lastLevelUpdate = Date()
        let power = connection.audioChannels.map(\.averagePowerLevel).max() ?? -60
        DispatchQueue.main.async { self.level.doubleValue = Double(max(0, min(60, power + 60))) }
    }

    private func tick() {
        if let startedAt {
            let seconds = Int(Date().timeIntervalSince(startedAt))
            timerLabel.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        } else { timerLabel.stringValue = "00:00" }
    }

    private func updateControls() {
        recordButton.isEnabled = !busy && configured && folder != nil
        let mayChange = !busy && !output.isRecording
        cameras.isEnabled = mayChange; microphones.isEnabled = mayChange; folderButton.isEnabled = mayChange
    }

    private func showError(_ message: String) { status.stringValue = message; status.textColor = .systemOrange; status.toolTip = message }

    private func loadTakes() {
        guard let folder else { return }
        do {
            table.files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
                .filter { $0.lastPathComponent.hasPrefix("Take ") && $0.pathExtension.lowercased() == "mov" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            table.reloadData()
        } catch { showError("Cannot read the recording folder. Reconnect your drive or choose the folder again.") }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { table.files.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = NSTextField(labelWithString: "▶  " + table.files[row].deletingPathExtension().lastPathComponent)
        text.font = .systemFont(ofSize: 13)
        text.toolTip = "Drag this take onto Final Cut Pro’s browser or timeline."
        return text
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        // File URLs are supported directly by Final Cut Pro and preserve the original media.
        table.files[row] as NSURL
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
}

struct RecorderError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
