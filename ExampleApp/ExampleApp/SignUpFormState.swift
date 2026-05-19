import Foundation
import Observation
import SensorBioSDK

@Observable
final class SignUpFormState {
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
    var orgId: String = ""

    var isSubmitting: Bool = false
    var result: Result? = nil

    enum Result {
        case success(username: String)
        case invalidBirthday
        case invalidEmail
        case invalidHeight
        case invalidWeight
        case other(message: String)
        case threw(String)
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
        let trimmedOrgId = orgId.trimmingCharacters(in: .whitespaces)

        let request = SB_CreateAccountRequest(
            username: username,
            email: email,
            password: password,
            birthday: birthdayComponents,
            gender: gender,
            heightCm: heightCmValue,
            weight: weight,
            imperialUnits: imperialUnits,
            orgId: trimmedOrgId.isEmpty ? nil : trimmedOrgId
        )

        do {
            let outcome = try await sensorBio.createAccount(request)
            switch outcome {
            case .success:
                result = .success(username: username)
            case .invalidBirthday:
                result = .invalidBirthday
            case .invalidEmail:
                result = .invalidEmail
            case .invalidHeight:
                result = .invalidHeight
            case .invalidWeight:
                result = .invalidWeight
            case .other(let message):
                result = .other(message: message)
                @unknown default:
                    break
            }
        } catch {
            result = .threw(error.localizedDescription)
        }
    }
}
