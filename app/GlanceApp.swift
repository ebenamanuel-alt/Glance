//  Glance: app entry point. It keeps running in the menu bar when you close the window.
import SwiftUI

@main
struct GlanceApp: App {
    @StateObject private var glance = Glance()

    /// The menu bar icon shows Glance's state at a glance.
    private var menuIcon: String {
        if !glance.isOn { return "eye.slash" }
        if !glance.worn { return "airpodspro" }
        if glance.needsRecentre { return "scope" }
        return "eye"
    }

    var body: some Scene {
        Window("Glance", id: "main") {
            ContentView().environmentObject(glance)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Glance", systemImage: menuIcon) {
            MenuContent().environmentObject(glance)
        }
    }
}
