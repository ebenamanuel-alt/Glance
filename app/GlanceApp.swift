//  Glance: app entry point. It keeps running in the menu bar when you close the window.
import SwiftUI

@main
struct GlanceApp: App {
    @StateObject private var glance = Glance()

    var body: some Scene {
        Window("Glance", id: "main") {
            ContentView().environmentObject(glance)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Glance", systemImage: glance.isOn ? "eye" : "eye.slash") {
            MenuContent().environmentObject(glance)
        }
    }
}
