import SwiftUI
import SensorBioSDK

struct ContentView: View {
    @State private var session: SB_Session? = sensorBio.session
    @AppStorage("envIsDev") private var envIsDev: Bool = true

    var body: some View {
        Group {
            if let session {
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
                        SignInView()
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        SignUpView()
                    } label: {
                        Label("Create Account", systemImage: "person.crop.circle.badge.plus")
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
