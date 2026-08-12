import SwiftUI
import SensorBioSDK

struct ContentView: View {
    @State private var session: SB_Session? = sensorBio.session
    @State private var authFlow = AuthFlow.shared
    @AppStorage("envIsDev") private var envIsDev: Bool = true

    var body: some View {
        Group {
            // While a register attempt is resolving, stay on the signed-out
            // screen even if the SDK has transiently published a session — a
            // failed register creates the account and publishes a session
            // before we roll it back.
            if let session, !authFlow.isRegistering {
                MainTabView(session: session)
            } else {
                signedOut
            }
        }
        .onReceive(sensorBio.$session) { session = $0 }
        .onChange(of: envIsDev) { _, newValue in
            SB_SDK.environment = newValue ? .staging : .production
        }
    }

    private var signedOut: some View {
        NavigationStack {
            List {
                Section("Auth") {
                    NavigationLink {
                        RegisterView()
                    } label: {
                        Label("Register", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                Section {
                    Picker("Server", selection: $envIsDev) {
                        Text("Staging").tag(true)
                        Text("Prod").tag(false)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Environment")
                } footer: {
                    Text("Flip before signing in. Changes after the first RPC take full effect on next launch.")
                }
                Section("About") {
                    LabeledContent("SDK", value: "SensorBioSDK")
                    LabeledContent("Linked as", value: "local SPM (../..)")
                }
            }
            .navigationTitle("SDK Example")
        }
    }
}

#Preview {
    ContentView()
}
