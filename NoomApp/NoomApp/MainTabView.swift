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
        .safeAreaInset(edge: .top, spacing: 0) { ConnectionIndicator() }
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

/// Persistent status bar shown above the TabView when a Noom Band is paired.
struct ConnectionIndicator: View {
    @State private var haveDevice: Bool = sensorBio.haveDevice
    @State private var connected: Bool = sensorBio.connected
    @State private var battery: Int? = sensorBio.batteryLevel
    @State private var charging: Bool? = sensorBio.charging

    var body: some View {
        Group {
            if haveDevice {
                HStack(spacing: 6) {
                    if connected {
                        Image(systemName: batteryIcon()).foregroundStyle(NoomTheme.red)
                        Text(battery.map { "Noom Band \($0)%" } ?? "Noom Band connected")
                            .foregroundStyle(NoomTheme.logoBlack)
                        if charging == true { Image(systemName: "bolt.fill").foregroundStyle(NoomTheme.gold) }
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(NoomTheme.muted)
                        Text("Noom Band not connected").foregroundStyle(NoomTheme.muted)
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 7)
                .background(NoomTheme.card)
                .overlay(alignment: .bottom) { NoomTheme.softLine.frame(height: 1) }
            }
        }
        .onReceive(sensorBio.$haveDevice) { haveDevice = $0 }
        .onReceive(sensorBio.$connected) { connected = $0 }
        .onReceive(sensorBio.$batteryLevel) { battery = $0 }
        .onReceive(sensorBio.$charging) { charging = $0 }
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
