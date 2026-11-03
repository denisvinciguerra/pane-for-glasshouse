import Foundation

/// Launch arguments for filming the demo, read in Debug builds only:
/// - `-PaneStartDemo YES`: the demo starts at launch, without the welcome screen;
/// - `-PaneDemoStandby YES`: the demo TV starts in Active Standby, screen off;
/// - `-PaneHideDemoLabel YES`: no « Demo » label nor Exit button on Remote (the row keeps its height);
/// - `-PaneNoDiscovery YES`: the search for TVs finds nothing, so no real TV shows on the welcome screen.
enum DebugLaunch {
    #if DEBUG
    static let startDemo = UserDefaults.standard.bool(forKey: "PaneStartDemo")
    static let demoStandby = UserDefaults.standard.bool(forKey: "PaneDemoStandby")
    static let hideDemoLabel = UserDefaults.standard.bool(forKey: "PaneHideDemoLabel")
    static let noDiscovery = UserDefaults.standard.bool(forKey: "PaneNoDiscovery")
    #else
    static let startDemo = false
    static let demoStandby = false
    static let hideDemoLabel = false
    static let noDiscovery = false
    #endif
}
