import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let item = NSMenuItem()
        appMenu.addItem(item)
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Final Cut Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        NSApp.mainMenu = appMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Final Cut Recorder"
        let title = NSTextField(labelWithString: "Record. Drop. Edit.")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "Your recorder lives in Final Cut Pro.\n\nOpen Window → Extensions → Final Cut Recorder. Choose a recording folder once, then record and drag your take onto the timeline.")
        let button = NSButton(title: "Open Final Cut Pro", target: self, action: #selector(openFinalCut))
        button.bezelStyle = .rounded
        let stack = NSStackView(views: [title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openFinalCut() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FinalCut") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
