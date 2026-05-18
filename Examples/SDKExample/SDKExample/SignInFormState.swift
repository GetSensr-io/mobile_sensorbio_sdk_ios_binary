import Foundation
import Observation
import SensorBioSDK

@Observable
final class SignInFormState {
    var email: String = ""
    var password: String = ""

    var isSubmitting: Bool = false
    var result: Result? = nil

    enum Result {
        case success(username: String)
        case passwordIncorrect
        case unknownUsername
        case other(message: String)
        case threw(String)
    }

    var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isSubmitting
    }

    @MainActor
    func submit() async {
        isSubmitting = true
        result = nil
        defer { isSubmitting = false }

        do {
            let outcome = try await sensorBio.signIn(email: email, password: password)
            switch outcome {
            case .success(let session):
                result = .success(username: session.username)
            case .passwordIncorrect:
                result = .passwordIncorrect
            case .unknownUsername:
                result = .unknownUsername
            case .other(let message):
                result = .other(message: message)
            }
        } catch {
            result = .threw(String(describing: error))
        }
    }
}
