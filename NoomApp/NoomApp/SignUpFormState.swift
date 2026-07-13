import Foundation
import Observation
import SensorBioSDK

@Observable
final class SignUpFormState {
    private let dependencies: SignUpDependencies

    var username: String = ""
    var email: String = ""
    var password: String = ""
    var birthday: Date = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date()
    var gender: SB_Gender = .undisclosed

    var heightCm: String = ""
    var heightFeet: String = ""
    var heightInches: String = ""
    var weightInput: String = ""
    var imperialUnits: Bool = true

    var isSubmitting: Bool = false
    var result: Result? = nil

    enum Result: Equatable {
        case success(username: String)
        case invalidBirthday
        case invalidEmail
        case emailInUse
        case invalidHeight
        case invalidWeight
        case invalidAccessCode
        case accessCodeAlreadyInUse
        case deviceSerialNumberRequired
        case deviceSerialNumberMismatch
        case serviceUnavailable
        case threw
        case unexpected
    }

    init(dependencies: SignUpDependencies = .live) {
        self.dependencies = dependencies
    }

    var heightOK: Bool {
        if imperialUnits {
            return Float(heightFeet) != nil && Float(heightInches) != nil
        } else {
            return Float(heightCm) != nil
        }
    }

    var canSubmit: Bool {
        !username.isEmpty &&
        !email.isEmpty &&
        password.count >= 6 &&
        heightOK &&
        Float(weightInput) != nil &&
        !isSubmitting
    }

    @MainActor
    func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        result = nil
        defer { isSubmitting = false }

        let heightCmValue: Float
        if imperialUnits {
            let feet = Float(heightFeet) ?? 0
            let inches = Float(heightInches) ?? 0
            heightCmValue = (feet * 12 + inches) * 2.54
        } else {
            heightCmValue = Float(heightCm) ?? 0
        }
        let weight = Float(weightInput) ?? 0
        let birthdayComponents = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let request = SignUpRequest(
            username: username,
            email: normalizedEmail,
            password: password,
            birthday: birthdayComponents,
            gender: gender,
            heightCm: heightCmValue,
            weight: weight,
            imperialUnits: imperialUnits
        )

        do {
            let emailAvailability = try await dependencies.checkEmailAvailability(normalizedEmail)
            switch emailAvailability {
            case .available:
                break
            case .invalidEmail:
                result = .invalidEmail
                return
            case .emailInUse:
                result = .emailInUse
                return
            case .serviceUnavailable:
                result = .serviceUnavailable
                return
            case .unexpected:
                result = .unexpected
                return
            }

            let outcome = try await dependencies.createAccount(request)
            switch outcome {
            case .success:
                password = ""
                result = .success(username: username)
            case .invalidBirthday:
                result = .invalidBirthday
            case .invalidEmail:
                // Availability and creation are separate backend operations.
                // Recheck after a create-time rejection so a concurrent signup
                // is never mislabeled as a malformed address.
                if let latest = try? await dependencies.checkEmailAvailability(normalizedEmail),
                   latest == .emailInUse {
                    result = .emailInUse
                } else {
                    result = .invalidEmail
                }
            case .invalidHeight:
                result = .invalidHeight
            case .invalidWeight:
                result = .invalidWeight
            case .invalidAccessCode:
                result = .invalidAccessCode
            case .accessCodeAlreadyInUse:
                result = .accessCodeAlreadyInUse
            case .deviceSerialNumberRequired:
                result = .deviceSerialNumberRequired
            case .deviceSerialNumberMismatch:
                result = .deviceSerialNumberMismatch
            case .serviceUnavailable:
                result = .serviceUnavailable
            case .unexpected:
                result = .unexpected
            }
        } catch {
            result = .threw
        }
    }
}
