import AppKit
import ApplicationServices

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var tap: CFMachPort?
var busy = false
var statusItem: NSStatusItem!
let root = NSHomeDirectory() + "/Projects/ghostty-image-bridge"

func alert(_ text: String) {
    let a = NSAlert()
    a.messageText = "Ghostty Image Bridge"
    a.informativeText = text
    a.runModal()
}
func context() throws -> (String, String) {
    let source = "tell application \"Ghostty\"\nset t to focused terminal of selected tab of front window\nreturn (id of t) & \"|\" & (pid of t as text)\nend tell"
    var error: NSDictionary?
    let result = NSAppleScript(source: source)!.executeAndReturnError(&error)
    guard error == nil, let value = result.stringValue else {
        throw NSError(domain: "Bridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow Ghostty Image Bridge to control Ghostty in System Settings → Privacy & Security → Automation."])
    }
    let fields = value.components(separatedBy: "|")
    guard fields.count == 2 else { throw NSError(domain: "Bridge", code: 2) }
    return (fields[0], fields[1])
}
func pasteImage() {
    guard !busy else { return }
    busy = true
    do {
        let (id, pid) = try context()
        let pb = NSPasteboard.general
        var img = NSImage(pasteboard: pb)
        if img == nil, let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first, url.isFileURL {
            img = NSImage(contentsOf: url)
        }
        guard let tiff = img?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            busy = false; alert("The clipboard image could not be read."); return
        }
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ghostty-image-" + UUID().uuidString + ".png")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/python3.13")
        task.arguments = [root + "/transfer.py", file.path, id, pid]
        let errors = Pipe()
        task.standardError = errors
        task.terminationHandler = { p in
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Upload failed"
            DispatchQueue.main.async {
                busy = false
                if p.terminationStatus != 0 { alert(message) }
            }
        }
        try task.run()
    } catch { busy = false; alert(error.localizedDescription) }
}
func callback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9,
          modifiers == .maskCommand,
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.mitchellh.ghostty" else {
        return Unmanaged.passUnretained(event)
    }
    let pb = NSPasteboard.general
    let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
    guard hasImage else { return Unmanaged.passUnretained(event) }
    DispatchQueue.main.async { pasteImage() }
    return nil
}
func enable() {
    guard tap == nil else { return }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else { return }
    tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: callback, userInfo: nil)
    if let t = tap {
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        statusItem.button?.title = "⇧▧"
    }
}
class Actions: NSObject {
    @objc func permissions() { enable() }
    @objc func quit() { app.terminate(nil) }
}
let actions = Actions()
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "▧!"
let menu = NSMenu()
menu.addItem(withTitle: "Ghostty Image Bridge", action: nil, keyEquivalent: "")
let permissionItem = menu.addItem(withTitle: "Enable / Check Permissions", action: #selector(Actions.permissions), keyEquivalent: "")
permissionItem.target = actions
let quitItem = menu.addItem(withTitle: "Quit", action: #selector(Actions.quit), keyEquivalent: "q")
quitItem.target = actions
statusItem.menu = menu
enable()
Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    if AXIsProcessTrusted() { enable() }
}
app.run()
