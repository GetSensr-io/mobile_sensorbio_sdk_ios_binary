import SwiftUI
import UIKit

/// The full contents of the `sdk_token` the register call presented, plus the
/// rest of what the exchange returned.
///
/// Shown because this app is a demonstration of the flow — it minted the token
/// in-process, so it can show you exactly what went on the wire. A real app has
/// no reason to surface one: it receives a token from its backend, hands it to
/// `registerUser`, and forgets it.
struct SDKTokenSheet: View {
    let record: SDKTokenRecord

    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if let token = record.token {
                    Section {
                        Text(token.sdkToken)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        Text("sdk_token")
                    } footer: {
                        Text("Spent. A token is good for exactly one register-or-login, and Sensor Bio keeps only its SHA-256 hash plus the \(String(token.sdkToken.prefix(9)))… prefix — which is the half you quote in a bug report.")
                    }

                    Section {
                        Button {
                            UIPasteboard.general.string = token.sdkToken
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy token",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    }

                    Section {
                        LabeledContent("organization_id", value: token.organizationId)
                            .textSelection(.enabled)
                        LabeledContent("sdk_key_id",
                                       value: token.sdkKeyId.isEmpty ? "—" : token.sdkKeyId)
                            .textSelection(.enabled)
                        LabeledContent("expires_in_seconds", value: "\(token.expiresInSeconds)")
                        if let mintedAt = record.mintedAt {
                            LabeledContent("minted", value: mintedAt.formatted(date: .omitted, time: .standard))
                        }
                        if let expiresAt = record.expiresAt {
                            LabeledContent("expires", value: expiresAt.formatted(date: .omitted, time: .standard))
                        }
                    } header: {
                        Text("From the exchange")
                    } footer: {
                        Text("`organization_id` and `sdk_token` are the only two fields your backend has to return to your app. The rest are diagnostics: `sdk_key_id` names the SDK Key this token was anchored to, and revoking that key signs out every session minted under it.")
                    }
                } else {
                    Section {
                        Label("Session restored — no register this launch",
                              systemImage: "key.slash")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("A relaunch restores the access/refresh pair from the keychain and re-registers nothing, so no exchange happened. The token that bootstrapped this session was spent by that register and is kept nowhere — not on the device, and not by Sensor Bio (only its hash and prefix).")
                    }
                }
            }
            .navigationTitle("SDK Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
