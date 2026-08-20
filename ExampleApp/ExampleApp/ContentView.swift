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

    // Signed out, the register screen IS the app: a customer integration has
    // exactly one way in — `registerUser(userId:)` with an org SDK key — so
    // there is nothing to choose between and no menu to show.
    private var signedOut: some View {
        NavigationStack {
            RegisterView()
        }
    }
}

#Preview {
    ContentView()
}
