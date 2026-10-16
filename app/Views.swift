//  Glance: the main window, the settings window and the menu bar menu.

import SwiftUI
import AppKit

extension ScreenInfo {
    /// The MacBook's own screen, rather than an external monitor
    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var g: Glance
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            VStack(spacing: 14) {
                StatusCard()
                problems
                HStack(alignment: .top, spacing: 14) {
                    DeskScene()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    VStack(spacing: 14) {
                        ScreensCard()
                        GesturesCard()
                        Spacer(minLength: 0)
                    }
                    .frame(width: 320)
                }
            }
            .padding(18)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 940, minHeight: 600)
        .onAppear { g.start() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("Glance").font(.headline)
            Spacer()
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Open settings (⌘ ,)")
            Toggle("Glance on", isOn: $g.isOn)
                .toggleStyle(.switch)
                .help("Turn Glance on or off (⌃ ⌥ G)")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(.bar)
    }

    // MARK: Problems, each with its fix

    @ViewBuilder private var problems: some View {
        if !g.trusted {
            ProblemBanner(symbol: "hand.raised.fill",
                          text: "Glance needs Accessibility permission to move the cursor and windows.",
                          button: "Open Accessibility") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if g.lightsEnabled && !g.bridgeOnline {
            ProblemBanner(symbol: "lightbulb.slash",
                          text: "The lights bridge isn't running, so your lights won't switch when you leave.",
                          button: "Start bridge") { g.startBridge() }
        }
    }
}

struct ProblemBanner: View {
    let symbol: String
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Button(button, action: action).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }
}

// MARK: - Status card: what Glance is doing right now

struct StatusCard: View {
    @EnvironmentObject var g: Glance

    private enum Mood { case good, waiting, off }

    private var state: (mood: Mood, symbol: String, title: String, detail: String) {
        let facingName = g.screens.first { $0.key == g.facing }?.name
        if g.calibration != nil { return (.waiting, "viewfinder", "Calibrating", "Turn your head to each dot, then press Space or nod. Esc cancels.") }
        if !g.isOn { return (.off, "eye.slash", "Glance is off", "Your screens work as normal. Switch it on at the top, or press ⌃ ⌥ G.") }
        if !g.airpods { return (.waiting, "airpodspro", "Waiting for your AirPods", "Put your AirPods Pro in and Glance starts by itself.") }
        if !g.worn { return (.waiting, "airpodspro", "Paused: AirPods out", "Your screens work as normal until you put them back in.") }
        if g.needsRecentre { return (.waiting, "scope", "Face your main screen and recentre", "Your AirPods were away for a while, so Glance needs a fresh starting point.") }
        if g.directions.isEmpty { return (.waiting, "display.2", "Save your screens to begin", "Press Calibrate and look at the corners of each screen. It takes about 30 seconds.") }
        if g.hidden { return (.good, "lock.fill", "Screens hidden while you're away", "Look back at a screen, or hold ⌃ ⌥, to show them.") }
        let dimmed = g.screens.filter { $0.key != g.activeScreen && g.directions[$0.key] != nil }.map(\.name)
        var parts: [String] = []
        if g.spotlight && !dimmed.isEmpty { parts.append("\(dimmed.joined(separator: ", ")) dimmed") }
        parts.append("AirPods in")
        if g.followCursor { parts.append("cursor follows your eyes") }
        if let name = facingName { return (.good, "eye", "Active · looking at \(name)", parts.joined(separator: " · ")) }
        return (.good, "eye", "Active · looking away", parts.joined(separator: " · "))
    }

    var body: some View {
        let s = state
        let tint: Color = s.mood == .good ? .green : (s.mood == .waiting ? .orange : .secondary)
        HStack(spacing: 14) {
            Image(systemName: s.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(s.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { g.recentreFromShortcut() } label: { Label("Recentre", systemImage: "scope") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [])
                .help("Face your main screen, then press this (⌃ ⌥ R)")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Screens card

struct ScreensCard: View {
    @EnvironmentObject var g: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Screens").font(.headline)
                Text("\(g.directions.count) of \(g.screens.count) saved").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { g.startCalibration() } label: { Label("Calibrate", systemImage: "viewfinder") }
                    .controlSize(.small)
                    .help("Look at the corners of each screen so Glance learns exactly where they are")
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ForEach(Array(g.screens.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Divider().padding(.leading, 44) }
                row(s)
            }
        }
        .padding(.bottom, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func row(_ s: ScreenInfo) -> some View {
        let saved = g.directions[s.key] != nil
        let looking = g.facing == s.key
        let dimmed = g.spotlight && saved && g.activeScreen != nil && g.activeScreen != s.key
        let kind = g.boxes[s.key] != nil ? "Calibrated" : "Saved"
        let detail = !saved ? "Not saved yet" : (looking ? "You're looking at it" : (dimmed ? "\(kind) · dimmed" : kind))
        return HStack(spacing: 10) {
            Image(systemName: looking ? "eye" : (s.isBuiltIn ? "laptopcomputer" : "display"))
                .frame(width: 20)
                .foregroundStyle(looking ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(detail).font(.caption)
                    .foregroundStyle(looking ? Color.accentColor : (saved ? Color.secondary : Color.orange))
            }
            Spacer(minLength: 6)
            if !saved {
                Button("Save") { g.save(s) }.controlSize(.small).buttonStyle(.borderedProminent)
                    .help("Look at this screen, then press Save")
            }
            Menu {
                Button(saved ? "Update direction" : "Save direction") { g.save(s) }
                Button("Show which screen this is") { g.identify(s) }
                if saved {
                    Divider()
                    Button("Forget this screen", role: .destructive) { g.forget(s) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More for \(s.name)")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(looking ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

// MARK: - Gestures card

struct GesturesCard: View {
    private let items: [(String, String)] = [
        ("⌃ ⌥ + nod", "Bring that window to the front"),
        ("⌃ ⌥ ⌘ + look", "Move the window to that screen"),
        ("⌃ ⌥ G", "Turn Glance on or off"),
        ("⌃ ⌥ R", "Recentre"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Gestures").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(items, id: \.0) { keys, text in
                    GridRow {
                        Text(keys)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
                        Text(text).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Desk scene: your real desk, your head, and where you're looking

struct DeskScene: View {
    @EnvironmentObject var g: Glance

    private struct Item: Identifiable {
        let screen: ScreenInfo
        let rect: CGRect
        let lit: Bool
        var id: String { screen.key }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let deskY = size.height * 0.64
            let items = layout(size: size, deskY: deskY)
            let headCentre = CGPoint(x: size.width * 0.5, y: size.height * 0.70)
            let turn = CGFloat(max(-30, min(30, -g.yaw * 0.7)))
            let target = items.first { $0.screen.key == g.facing }

            ZStack(alignment: .topLeading) {
                // Wall and desk
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
                if let t = target {
                    RadialGradient(colors: [Color(red: 0.66, green: 0.79, blue: 1).opacity(0.35), .clear],
                                   center: .init(x: t.rect.midX / max(1, size.width), y: t.rect.midY / max(1, size.height)),
                                   startRadius: 0, endRadius: size.width * 0.45)
                }
                Rectangle()
                    .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.92, blue: 0.90), Color(red: 0.81, green: 0.80, blue: 0.77)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size.width, height: size.height - deskY)
                    .offset(y: deskY)

                // Keyboard and mice in front of the external monitor
                if let ext = items.first(where: { !$0.screen.isBuiltIn }) {
                    let kx = ext.rect.midX
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.96))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.82)))
                        .frame(width: size.width * 0.24, height: size.height * 0.08)
                        .position(x: kx - size.width * 0.02, y: deskY + size.height * 0.11)
                    Ellipse().fill(Color(white: 0.98)).overlay(Ellipse().strokeBorder(Color(white: 0.82)))
                        .frame(width: 22, height: 12)
                        .position(x: kx - size.width * 0.02, y: deskY + size.height * 0.035)
                    Ellipse().fill(Color(white: 0.1))
                        .frame(width: 28, height: 18)
                        .position(x: min(size.width - 20, kx + size.width * 0.17), y: deskY + size.height * 0.13)
                }

                // Beam from your head to the screen you're looking at
                if let t = target {
                    Path { p in
                        p.move(to: CGPoint(x: headCentre.x + turn * 0.6, y: headCentre.y - 36))
                        p.addLine(to: CGPoint(x: t.rect.minX, y: t.rect.minY))
                        p.addLine(to: CGPoint(x: t.rect.maxX, y: t.rect.minY))
                        p.addLine(to: CGPoint(x: t.rect.maxX, y: t.rect.maxY))
                        p.addLine(to: CGPoint(x: t.rect.minX, y: t.rect.maxY))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.45), Color.blue.opacity(0.04)],
                                         startPoint: .bottom, endPoint: .top))
                    .animation(.easeOut(duration: 0.25), value: g.facing)
                }

                // The screens
                ForEach(items) { item in
                    if item.screen.isBuiltIn {
                        LaptopView(lit: item.lit, dim: g.spotlightStrength, looking: g.facing == item.screen.key)
                            .frame(width: item.rect.width, height: item.rect.height * 1.18)
                            .position(x: item.rect.midX, y: item.rect.minY + item.rect.height * 0.59)
                    } else {
                        MonitorView(lit: item.lit, dim: g.spotlightStrength, looking: g.facing == item.screen.key,
                                    deskY: deskY - item.rect.minY)
                            .frame(width: item.rect.width, height: item.rect.height)
                            .position(x: item.rect.midX, y: item.rect.midY)
                    }
                }

                // You, from behind, with AirPods in
                HeadView(turn: Double(turn), airpods: g.airpods && g.worn)
                    .frame(width: 140, height: 150)
                    .position(x: headCentre.x, y: headCentre.y + 40)
                    .animation(.easeOut(duration: 0.15), value: turn)

                // Labels
                VStack {
                    HStack {
                        Text("Your desk").font(.headline).foregroundStyle(.white)
                        Spacer()
                        Text(g.airpods ? "Live from your AirPods" : "AirPods not connected")
                            .font(.caption).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                    Spacer()
                    HStack {
                        ForEach(items.sorted { $0.rect.midX < $1.rect.midX }) { item in
                            let looking = g.facing == item.screen.key
                            Text(looking ? "Looking at \(item.screen.name)" : (item.lit ? item.screen.name : "\(item.screen.name) · dimmed"))
                                .font(.caption).foregroundStyle(.white).lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(looking ? Color.accentColor.opacity(0.9) : Color.black.opacity(0.55), in: Capsule())
                            if item.id != items.sorted(by: { $0.rect.midX < $1.rect.midX }).last?.id { Spacer() }
                        }
                    }
                }
                .padding(14)
                .frame(width: size.width, height: size.height)

                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "display.2").font(.system(size: 34)).foregroundStyle(.white.opacity(0.8))
                        Text("1. Face your main screen and press Recentre.")
                        Text("2. Look at each screen and press Save.")
                    }
                    .font(.callout).foregroundStyle(.white.opacity(0.85))
                    .frame(width: size.width, height: size.height * 0.6)
                }
            }
        }
    }

    /// Places each saved screen where it really is: left or right by which way you turn to see it,
    /// higher up if you look up at it. The MacBook sits on the desk; monitors stand behind it.
    private func layout(size: CGSize, deskY: CGFloat) -> [Item] {
        let saved = g.screens.compactMap { s in g.directions[s.key].map { (s, $0) } }
        guard !saved.isEmpty else { return [] }
        let yaws = saved.map(\.1.yaw)
        let minYaw = yaws.min() ?? 0, maxYaw = yaws.max() ?? 0
        let spread = max(1, maxYaw - minYaw)
        let pitches = saved.map(\.1.pitch)
        let maxPitch = pitches.max() ?? 0
        return saved.map { s, d in
            // Turning left is a bigger yaw, so it goes further left
            let t = CGFloat(saved.count == 1 ? 0.5 : (maxYaw - d.yaw) / spread)
            let x = size.width * (0.27 + 0.46 * t)
            let lit = !g.spotlight || g.activeScreen == nil || g.activeScreen == s.key || !g.isOn
            if s.isBuiltIn {
                let w = size.width * 0.36, h = w * 0.6
                return Item(screen: s, rect: CGRect(x: x - w / 2, y: deskY - h, width: w, height: h), lit: lit)
            } else {
                let w = size.width * 0.5, h = w * 0.6
                let lift = CGFloat(max(0.0, min(1.0, (maxPitch - d.pitch) / 20)))   // lower if you look down at it
                let top = size.height * (0.06 + 0.10 * lift)
                return Item(screen: s, rect: CGRect(x: x - w / 2, y: top, width: w, height: h), lit: lit)
            }
        }
    }
}

/// A screen showing a couple of windows, dimmed when you're not looking at it.
struct ScreenContent: View {
    let lit: Bool
    let dim: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.86, green: 0.9, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(Color(red: 0.89, green: 0.91, blue: 0.95)).frame(height: max(4, h * 0.08))
                HStack(spacing: 2) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25))
                }
                .frame(width: max(9, h * 0.13), height: max(3, h * 0.04))
                .offset(x: w * 0.03, y: h * 0.02)
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.85))
                    .frame(width: w * 0.2, height: h * 0.8).offset(x: w * 0.03, y: h * 0.13)
                RoundedRectangle(cornerRadius: 2).fill(.white)
                    .frame(width: w * 0.71, height: h * 0.8).offset(x: w * 0.26, y: h * 0.13)
                VStack(alignment: .leading, spacing: max(2, h * 0.04)) {
                    Capsule().fill(Color.black.opacity(0.7)).frame(width: w * 0.42, height: max(2, h * 0.04))
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(Color(red: 0.8, green: 0.84, blue: 0.88))
                            .frame(width: w * (i == 3 ? 0.4 : 0.62), height: max(1.5, h * 0.025))
                    }
                    HStack(spacing: w * 0.02) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.18)).frame(width: w * 0.3, height: h * 0.3)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.93, green: 0.94, blue: 0.96)).frame(width: w * 0.32, height: h * 0.3)
                    }
                }
                .offset(x: w * 0.29, y: h * 0.19)
                Rectangle().fill(Color.black.opacity(lit ? 0 : max(0.35, dim)))
                    .animation(.easeOut(duration: 0.3), value: lit)
            }
        }
    }
}

struct MonitorView: View {
    let lit: Bool
    let dim: Double
    let looking: Bool
    /// How far below the screen's top edge the desk is, for the stand
    let deskY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                // Arm down to the desk, at the back right
                Rectangle().fill(Color(white: 0.12))
                    .frame(width: 7, height: max(0, deskY - h * 0.55))
                    .offset(x: w * 0.85, y: h * 0.55)
                Ellipse().fill(Color(white: 0.08))
                    .frame(width: 60, height: 10)
                    .offset(x: w * 0.85 - 27, y: deskY - 5)
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(white: 0.07))
                ScreenContent(lit: lit, dim: dim)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.horizontal, 5).padding(.top, 5).padding(.bottom, 9)
                Text("DELL").font(.system(size: 5, weight: .semibold)).tracking(0.6).foregroundStyle(Color(white: 0.45))
                    .frame(width: w).offset(y: h - 8)
                if looking {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-2)
                }
            }
        }
    }
}

struct LaptopView: View {
    let lit: Bool
    let dim: Double
    let looking: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lid = h * 0.85
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(white: 0.1))
                    .frame(width: w * 0.92, height: lid).offset(x: w * 0.04)
                ScreenContent(lit: lit, dim: dim)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .frame(width: w * 0.92 - 10, height: lid - 10).offset(x: w * 0.04 + 5, y: 5)
                if looking {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: w * 0.92 + 4, height: lid + 4).offset(x: w * 0.04 - 2, y: -2)
                }
                Path { p in
                    p.move(to: CGPoint(x: w * 0.04, y: lid))
                    p.addLine(to: CGPoint(x: w * 0.96, y: lid))
                    p.addLine(to: CGPoint(x: w, y: h * 0.96))
                    p.addLine(to: CGPoint(x: 0, y: h * 0.96))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.3)], startPoint: .top, endPoint: .bottom))
                Rectangle().fill(Color(white: 0.22)).frame(width: w, height: h * 0.04).offset(y: h * 0.96)
            }
        }
    }
}

struct HeadView: View {
    /// Degrees, positive turns to the right
    let turn: Double
    let airpods: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let shift = CGFloat(turn) * 0.35
            let skin = LinearGradient(colors: [Color(red: 0.48, green: 0.3, blue: 0.2), Color(red: 0.37, green: 0.23, blue: 0.15)],
                                      startPoint: .leading, endPoint: .trailing)
            ZStack(alignment: .topLeading) {
                // Shoulders and neck
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addCurve(to: CGPoint(x: w / 2, y: h * 0.7), control1: CGPoint(x: w * 0.02, y: h * 0.76), control2: CGPoint(x: w * 0.25, y: h * 0.7))
                    p.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: w * 0.75, y: h * 0.7), control2: CGPoint(x: w * 0.98, y: h * 0.76))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.23, blue: 0.3), Color(red: 0.12, green: 0.15, blue: 0.2)],
                                     startPoint: .top, endPoint: .bottom))
                Rectangle().fill(skin).frame(width: w * 0.22, height: h * 0.16).offset(x: w * 0.39, y: h * 0.58)
                // Ears
                Ellipse().fill(skin).frame(width: w * 0.1, height: h * 0.17)
                    .offset(x: w * 0.17 + shift * 0.5, y: h * 0.33)
                Ellipse().fill(skin).frame(width: w * 0.08 + shift * 0.002, height: h * 0.15)
                    .offset(x: w * 0.73 + shift * 0.5, y: h * 0.33)
                // Head
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 0.18, green: 0.13, blue: 0.1), Color(red: 0.06, green: 0.04, blue: 0.03)],
                                         center: UnitPoint(x: CGFloat(0.5 + turn / 120), y: 0.35), startRadius: 2, endRadius: w * 0.5))
                    .frame(width: w * 0.62, height: h * 0.64)
                    .rotationEffect(.degrees(turn * 0.5))
                    .offset(x: w * 0.19 + shift * 0.3, y: h * 0.04)
                // AirPods Pro
                if airpods {
                    airpod.offset(x: w * 0.17 + shift * 0.5, y: h * 0.37)
                    airpod.scaleEffect(0.85).offset(x: w * 0.76 + shift * 0.5, y: h * 0.36)
                }
            }
        }
    }

    private var airpod: some View {
        VStack(spacing: -1) {
            Ellipse().fill(Color(white: 0.97)).frame(width: 9, height: 10)
            Capsule().fill(Color(white: 0.97)).frame(width: 4.5, height: 17)
        }
        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }
}

// MARK: - Settings window

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", cursor = "Cursor", spotlight = "Spotlight", privacy = "Privacy", lights = "Lights", airpods = "AirPods"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .cursor: return "cursorarrow"
        case .spotlight: return "sun.max.fill"
        case .privacy: return "lock.fill"
        case .lights: return "lightbulb.fill"
        case .airpods: return "airpodspro"
        }
    }
    var colour: Color {
        switch self {
        case .general: return .gray
        case .cursor: return .blue
        case .spotlight: return .orange
        case .privacy: return .indigo
        case .lights: return .yellow
        case .airpods: return .green
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var g: Glance
    @State private var page: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { p in
                Label {
                    Text(p.rawValue)
                } icon: {
                    Image(systemName: p.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p == .lights ? Color.black.opacity(0.8) : .white)
                        .frame(width: 22, height: 22)
                        .background(p.colour, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Form { detail(page ?? .general) }
                .formStyle(.grouped)
                .navigationTitle(page?.rawValue ?? "General")
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    @ViewBuilder private func detail(_ p: SettingsPage) -> some View {
        switch p {
        case .general: general
        case .cursor: cursor
        case .spotlight: spotlight
        case .privacy: privacy
        case .lights: lights
        case .airpods: airpods
        }
    }

    // MARK: Pages

    @ViewBuilder private var general: some View {
        Section {
            Toggle(isOn: $g.isOn) { row("Glance on", "Turn everything on or off. Shortcut: ⌃ ⌥ G") }
        }
        Section("Shortcuts") {
            LabeledContent("Turn Glance on or off", value: "⌃ ⌥ G")
            LabeledContent("Recentre", value: "⌃ ⌥ R")
            LabeledContent("Show your screens again", value: "Hold ⌃ ⌥")
        }
        Section {
            LabeledContent {
                Button("Reset", role: .destructive) { g.resetSettings() }
            } label: {
                row("Reset to defaults", "Puts every setting back to how it started. Your saved screens are kept.")
            }
        }
    }

    @ViewBuilder private var cursor: some View {
        Section {
            LabeledContent {
                Button("Calibrate") { g.startCalibration() }
            } label: {
                row("Calibrate your screens", "Look at the corners of each screen so Glance knows exactly where they are")
            }
        }
        Section {
            Toggle(isOn: $g.followCursor) { row("Move the cursor to the screen you look at", "The cursor jumps to the screen you're facing") }
            Picker("Switch screens", selection: $g.autoSwitch) {
                Text("Automatically").tag(true)
                Text("Only while holding ⌃ ⌥").tag(false)
            }
            Toggle(isOn: $g.nodEnabled) { row("Nod to focus", "Hold ⌃ ⌥ and nod to bring the window to the front") }
            Toggle(isOn: $g.throwEnabled) { row("Move windows by looking", "Hold ⌃ ⌥ ⌘ and look at another screen to move the front window there") }
        }
        Section {
            DisclosureGroup("More options") {
                slider("Look time", $g.dwell, 0...1.5, step: 0.05, String(format: "%.2f s", g.dwell),
                       "How long you look at a screen before switching. Longer ignores quick glances.")
                slider("Aim", $g.tolerance, 10...45, step: 1, "\(Int(g.tolerance))°",
                       "How close to a screen you must look. Only for screens you haven't calibrated.")
                slider("Nod size", $g.nodSize, 3...15, step: 1, "\(Int(g.nodSize))°",
                       "How far your head must dip for a nod.")
                Toggle("Return to where the cursor was on that screen", isOn: $g.rememberPosition)
                Toggle("Make the window there ready for typing", isOn: $g.focusOnSwitch)
            }
        }
    }

    @ViewBuilder private var spotlight: some View {
        Section {
            Toggle(isOn: $g.spotlight) { row("Dim screens you're not looking at", "The screen you face stays bright") }
            slider("Dim amount", $g.spotlightStrength, 0.1...0.8, step: 0.05, "\(Int(g.spotlightStrength * 100))%", nil)
            LabeledContent("Try it on your screens") { Button("Test dimming") { g.testDim() } }
        } footer: {
            Text(spotStatus).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            DisclosureGroup("More options") {
                Picker("Dim by", selection: $g.gammaDim) {
                    Text("Darkening colours").tag(true)
                    Text("Dark layer").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Darkening colours works best on external monitors. Try Dark layer if one doesn't dim.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var privacy: some View {
        Section {
            Toggle(isOn: $g.privacy) { row("Hide my screens when I look away", "Nobody can read over your shoulder while you're turned away") }
            slider("Away time", $g.awaySeconds, 3...60, step: 1, "\(Int(g.awaySeconds)) s",
                   "How long you can look away before your screens hide.")
            Picker("When away", selection: $g.sleepDisplay) {
                Text("Blur screens").tag(false)
                Text("Turn screens off").tag(true)
            }
        } footer: {
            Text("Holding ⌃ ⌥ always shows your screens again.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            DisclosureGroup("More options") {
                slider("Cover strength", $g.privacyStrength, 0.3...1, step: 0.05, "\(Int(g.privacyStrength * 100))%",
                       "100% hides everything completely.")
            }
        }
    }

    @ViewBuilder private var lights: some View {
        Section {
            LabeledContent {
                if g.bridgeOnline {
                    Button("Test lights") { g.testLights() }
                } else {
                    Button("Start bridge") { g.startBridge() }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(g.bridgeOnline ? Color.green : Color.orange).frame(width: 8, height: 8)
                    row(g.bridgeOnline ? "Bridge running" : "Bridge not running",
                        g.bridgeOnline ? "\(g.bridgeLights.count) light(s) found" : "Glance needs Look and Nod's bridge to reach your lights")
                }
            }
        } footer: {
            Text(g.lightNote).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle(isOn: $g.lightsEnabled) { row("Switch my lights off when I leave my desk", "And back on when you return") }
            if g.lightsEnabled {
                Picker("Which light", selection: $g.lightTarget) {
                    Text("All lights").tag("all")
                    ForEach(g.bridgeLights) { l in Text(l.label).tag(l.name) }
                }
                slider("Leave after", $g.leaveSeconds, 2...300, step: 1, leaveText,
                       "How long you look away from your screens before the lights go off.")
                Toggle("Switch them back on when I return", isOn: $g.lightsBackOn)
            }
        }
        if g.lightsEnabled {
            Section {
                Picker("Only when it's dark", selection: $g.darkMode) {
                    Text("Sunset to sunrise").tag(0)
                    Text("Set hours").tag(1)
                    Text("Any time").tag(2)
                }
                if g.darkMode == 0 {
                    slider("Start early", $g.sunOffset, 0...90, step: 5, "\(Int(g.sunOffset)) min",
                           "Counts as dark this long before sunset and after sunrise.")
                } else if g.darkMode == 1 {
                    Stepper(String(format: "Dark from %02d:00", Int(g.startHour)), value: $g.startHour, in: 0...23)
                    Stepper(String(format: "Until %02d:00", Int(g.endHour)), value: $g.endHour, in: 0...23)
                }
            } footer: {
                Text("\(g.darkSummary) · \(g.isDark ? "It's dark now" : "It's light now")").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var airpods: some View {
        Section {
            Toggle(isOn: $g.keepAirPodsAwake) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep AirPods connected")
                    Text("Plays a sound too quiet to hear, so pausing a video doesn't disconnect them").font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("AirPods") {
                Text(!g.airpods ? "Not connected" : (g.worn ? "In your ears" : "Out"))
                    .foregroundStyle(g.airpods && g.worn ? Color.green : Color.secondary)
            }
            LabeledContent {
                Button("Recentre") { g.recentreFromShortcut() }
            } label: {
                row("Recentre", "Face your main screen and press this. Shortcut: ⌃ ⌥ R")
            }
        } footer: {
            Text("Taking your AirPods out pauses Glance, so your screens always work while they're charging. If they're out for a short time, Glance carries on by itself when you put them back.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var leaveText: String {
        let v = g.leaveSeconds
        return v < 60 ? "\(Int(v)) s" : String(format: "%d min %02d s", Int(v) / 60, Int(v) % 60)
    }

    private var spotStatus: String {
        guard let a = g.activeScreen, let bright = g.screens.first(where: { $0.key == a }) else {
            return "Right now: waiting until you look at a saved screen."
        }
        let dimmed = g.screens.filter { $0.key != a }.map(\.name).joined(separator: ", ")
        return "Right now: \(bright.name) bright" + (dimmed.isEmpty ? "." : ", \(dimmed) dimmed.")
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double,
                        _ shown: String, _ hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Slider(value: value, in: range, step: step).labelsHidden()
                Text(shown).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 64, alignment: .trailing)
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Menu bar menu

struct MenuContent: View {
    @EnvironmentObject var g: Glance
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Glance on   ⌃⌥G", isOn: $g.isOn)
        Button("Recentre   ⌃⌥R") { g.recentre() }
        if g.airpods && !g.worn { Text("Paused: AirPods out") }
        if g.needsRecentre { Text("Press Recentre to resume") }
        Divider()
        Button("Open Glance") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Glance") { NSApp.terminate(nil) }
    }
}

// MARK: - Calibration overlay: a dot in each corner to look at

struct CalibrationOverlay: View {
    let screenName: String
    let screenNumber: Int
    let screenCount: Int
    /// nil = the starting point in the middle of the screen
    let corner: Corner?
    let stepsDone: Int
    let stepsTotal: Int

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let inset: CGFloat = 70
            let dot: CGPoint = {
                switch corner {
                case .none: return CGPoint(x: size.width / 2, y: size.height / 2)
                case .topLeft: return CGPoint(x: inset, y: inset + 30)
                case .topRight: return CGPoint(x: size.width - inset, y: inset + 30)
                case .bottomRight: return CGPoint(x: size.width - inset, y: size.height - inset)
                case .bottomLeft: return CGPoint(x: inset, y: size.height - inset)
                }
            }()
            ZStack {
                Color.black.opacity(0.62)

                VStack(spacing: 10) {
                    Text(corner == nil ? "Calibrate Glance" : "Screen \(screenNumber) of \(screenCount) · \(screenName)")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    Text(corner == nil ? "Face the middle of this screen" : "Turn your head to the \(corner!.name) dot")
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    Text("Then press Space or nod. Turn your head, not just your eyes.")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 6) {
                        ForEach(0..<stepsTotal, id: \.self) { i in
                            Circle().fill(i < stepsDone ? Color.accentColor : Color.white.opacity(0.3)).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.top, 8)
                    Text("Esc to cancel").font(.caption).foregroundStyle(.white.opacity(0.5)).padding(.top, 4)
                }
                .padding(.horizontal, 36).padding(.vertical, 26)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                        .frame(width: 70, height: 70)
                        .scaleEffect(pulse ? 1.25 : 0.8)
                        .opacity(pulse ? 0 : 1)
                    Circle().fill(Color.white).frame(width: 30, height: 30)
                    Circle().fill(Color.accentColor).frame(width: 14, height: 14)
                }
                .position(dot)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
    }
}

// MARK: - Short message shown in the middle of the screen

struct BannerView: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - "Which one?" label shown on a screen

struct IdentifyBadge: View {
    let name: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "display").font(.system(size: 54, weight: .semibold))
            Text(name).font(.system(size: 40, weight: .bold))
            Text("This screen").font(.title2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 48).padding(.vertical, 32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
