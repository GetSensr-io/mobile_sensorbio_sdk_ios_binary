import SwiftUI
import SensorBioSDK

struct MainTabView: View {
    let session: SB_Session

    var body: some View {
        TabView {
            NavigationStack { DashboardView(session: session) }
                .tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }

            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "sparkles") }

            NavigationStack { NoomProgressSignalsView() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            NavigationStack { SleepHomeView() }
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
        }
        .tint(NoomTheme.red)
    }
}

struct SleepHomeView: View {
    var body: some View {
        NoomScreen {
            NoomTopBar(label: "Sleep") { NoomPill(title: "Details", color: NoomTheme.ink) }
            Text("Sleep and Recovery").noomSerifTitle(size: 38)
            Text("View available data from your latest Noom Band sync.").noomBody()
            NavigationLink { SleepDetailView() } label: {
                destinationCard(title: "Sleep details", detail: "Overnight sleep, stages, and biometrics", icon: "moon.zzz.fill")
            }
            NavigationLink { RecoveryDetailView() } label: {
                destinationCard(title: "Recovery details", detail: "Recovery trends and returned score factors", icon: "heart.text.square.fill")
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func destinationCard(title: String, detail: String, icon: String) -> some View {
        NoomCard {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(NoomTheme.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(NoomTheme.logoBlack)
                    Text(detail).noomBody()
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(NoomTheme.muted)
            }
        }
    }
}

/// Compact band status shown beside the dashboard profile control.
struct BandBatteryBadge: View {
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var battery: Int? = sensorBio.batteryLevel
    @State private var charging: Bool? = sensorBio.charging

    var body: some View {
        Group {
            if haveDevice {
                HStack(spacing: 5) {
                    Image(systemName: batteryIcon())
                    if connected {
                        Text(battery.map { "\($0)%" } ?? "Live")
                        if charging == true {
                            Image(systemName: "bolt.fill")
                        }
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        Text("Offline")
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(connected ? NoomTheme.logoBlack : NoomTheme.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    connected ? NoomTheme.red.opacity(0.12) : NoomTheme.softLine.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityStatus)
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$batteryLevel) { battery = $0 }
        .onReceive(sensorBio.$charging) { charging = $0 }
    }

    private var accessibilityStatus: String {
        guard connected else { return "Noom Band not connected" }
        if let battery { return "Noom Band battery \(battery) percent" }
        return "Noom Band connected"
    }

    private func batteryIcon() -> String {
        guard let battery else { return "battery.0percent" }
        switch battery {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
