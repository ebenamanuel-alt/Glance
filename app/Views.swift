//  Glance: the window, the settings panel and the menu bar menu.

import SwiftUI
import AppKit

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var g: Glance
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            header
            HStack(alignment: .top, spacing: 16) {
                DeskMap()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
                screenList
                    .frame(width: 340)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 920, minHeight: 580)
        .onAppear { g.start() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [.teal, .blue], startPoint: .top, endPoint: .bottom))
                Image(systemName: "eye.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Glance").font(.system(size: 24, weight: .bold))
                Text(g.message).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                pill("airpodspro", "AirPods", g.airpods)
                pill("hand.raised", g.trusted ? "Allowed" : "Allow Accessibility", g.trusted)
                pill("keyboard", g.listening ? "Listening" : "⌃ ⌥", g.listening, neutral: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            Toggle("On", isOn: $g.isOn).toggleStyle(.switch).labelsHidden().help("Turn Glance on or off")
            Button { showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless)
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) { SettingsPanel().environmentObject(g) }
            Button { g.recentre() } label: { Label("Recentre", systemImage: "scope") }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: [])
                .help("Face your main screen, then press this. Do it each time you start Glance.")
        }
    }

    private func pill(_ symbol: String, _ text: String, _ ok: Bool, neutral: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : (neutral ? Color.secondary : Color.orange)).frame(width: 7, height: 7)
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text)
        }
        .font(.caption.weight(.medium))
    }

    // MARK: Screens list

    private var screenList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your screens", systemImage: "display.2").font(.headline)
                Spacer()
                Text("\(g.directions.count) of \(g.screens.count) saved").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(g.screens) { s in screenRow(s) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func screenRow(_ s: ScreenInfo) -> some View {
        let saved = g.directions[s.key]
        let looking = g.facing == s.key
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: looking ? "eye.fill" : "display")
                    .frame(width: 22)
                    .foregroundStyle(looking ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.body.weight(.semibold)).lineLimit(1)
                    Text(saved == nil ? "Not saved yet" : (looking ? "You're looking at it" : "Saved"))
                        .font(.caption)
                        .foregroundStyle(looking ? Color.accentColor : (saved == nil ? Color.orange : Color.secondary))
                }
                Spacer()
                Text("\(Int(s.frame.width))×\(Int(s.frame.height))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                if saved == nil {
                    Button("Save direction") { g.save(s) }.buttonStyle(.borderedProminent)
                } else {
                    Button("Update direction") { g.save(s) }
                }
                Button("Which one?") { g.identify(s) }.help("Shows the name on that screen for a moment")
                if saved != nil { Button("Forget") { g.forget(s) } }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(looking ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(looking ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 18) {
            hint("eye", g.autoSwitch ? "Look at a screen: the cursor follows" : "Hold ⌃ ⌥ and look: the cursor follows")
            hint("arrow.down.circle", "Hold ⌃ ⌥ and nod: focus that window")
            hint("macwindow.on.rectangle", "Hold ⌃ ⌥ ⌘ and look: move the window")
            hint("lock.shield", "Look away: screens hide")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
    }
}

// MARK: - Desk map: your screens and where you're looking, seen from above

struct Placed: Identifiable {
    let screen: ScreenInfo
    let dir: Direction
    var id: String { screen.key }
}

struct DeskMap: View {
    @EnvironmentObject var g: Glance

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let saved = g.screens.compactMap { s in g.directions[s.key].map { Placed(screen: s, dir: $0) } }
            let extent: Double = max(30, saved.map { max(abs($0.dir.yaw), abs($0.dir.pitch)) }.max() ?? 30)
            let half: Double = Double(min(size.width, size.height)) / 2
            let scale: Double = max(1, min(8, (half - 90) / extent))
            let point: (Double, Double) -> CGPoint = { yaw, pitch in
                CGPoint(x: Double(c.x) - yaw * scale, y: Double(c.y) - pitch * scale)
            }
            let ring = CGFloat(g.tolerance * scale * 2)
            ZStack {
                VStack {
                    HStack {
                        Label("Your desk", systemImage: "rectangle.3.group").font(.headline)
                        Spacer()
                        Text(g.hidden ? "Screens hidden" : (g.listening ? "Listening" : ""))
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)

                ForEach(saved) { item in
                    let s = item.screen
                    let d = item.dir
                    let w: CGFloat = 120
                    let h = max(50, min(110, w * s.frame.height / max(1, s.frame.width)))
                    let looking = g.facing == s.key
                    let active = g.activeScreen == s.key
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(looking ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(looking ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: looking ? 3 : 1.5))
                            .overlay(Image(systemName: active ? "sun.max.fill" : "display")
                                .foregroundStyle(active ? Color.yellow : Color.secondary))
                            .frame(width: w, height: h)
                            .shadow(color: looking ? Color.accentColor.opacity(0.5) : .clear, radius: 12)
                        Text(s.name).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 150)
                    }
                    .position(point(d.yaw, d.pitch))
                    .animation(.easeOut(duration: 0.2), value: looking)
                }

                if saved.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "display.2").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("1. Face your main screen and press Recentre.")
                        Text("2. Look at each screen and press Save direction.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                // Where your head is pointing
                let head = point(g.yaw, g.pitch)
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                    .frame(width: ring, height: ring)
                    .position(head)
                Circle()
                    .fill(g.listening ? Color.orange : Color.accentColor)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(radius: 4)
                    .position(head)
            }
        }
        .clipped()
    }
}

// MARK: - Settings panel

struct SettingsPanel: View {
    @EnvironmentObject var g: Glance

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings").font(.title3.weight(.semibold))

                section("Cursor follows your eyes", "eye")
                Toggle("Move the cursor to the screen you look at", isOn: $g.followCursor)
                Picker("Switch", selection: $g.autoSwitch) {
                    Text("Automatically").tag(true)
                    Text("Only holding ⌃ ⌥").tag(false)
                }
                .pickerStyle(.segmented)
                slider("Look time", $g.dwell, 0...1.5, step: 0.05, format: { String(format: "%.2f s", $0) },
                       hint: "How long you must look at a screen before switching. Longer means quick glances are ignored.")
                slider("Aim", $g.tolerance, 10...45, step: 1, format: { "\(Int($0))°" },
                       hint: "How close to a screen you must look. Smaller means more precise.")
                Toggle("Return to where the cursor was on that screen", isOn: $g.rememberPosition)
                Toggle("Make the window there ready for typing", isOn: $g.focusOnSwitch)

                section("Nod to focus", "arrow.down.circle")
                Toggle("Hold ⌃ ⌥ and nod to bring the window to the front", isOn: $g.nodEnabled)
                slider("Nod size", $g.nodSize, 3...15, step: 1, format: { "\(Int($0))°" },
                       hint: "How far your head must dip. Smaller means a smaller nod counts.")

                section("Move windows", "macwindow.on.rectangle")
                Toggle("Hold ⌃ ⌥ ⌘ and look at another screen to move the front window there", isOn: $g.throwEnabled)

                section("Spotlight", "sun.max")
                Toggle("Dim the screens you're not looking at", isOn: $g.spotlight)
                Picker("Dim by", selection: $g.gammaDim) {
                    Text("Darkening colours").tag(true)
                    Text("Dark layer").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Darkening colours works best on external monitors like Dell. Try the other if one doesn't work.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                slider("Dim amount", $g.spotlightStrength, 0.1...0.8, step: 0.05, format: { "\(Int($0 * 100))%" },
                       hint: "How dark the other screens go.")
                Text(spotStatus).font(.caption).foregroundStyle(.secondary)
                Button("Test dimming") { g.testDim() }
                    .help("Darkens every screen except the one with the cursor for 2 seconds")

                section("Privacy", "lock.shield")
                Toggle("Hide my screens when I look away", isOn: $g.privacy)
                slider("Away time", $g.awaySeconds, 3...60, step: 1, format: { "\(Int($0)) s" },
                       hint: "How long you can look away before your screens are hidden.")
                Picker("When away", selection: $g.sleepDisplay) {
                    Text("Blur screens").tag(false)
                    Text("Turn screens off").tag(true)
                }
                .pickerStyle(.segmented)
                slider("Cover strength", $g.privacyStrength, 0.3...1, step: 0.05, format: { "\(Int($0 * 100))%" },
                       hint: "100% hides everything completely.")
                Toggle("Also hide when I take my AirPods out", isOn: $g.privacyWhenOut)
                Text("Holding ⌃ ⌥ always shows your screens again.").font(.caption).foregroundStyle(.secondary)

                Divider()
                Button("Reset to defaults") { g.resetSettings() }
            }
            .padding(18)
        }
        .frame(width: 360, height: 620)
    }

    private var spotStatus: String {
        guard let a = g.activeScreen, let bright = g.screens.first(where: { $0.key == a }) else {
            return "Spotlight: waiting until you look at a saved screen."
        }
        let dimmed = g.screens.filter { $0.key != a }.map(\.name).joined(separator: ", ")
        return "Spotlight now: \(bright.name) bright" + (dimmed.isEmpty ? "" : ", \(dimmed) dimmed")
    }

    private func section(_ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double,
                        format: @escaping (Double) -> String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Menu bar menu

struct MenuContent: View {
    @EnvironmentObject var g: Glance
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Glance on", isOn: $g.isOn)
        Button("Recentre") { g.recentre() }
        Divider()
        Button("Open Glance") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Glance") { NSApp.terminate(nil) }
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
