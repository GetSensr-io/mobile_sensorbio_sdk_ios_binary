import SwiftUI
import SensorBioSDK

struct MainTabView: View {
    let session: SB_Session

    var body: some View {
        VStack(spacing: 0) {
            ConnectionIndicator()
            TabView {
                NavigationStack { DashboardView(session: session) }
                    .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }

                NavigationStack { TimelineTabView() }
                    .tabItem { Label("Timeline", systemImage: "clock") }

                NavigationStack { InsightsView() }
                    .tabItem { Label("Insights", systemImage: "lightbulb") }

                NavigationStack { ProfileView(session: session) }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }
        }
    }
}

/// Persistent status bar shown above the TabView when the user has a
/// paired device. Reads `connected` + `batteryLevel` and renders a
/// compact "X% • Connected" / "Not connected" line.
struct ConnectionIndicator: View {
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var battery: Int? = sensorBio.batteryLevel
    @State private var charging: Bool? = sensorBio.charging

    var body: some View {
        Group {
            if haveDevice {
                indicator
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$batteryLevel) { battery = $0 }
        .onReceive(sensorBio.$charging) { charging = $0 }
    }

    @ViewBuilder
    private var indicator: some View {
        HStack(spacing: 6) {
            if connected {
                Image(systemName: batteryIcon())
                    .foregroundStyle(.green)
                Text(connected && battery != nil ? "\(battery!)%" : "Connected")
                    .foregroundStyle(.primary)
                if charging == true {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                }
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.secondary)
                Text("Not connected")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func batteryIcon() -> String {
        guard let battery else { return "battery.0percent" }
        switch battery {
        case ..<13:  return "battery.0percent"
        case ..<38:  return "battery.25percent"
        case ..<63:  return "battery.50percent"
        case ..<88:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }
}
