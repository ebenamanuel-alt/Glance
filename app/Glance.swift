//  Glance
//  Look at a screen and your cursor and typing go there, using the head tracking in your AirPods.
//
//  1. Cursor follows your eyes   look at a screen and the cursor jumps there
//  2. Nod to focus               hold Control + Option and nod: the window under the cursor comes to the front
//  3. Throw a window             hold Control + Option + Command and look at another screen: the front window moves there
//  5. Spotlight                  screens you aren't looking at dim slightly
//  7. Privacy                    look away (or take your AirPods out) and your screens are hidden until you look back

import SwiftUI
import AppKit
import CoreMotion
import ApplicationServices

// MARK: - Helpers

func wrapAngle(_ d: Double) -> Double {
    var a = (d + 180).truncatingRemainder(dividingBy: 360)
    if a < 0 { a += 360 }
    return a - 180
}

/// Height of the main (menu bar) screen. AppKit measures from the bottom left, the window system from the top left.
@MainActor private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
@MainActor func toQuartz(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
@MainActor func toQuartz(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }

enum Pref {
    static func double(_ key: String, _ fallback: Double) -> Double { (UserDefaults.standard.object(forKey: key) as? Double) ?? fallback }
    static func bool(_ key: String, _ fallback: Bool) -> Bool { (UserDefaults.standard.object(forKey: key) as? Bool) ?? fallback }
    static func set(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
}

/// Default settings, and "Reset to defaults" puts these back.
enum Setting {
    static let doubles: [String: Double] = [
        "dwell": 0.35, "tolerance": 25, "nodSize": 5, "spotlightStrength": 0.45,
        "awaySeconds": 10, "privacyStrength": 0.85,
    ]
    static let bools: [String: Bool] = [
        "isOn": true, "followCursor": true, "autoSwitch": true, "rememberPosition": true,
        "focusOnSwitch": true, "nodEnabled": true, "throwEnabled": true, "spotlight": true,
        "privacy": true, "privacyWhenOut": false, "sleepDisplay": false, "gammaDim": true,
    ]
    static func d(_ key: String) -> Double { Pref.double(key, doubles[key] ?? 0) }
    static func b(_ key: String) -> Bool { Pref.bool(key, bools[key] ?? false) }
}

struct ScreenInfo: Identifiable, Equatable {
    let key: String
    let name: String
    let frame: CGRect          // AppKit coordinates
    let quartzFrame: CGRect    // window-system coordinates (top left origin)
    let quartzVisible: CGRect  // the same, without the menu bar and Dock
    let displayID: CGDirectDisplayID
    var id: String { key }

    @MainActor static func all() -> [ScreenInfo] {
        var seen: [String: Int] = [:]
        return NSScreen.screens.map { s in
            let base = "\(s.localizedName) \(Int(s.frame.width))x\(Int(s.frame.height))"
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return ScreenInfo(key: n > 1 ? "\(base) #\(n)" : base, name: s.localizedName,
                              frame: s.frame, quartzFrame: toQuartz(s.frame), quartzVisible: toQuartz(s.visibleFrame),
                              displayID: (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
        }
    }
}

/// Where a screen is, measured from where you face when you press Recentre.
struct Direction: Codable, Equatable {
    var yaw: Double     // turning left and right
    var pitch: Double   // looking up and down
}

// MARK: - Nod detection

struct NodDetector {
    var degrees = 5.0
    private var samples: [(t: Double, p: Double, y: Double)] = []
    private var cooldownUntil = 0.0
    private let hysteresis = 3.0

    mutating func reset() { samples.removeAll() }

    /// True when a small down-and-back-up nod has just finished.
    mutating func feed(t: Double, pitch: Double, yaw: Double) -> Bool {
        samples.append((t, pitch, yaw))
        samples.removeAll { t - $0.t > 1.0 }
        guard t >= cooldownUntil, samples.count >= 8, t - samples[0].t >= 0.25 else { return false }
        let p0 = samples[0].p, y0 = samples[0].y
        let ps = samples.map { $0.p }
        let ys = samples.map { wrapAngle($0.y - y0) }
        let yawRange = (ys.max() ?? 0) - (ys.min() ?? 0)
        let dip = ps.map { abs($0 - p0) }.max() ?? 0
        guard reversals(ps) >= 1, dip >= degrees,
              abs(ps[ps.count - 1] - p0) <= max(3, degrees * 0.6),
              yawRange <= max(6, dip) else { return false }
        cooldownUntil = t + 1.0
        samples.removeAll()
        return true
    }

    private func reversals(_ v: [Double]) -> Int {
        guard var ext = v.first else { return 0 }
        var dir = 0, count = 0
        for x in v.dropFirst() {
            switch dir {
            case 0:
                if x - ext > hysteresis { dir = 1; ext = x } else if ext - x > hysteresis { dir = -1; ext = x }
            case 1:
                if x > ext { ext = x } else if ext - x > hysteresis { dir = -1; ext = x; count += 1 }
            default:
                if x < ext { ext = x } else if x - ext > hysteresis { dir = 1; ext = x; count += 1 }
            }
        }
        return count
    }
}

// MARK: - Controller

@MainActor
final class Glance: ObservableObject {
    // Live state
    @Published var airpods = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var screens: [ScreenInfo] = []
    @Published var directions: [String: Direction] = [:] { didSet { saveDirections() } }
    @Published var yaw = 0.0
    @Published var pitch = 0.0
    @Published var facing: String?          // the screen you're looking at
    @Published var activeScreen: String?    // the screen the spotlight is on
    @Published var listening = false        // Control + Option held
    @Published var hidden = false           // privacy cover showing
    @Published var hasRecentred = false
    @Published var message = "Put in your AirPods, face your main screen and press Recentre."

    // Settings, remembered between launches
    @Published var isOn = Setting.b("isOn") { didSet { Pref.set(isOn, "isOn"); if !isOn { setCover(false) }; updateDim() } }
    @Published var followCursor = Setting.b("followCursor") { didSet { Pref.set(followCursor, "followCursor") } }
    @Published var autoSwitch = Setting.b("autoSwitch") { didSet { Pref.set(autoSwitch, "autoSwitch") } }
    @Published var dwell = Setting.d("dwell") { didSet { Pref.set(dwell, "dwell") } }
    @Published var tolerance = Setting.d("tolerance") { didSet { Pref.set(tolerance, "tolerance") } }
    @Published var rememberPosition = Setting.b("rememberPosition") { didSet { Pref.set(rememberPosition, "rememberPosition") } }
    @Published var focusOnSwitch = Setting.b("focusOnSwitch") { didSet { Pref.set(focusOnSwitch, "focusOnSwitch") } }
    @Published var nodEnabled = Setting.b("nodEnabled") { didSet { Pref.set(nodEnabled, "nodEnabled") } }
    @Published var nodSize = Setting.d("nodSize") { didSet { Pref.set(nodSize, "nodSize"); nod.degrees = nodSize } }
    @Published var throwEnabled = Setting.b("throwEnabled") { didSet { Pref.set(throwEnabled, "throwEnabled") } }
    @Published var spotlight = Setting.b("spotlight") { didSet { Pref.set(spotlight, "spotlight"); updateDim() } }
    @Published var spotlightStrength = Setting.d("spotlightStrength") { didSet { Pref.set(spotlightStrength, "spotlightStrength"); updateDim() } }
    @Published var privacy = Setting.b("privacy") { didSet { Pref.set(privacy, "privacy"); if !privacy { setCover(false) } } }
    @Published var awaySeconds = Setting.d("awaySeconds") { didSet { Pref.set(awaySeconds, "awaySeconds") } }
    @Published var privacyStrength = Setting.d("privacyStrength") { didSet { Pref.set(privacyStrength, "privacyStrength"); buildOverlays() } }
    @Published var privacyWhenOut = Setting.b("privacyWhenOut") { didSet { Pref.set(privacyWhenOut, "privacyWhenOut") } }
    @Published var sleepDisplay = Setting.b("sleepDisplay") { didSet { Pref.set(sleepDisplay, "sleepDisplay") } }
    /// true: dim by darkening the screen's colours (works on external monitors). false: a dark see-through layer.
    @Published var gammaDim = Setting.b("gammaDim") {
        didSet {
            Pref.set(gammaDim, "gammaDim")
            for s in screens { setGamma(s.key, 0) }
            for w in dimWindows.values { setDim(w, 0) }
            updateDim()
        }
    }

    // Internal state
    private let motion = CMHeadphoneMotionManager()
    private var nod = NodDetector()
    private var rawYaw = 0.0, rawPitch = 0.0
    private var centreYaw = 0.0, centrePitch = 0.0
    private var started = false
    private var lastDraw = 0.0
    private var candidate: String?
    private var candidateSince = 0.0
    private var handled: String?
    private var cursorMemory: [String: CGPoint] = [:]
    private var lastMotion = Date.distantPast
    private var everHadMotion = false
    private var awaySince: Date?
    private var snoozed = false
    private var slept = false
    private var dimWindows: [String: NSWindow] = [:]
    private var coverWindows: [String: NSWindow] = [:]
    private var timer: Timer?

    func start() {
        guard !started else { return }
        started = true
        CGDisplayRestoreColorSyncSettings()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in
            CGDisplayRestoreColorSyncSettings()   // always put normal colours back when Glance quits
        }
        screens = ScreenInfo.all()
        nod.degrees = nodSize
        loadDirections()
        if motion.isDeviceMotionAvailable {
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                MainActor.assumeIsolated { self.handle(data) }
            }
        } else {
            message = "This Mac can't read AirPods motion. It needs macOS 14 or later."
        }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        buildOverlays()
    }

    // MARK: Head movement

    private func handle(_ m: CMDeviceMotion) {
        lastMotion = Date()
        everHadMotion = true
        snoozed = false
        if !airpods { airpods = true }
        rawYaw = m.attitude.yaw * 180 / .pi
        rawPitch = m.attitude.pitch * 180 / .pi
        let y = wrapAngle(rawYaw - centreYaw)
        let p = rawPitch - centrePitch
        if m.timestamp - lastDraw >= 1.0 / 30 { yaw = y; pitch = p; lastDraw = m.timestamp }

        // Directions only mean something once you've recentred in this session
        guard isOn, hasRecentred else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let held = flags.contains(.maskControl) && flags.contains(.maskAlternate)
        let throwing = held && flags.contains(.maskCommand)
        if held != listening { listening = held }

        updateFacing(y, p)

        if held && nodEnabled && !throwing {
            if nod.feed(t: m.timestamp, pitch: p, yaw: y) { nodFocus() }
        } else {
            nod.reset()
        }
        decide(t: m.timestamp, held: held, throwing: throwing)
    }

    private func distance(_ d: Direction, _ y: Double, _ p: Double) -> Double {
        let dy = wrapAngle(y - d.yaw), dp = p - d.pitch
        return (dy * dy + dp * dp).squareRoot()
    }

    private func updateFacing(_ y: Double, _ p: Double) {
        let known = screens.compactMap { s in directions[s.key].map { (s.key, distance($0, y, p)) } }
        // The spotlight follows whichever screen you're closest to, even slightly outside the aim circle,
        // so looking down at a laptop still counts.
        if let near = known.min(by: { $0.1 < $1.1 }), near.1 <= tolerance * 1.8 {
            if near.0 != spotCandidate { spotCandidate = near.0; spotSince = Date() }
            if activeScreen != near.0, Date().timeIntervalSince(spotSince) >= max(0.2, dwell) {
                activeScreen = near.0
                updateDim()
            }
        }
        guard let best = known.min(by: { $0.1 < $1.1 }), best.1 <= tolerance else {
            if facing != nil { facing = nil }
            return
        }
        var pick = best.0
        // Near the edge between two screens, stay on the current one so it doesn't flicker
        if let cur = facing, cur != best.0,
           let curDist = known.first(where: { $0.0 == cur })?.1,
           curDist <= tolerance, best.1 > curDist - 3 {
            pick = cur
        }
        if facing != pick { facing = pick }
    }

    /// Acts once each time you settle on a different screen.
    private func decide(t: Double, held: Bool, throwing: Bool) {
        guard let target = facing else { candidate = nil; handled = nil; return }
        if target != candidate { candidate = target; candidateSince = t; handled = nil }
        let looked = t - candidateSince

        if looked >= dwell, activeScreen != target {
            activeScreen = target
            updateDim()
        }
        guard handled != target, NSEvent.pressedMouseButtons == 0 else { return }

        if throwing {
            guard throwEnabled, looked >= 0.15 else { return }
            handled = target
            throwWindow(to: target)
            return
        }
        guard followCursor else { return }
        if autoSwitch {
            guard looked >= dwell else { return }
        } else {
            guard held, looked >= 0.1 else { return }
        }
        handled = target
        switchTo(target)
    }

    // MARK: 1. Cursor follows your eyes

    private func cursorQuartz() -> CGPoint { toQuartz(NSEvent.mouseLocation) }
    private func screenKey(at p: CGPoint) -> String? { screens.first { $0.quartzFrame.contains(p) }?.key }

    private func switchTo(_ key: String) {
        guard let s = screens.first(where: { $0.key == key }) else { return }
        let cursor = cursorQuartz()
        if let from = screenKey(at: cursor) {
            if from == key { return }
            cursorMemory[from] = cursor
        }
        var dest = CGPoint(x: s.quartzFrame.midX, y: s.quartzFrame.midY)
        if rememberPosition, let saved = cursorMemory[key], s.quartzFrame.contains(saved) { dest = saved }
        CGWarpMouseCursorPosition(dest)
        CGAssociateMouseAndMouseCursorPosition(1)
        if focusOnSwitch { focusWindow(at: dest, on: s) }
        message = "Moved to \(s.name)."
    }

    // MARK: 2. Nod to focus

    private func nodFocus() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        let cursor = cursorQuartz()
        if let f = facing, screenKey(at: cursor) != f, let s = screens.first(where: { $0.key == f }) {
            // You nodded at a different screen from the cursor: go there and focus it
            let saveFocus = focusOnSwitch
            switchTo(f)
            if !saveFocus { focusWindow(at: cursorQuartz(), on: s) }
            handled = f
            message = "Nod: focused \(s.name)."
            return
        }
        if focusWindow(at: cursor, on: screens.first { $0.quartzFrame.contains(cursor) }) {
            message = "Nod: brought that window to the front."
        } else {
            message = "Nod: no window there."
        }
    }

    // MARK: Windows

    private struct WinInfo { let pid: pid_t; let bounds: CGRect }

    /// Normal app windows on screen, front to back.
    private func visibleWindows() -> [WinInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  r.width > 80, r.height > 60 else { return nil }
            return WinInfo(pid: pid, bounds: r)
        }
    }

    @discardableResult
    private func focusWindow(at p: CGPoint, on s: ScreenInfo?) -> Bool {
        let wins = visibleWindows()
        let target = wins.first(where: { $0.bounds.contains(p) })
            ?? s.flatMap { scr in wins.first(where: { $0.bounds.intersects(scr.quartzFrame) }) }
        guard let w = target else { return false }
        raiseWindow(pid: w.pid, bounds: w.bounds)
        return true
    }

    private func raiseWindow(pid: pid_t, bounds: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let match = axWindows(app).first { el in
            guard let f = frame(of: el) else { return false }
            return abs(f.minX - bounds.minX) < 4 && abs(f.minY - bounds.minY) < 4 && abs(f.width - bounds.width) < 4
        }
        if let win = match {
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    private func axWindows(_ app: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let list = v as? [AXUIElement] else { return [] }
        return list
    }

    private func frame(of el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?
        var sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success,
              let pRef = pv, let sRef = sv,
              CFGetTypeID(pRef) == AXValueGetTypeID(), CFGetTypeID(sRef) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pRef as! AXValue, .cgPoint, &p)
        AXValueGetValue(sRef as! AXValue, .cgSize, &size)
        return CGRect(origin: p, size: size)
    }

    private func setFrame(_ el: AXUIElement, _ r: CGRect) {
        var origin = r.origin
        var size = r.size
        if let pv = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv) }
    }

    // MARK: 3. Throw a window to another screen

    private func throwWindow(to key: String) {
        guard let dest = screens.first(where: { $0.key == key }),
              let front = NSWorkspace.shared.frontmostApplication else { return }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &v) == .success,
              let ref = v, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            message = "No window to move. Click a window first."
            return
        }
        let win = ref as! AXUIElement
        guard let f = frame(of: win) else { return }
        let centre = CGPoint(x: f.midX, y: f.midY)
        guard let from = screens.first(where: { $0.quartzFrame.contains(centre) }), from.key != dest.key else { return }

        // Keep the window in the same relative spot, shrinking it if the new screen is smaller
        let a = from.quartzVisible, b = dest.quartzVisible
        let w = min(f.width, b.width), h = min(f.height, b.height)
        let rx = a.width > f.width ? (f.minX - a.minX) / (a.width - f.width) : 0.5
        let ry = a.height > f.height ? (f.minY - a.minY) / (a.height - f.height) : 0.5
        let x = b.minX + max(0, min(1, rx)) * (b.width - w)
        let y = b.minY + max(0, min(1, ry)) * (b.height - h)
        let moved = CGRect(x: x, y: y, width: w, height: h)
        setFrame(win, moved)

        CGWarpMouseCursorPosition(CGPoint(x: moved.midX, y: moved.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        message = "Moved \(front.localizedName ?? "the window") to \(dest.name)."
    }

    // MARK: 5. Spotlight and 7. Privacy cover

    private func makeOverlay(for s: ScreenInfo, level: NSWindow.Level) -> NSWindow {
        // Create the window on that exact display, so macOS doesn't move it to the main screen
        let screen = NSScreen.screens.first { $0.frame == s.frame }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: s.frame.size), styleMask: .borderless,
                         backing: .buffered, defer: false, screen: screen)
        w.setFrame(s.frame, display: true)
        w.isMovable = false
        w.canHide = false
        w.hidesOnDeactivate = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = level
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.alphaValue = 0
        return w
    }

    private func coverView(size: CGSize) -> NSView {
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let tint = NSView(frame: blur.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(privacyStrength).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)
        let label = NSTextField(labelWithString: "Hidden by Glance. Look back at your screen to show it.")
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        label.frame.origin = CGPoint(x: (size.width - label.frame.width) / 2, y: (size.height - label.frame.height) / 2)
        label.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        blur.addSubview(label)
        return blur
    }

    func buildOverlays() {
        guard started else { return }
        for w in dimWindows.values { w.orderOut(nil) }
        for w in coverWindows.values { w.orderOut(nil) }
        dimWindows = [:]
        coverWindows = [:]
        for s in screens {
            let dim = makeOverlay(for: s, level: .screenSaver)
            let black = NSView(frame: NSRect(origin: .zero, size: s.frame.size))
            black.wantsLayer = true
            black.layer?.backgroundColor = NSColor.black.cgColor
            dim.contentView = black
            dim.orderFrontRegardless()
            dimWindows[s.key] = dim

            let cover = makeOverlay(for: s, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
            cover.contentView = coverView(size: s.frame.size)
            cover.alphaValue = hidden ? 1 : 0
            cover.orderFrontRegardless()
            coverWindows[s.key] = cover
        }
        updateDim()
    }

    private var testingDim = false
    private var testEndsAt = Date.distantPast
    private var spotCandidate: String?
    private var spotSince = Date.distantPast

    private func spotTarget(_ key: String) -> CGFloat {
        let on = isOn && spotlight && screens.count > 1 && activeScreen != nil && key != activeScreen && !hidden
        return on ? spotlightStrength : 0
    }

    /// How dark a screen's colours should be: the privacy cover wins over the spotlight.
    private func colourTarget(_ key: String) -> Double {
        if hidden { return max(0.85, privacyStrength) }
        return gammaDim ? Double(spotTarget(key)) : 0
    }

    private func updateDim() {
        guard !testingDim else { return }
        for s in screens { dimScreen(s.key, spotTarget(s.key)) }
    }

    /// Dims one screen using whichever method is chosen in settings.
    private func dimScreen(_ key: String, _ target: CGFloat) {
        if gammaDim {
            setGamma(key, hidden ? colourTarget(key) : Double(target))
            if let w = dimWindows[key], w.alphaValue > 0 { setDim(w, 0) }
        } else {
            // The privacy cover also darkens colours, so it works on monitors where the layer doesn't show
            setGamma(key, hidden ? colourTarget(key) : 0)
            if let w = dimWindows[key] { setDim(w, target) }
        }
    }

    // MARK: Colour dimming
    // Turns down the colours the Mac sends to a display. Works on external monitors too,
    // because it changes the picture itself rather than drawing a window on top.

    private var gammaNow: [String: Double] = [:]
    private var gammaGoal: [String: Double] = [:]
    private var fadeTimer: Timer?

    private func setGamma(_ key: String, _ target: Double) {
        gammaGoal[key] = target
        if (gammaNow[key] ?? 0) == target { return }
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeStep() }
        }
    }

    private func fadeStep() {
        var moving = false
        for (key, goal) in gammaGoal {
            let now = gammaNow[key] ?? 0
            guard now != goal else { continue }
            let next = abs(goal - now) <= 0.04 ? goal : now + (goal > now ? 0.04 : -0.04)
            gammaNow[key] = next
            applyGamma(key, next)
            if next != goal { moving = true }
        }
        if !moving {
            fadeTimer?.invalidate()
            fadeTimer = nil
            if gammaNow.values.allSatisfy({ $0 == 0 }) { CGDisplayRestoreColorSyncSettings() }
        }
    }

    private func applyGamma(_ key: String, _ amount: Double) {
        guard let s = screens.first(where: { $0.key == key }), s.displayID != 0 else { return }
        // The spotlight never goes below 15% so you can still see; the privacy cover can go fully dark
        let top = CGGammaValue(max(hidden ? 0 : 0.15, 1 - amount))
        CGSetDisplayTransferByFormula(s.displayID, 0, top, 1, 0, top, 1, 0, top, 1)
    }

    /// Four times a second, makes sure each screen's dim layer is really showing as it should.
    /// macOS sometimes hides or moves these layers when apps switch or Spaces change.
    private func enforceDim() {
        guard !testingDim else { return }
        if gammaDim || hidden {
            // Night Shift or True Tone can reset the colours, so put the dimming back
            for s in screens {
                let target = colourTarget(s.key)
                if gammaGoal[s.key] != target { setGamma(s.key, target) }
                else if fadeTimer == nil, let now = gammaNow[s.key], now > 0 { applyGamma(s.key, now) }
            }
            return
        }
        for (key, w) in dimWindows {
            let on = isOn && spotlight && screens.count > 1 && activeScreen != nil && key != activeScreen && !hidden
            let target: CGFloat = on ? spotlightStrength : 0
            if target > 0 {
                if let s = screens.first(where: { $0.key == key }), w.frame != s.frame { w.setFrame(s.frame, display: true) }
                if !w.isVisible || !w.isOnActiveSpace { w.orderFrontRegardless() }
                if abs(w.alphaValue - target) > 0.05 { setDim(w, target) }
            } else if w.alphaValue > 0.05 {
                setDim(w, 0)
            }
        }
    }

    private func setDim(_ w: NSWindow, _ target: CGFloat) {
        if target > 0 {
            // Make sure it's really on that screen and on top, even after display or Space changes
            if let key = dimWindows.first(where: { $0.value === w })?.key,
               let s = screens.first(where: { $0.key == key }), w.frame != s.frame {
                w.setFrame(s.frame, display: true)
            }
            w.orderFrontRegardless()
        }
        guard abs(w.alphaValue - target) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.allowsImplicitAnimation = true
            w.animator().alphaValue = target
        } completionHandler: {
            // If the animation didn't apply, set it directly
            MainActor.assumeIsolated { if abs(w.alphaValue - target) > 0.01 { w.alphaValue = target } }
        }
    }

    /// Dims every screen except the one with the cursor for two seconds, to check spotlight works.
    func testDim() {
        if dimWindows.isEmpty { buildOverlays() }
        let cursor = toQuartz(NSEvent.mouseLocation)
        let keep = screens.first { $0.quartzFrame.contains(cursor) }?.key
        testingDim = true
        testEndsAt = Date().addingTimeInterval(2)
        for s in screens { dimScreen(s.key, s.key == keep ? 0 : max(0.4, spotlightStrength)) }
        message = screens.count > 1
            ? "Testing: every screen except this one should go darker for 2 seconds."
            : "Only one screen found. Spotlight needs two or more."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.testingDim = false
                self.updateDim()
            }
        }
    }

    private func setCover(_ on: Bool) {
        guard on != hidden else { return }
        hidden = on
        for w in coverWindows.values {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = on ? 0.4 : 0.2
                w.animator().alphaValue = on ? 1 : 0
            }
        }
        updateDim()
    }

    private func sleepScreens() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    /// Runs four times a second: checks permissions and whether you've looked away.
    private func tick() {
        if testingDim, Date() >= testEndsAt.addingTimeInterval(0.5) { testingDim = false }
        enforceDim()
        let t = AXIsProcessTrusted()
        if t != trusted { trusted = t }
        let live = Date().timeIntervalSince(lastMotion) < 2
        if live != airpods { airpods = live }

        guard isOn, privacy else {
            awaySince = nil; slept = false
            if hidden { setCover(false) }
            return
        }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if flags.contains(.maskControl) && flags.contains(.maskAlternate) {
            // Holding Control + Option always shows the screens again
            if hidden { setCover(false); if !live { snoozed = true } }
            awaySince = nil; slept = false
            return
        }
        let away: Bool
        if live {
            away = facing == nil && !directions.isEmpty && hasRecentred
        } else {
            away = privacyWhenOut && everHadMotion && !snoozed
        }
        guard away else {
            awaySince = nil; slept = false
            if hidden { setCover(false) }
            return
        }
        if awaySince == nil { awaySince = Date() }
        guard let since = awaySince, Date().timeIntervalSince(since) >= awaySeconds else { return }
        if sleepDisplay {
            if !slept { slept = true; sleepScreens() }
        } else if !hidden {
            setCover(true)
        }
    }

    // MARK: Setup actions

    func recentre() {
        centreYaw = rawYaw
        centrePitch = rawPitch
        yaw = 0; pitch = 0
        hasRecentred = true
        candidate = nil; handled = nil
        message = directions.isEmpty
            ? "Centred. Now look at each screen and press Save direction next to it."
            : "Centred. Your saved screens are ready."
    }

    func save(_ s: ScreenInfo) {
        directions[s.key] = Direction(yaw: yaw, pitch: pitch)
        hasRecentred = true
        message = "Saved \(s.name). Look at it and the cursor will go there."
    }

    func forget(_ s: ScreenInfo) {
        directions[s.key] = nil
    }

    /// Shows a big label on a screen, so you know which one is which.
    func identify(_ s: ScreenInfo) {
        let w = makeOverlay(for: s, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2))
        let host = NSHostingView(rootView: IdentifyBadge(name: s.name))
        host.frame = NSRect(origin: .zero, size: s.frame.size)
        w.contentView = host
        w.alphaValue = 1
        w.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { w.orderOut(nil) }
    }

    func resetSettings() {
        for (k, v) in Setting.doubles { UserDefaults.standard.set(v, forKey: k) }
        for (k, v) in Setting.bools { UserDefaults.standard.set(v, forKey: k) }
        isOn = Setting.b("isOn"); followCursor = Setting.b("followCursor"); autoSwitch = Setting.b("autoSwitch")
        dwell = Setting.d("dwell"); tolerance = Setting.d("tolerance"); rememberPosition = Setting.b("rememberPosition")
        focusOnSwitch = Setting.b("focusOnSwitch"); nodEnabled = Setting.b("nodEnabled"); nodSize = Setting.d("nodSize")
        throwEnabled = Setting.b("throwEnabled"); spotlight = Setting.b("spotlight")
        spotlightStrength = Setting.d("spotlightStrength"); privacy = Setting.b("privacy")
        awaySeconds = Setting.d("awaySeconds"); privacyStrength = Setting.d("privacyStrength")
        privacyWhenOut = Setting.b("privacyWhenOut"); sleepDisplay = Setting.b("sleepDisplay"); gammaDim = Setting.b("gammaDim")
    }

    private func screensChanged() {
        CGDisplayRestoreColorSyncSettings()
        gammaNow = [:]; gammaGoal = [:]
        screens = ScreenInfo.all()
        buildOverlays()
    }

    private func saveDirections() {
        if let data = try? JSONEncoder().encode(directions) { UserDefaults.standard.set(data, forKey: "directions") }
    }

    private func loadDirections() {
        if let data = UserDefaults.standard.data(forKey: "directions"),
           let saved = try? JSONDecoder().decode([String: Direction].self, from: data) { directions = saved }
    }
}
