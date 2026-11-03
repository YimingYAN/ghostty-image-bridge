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
    a.messageText = "Ghostty File Bridge"
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
func pasteFiles(_ originalEvent: CGEvent) {
    guard !busy else { return }
    busy = true
    do {
        let (id, pid) = try context()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", pid, "-o", "comm="]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let command = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        let program = URL(fileURLWithPath: command.trimmingCharacters(in: .whitespacesAndNewlines)).lastPathComponent
        if !["ssh", "mosh", "mosh-client"].contains(program) {
            // Replay the original shortcut so Ghostty handles local file paths natively.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.mitchellh.ghostty",
               let current = try? context(), current == (id, pid) {
                originalEvent.setIntegerValueField(.eventSourceUserData, value: 0x474642)
                originalEvent.post(tap: .cghidEventTap)
            }
            busy = false
            return
        }
        let pb = NSPasteboard.general
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []).filter { $0.isFileURL }
        var temporaryFile: URL?
        let arguments: [String]
        if !urls.isEmpty {
            arguments = [root + "/transfer.py", "--files", id, pid] + urls.map { $0.path }
        } else {
            let img = NSImage(pasteboard: pb)
            guard let tiff = img?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
                busy = false; alert("The clipboard image could not be read."); return
            }
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ghostty-image-" + UUID().uuidString + ".png")
            temporaryFile = file
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            arguments = [root + "/transfer.py", file.path, id, pid]
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/python3.13")
        task.arguments = arguments
        let errors = Pipe()
        task.standardError = errors
        task.terminationHandler = { p in
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Upload failed"
            DispatchQueue.main.async {
                busy = false
                if p.terminationStatus != 0 { alert(message) }
            }
        }
        do {
            try task.run()
        } catch {
            if let file = temporaryFile { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    } catch { busy = false; alert(error.localizedDescription) }
}
func callback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == 0x474642 { return Unmanaged.passUnretained(event) }
    let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9,
          modifiers == .maskCommand,
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.mitchellh.ghostty" else {
        return Unmanaged.passUnretained(event)
    }
    let pb = NSPasteboard.general
    let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
    let hasFiles = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    guard hasImage || hasFiles else { return Unmanaged.passUnretained(event) }
    guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
    DispatchQueue.main.async { pasteFiles(copy) }
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
menu.addItem(withTitle: "Ghostty File Bridge", action: nil, keyEquivalent: "")
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
