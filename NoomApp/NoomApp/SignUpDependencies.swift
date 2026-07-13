import Foundation
import SensorBioSDK

struct SignUpRequest {
    let username: String
    let email: String
    let password: String
    let birthday: DateComponents
    let gender: SB_Gender
    let heightCm: Float
    let weight: Float
    let imperialUnits: Bool
}

enum EmailAvailabilityDecision: Equatable {
    case available
    case invalidEmail
    case emailInUse
    case serviceUnavailable
    case unexpected
}

enum AccountCreationDecision: Equatable {
    case success
    case invalidBirthday
    case invalidEmail
    case invalidHeight
    case invalidWeight
    case invalidAccessCode
    case accessCodeAlreadyInUse
    case deviceSerialNumberRequired
    case deviceSerialNumberMismatch
    case serviceUnavailable
    case unexpected
}

struct SignUpDependencies {
    let checkEmailAvailability: (String) async throws -> EmailAvailabilityDecision
    let createAccount: (SignUpRequest) async throws -> AccountCreationDecision

    static let live = SignUpDependencies(
        checkEmailAvailability: { email in
            switch try await sensorBio.checkEmailAvailability(email: email) {
            case .ok:
                return .available
            case .invalidEmail:
                return .invalidEmail
            case .emailInUse:
                return .emailInUse
            case .other:
                return .serviceUnavailable
            @unknown default:
                return .unexpected
            }
        },
        createAccount: { form in
            let request = SB_CreateAccountRequest(
                username: form.username,
                email: form.email,
                password: form.password,
                birthday: form.birthday,
                gender: form.gender,
                heightCm: form.heightCm,
                weight: form.weight,
                imperialUnits: form.imperialUnits,
                orgId: nil,
                accountVerificationAccessCode: nil,
                deviceSerialNumber: nil
            )

            switch try await sensorBio.createAccount(request) {
            case .success:
                return .success
            case .invalidBirthday:
                return .invalidBirthday
            case .invalidEmail:
                return .invalidEmail
            case .invalidHeight:
                return .invalidHeight
            case .invalidWeight:
                return .invalidWeight
            case .invalidAccessCode:
                return .invalidAccessCode
            case .accessCodeAlreadyInUse:
                return .accessCodeAlreadyInUse
            case .deviceSerialNumberRequired:
                return .deviceSerialNumberRequired
            case .deviceSerialNumberMismatch:
                return .deviceSerialNumberMismatch
            case .other:
                return .serviceUnavailable
            @unknown default:
                return .unexpected
            }
        }
    )
}
