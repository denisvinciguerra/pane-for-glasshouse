import PaneKit
import SwiftUI

@main
struct PaneiOSApp: App {
    @State private var model: MobileModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BarAppearance.apply()
        let discovery = DebugLaunch.noDiscovery
            ? Discovery(ssdp: { SSDPResult(hosts: [], denied: false) }, localHosts: { [] })
            : Discovery()
        // No ARP table on iOS: a lost TV is found again by the MAC its server reports.
        let app = AppModel(relocator: Relocator(macOf: { _ in nil }), discovery: discovery)
        if DebugLaunch.startDemo { app.startDemo(standby: DebugLaunch.demoStandby) }
        _model = State(initialValue: MobileModel(app: app))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(phase) }
        }
    }
}
