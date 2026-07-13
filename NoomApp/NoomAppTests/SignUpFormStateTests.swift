import XCTest
@preconcurrency import Combine
@testable import NoomApp

@MainActor
final class SignUpFormStateTests: XCTestCase {
    private enum TestError: Error { case failed }

    private func makeForm(dependencies: SignUpDependencies) -> SignUpFormState {
        let form = SignUpFormState(dependencies: dependencies)
        form.username = "tester"
        form.email = "  Taken@Example.COM  "
        form.password = "secret1"
        form.heightFeet = "5"
        form.heightInches = "10"
        form.weightInput = "165"
        return form
    }

    func testChecksNormalizedEmailBeforeCreatingAndSucceeds() async {
        var events: [String] = []
        var capturedEmail: String?
        let dependencies = SignUpDependencies(
            checkEmailAvailability: { email in
                events.append("check:\(email)")
                return .available
            },
            createAccount: { request in
                events.append("create")
                capturedEmail = request.email
                return .success
            }
        )
        let form = makeForm(dependencies: dependencies)

        await form.submit()

        XCTAssertEqual(events, ["check:taken@example.com", "create"])
        XCTAssertEqual(capturedEmail, "taken@example.com")
        XCTAssertEqual(form.result, .success(username: "tester"))
        XCTAssertEqual(form.password, "")
    }

    func testExistingEmailStopsBeforeCreate() async {
        var createCalls = 0
        let dependencies = SignUpDependencies(
            checkEmailAvailability: { _ in .emailInUse },
            createAccount: { _ in
                createCalls += 1
                return .success
            }
        )
        let form = makeForm(dependencies: dependencies)

        await form.submit()

        XCTAssertEqual(form.result, .emailInUse)
        XCTAssertEqual(createCalls, 0)
    }

    func testMalformedEmailStopsBeforeCreate() async {
        var createCalls = 0
        let dependencies = SignUpDependencies(
            checkEmailAvailability: { _ in .invalidEmail },
            createAccount: { _ in
                createCalls += 1
                return .success
            }
        )
        let form = makeForm(dependencies: dependencies)

        await form.submit()

        XCTAssertEqual(form.result, .invalidEmail)
        XCTAssertEqual(createCalls, 0)
    }

    func testCreateTimeInvalidEmailRechecksForConcurrentRegistration() async {
        var checkCalls = 0
        let dependencies = SignUpDependencies(
            checkEmailAvailability: { _ in
                checkCalls += 1
                return checkCalls == 1 ? .available : .emailInUse
            },
            createAccount: { _ in .invalidEmail }
        )
        let form = makeForm(dependencies: dependencies)

        await form.submit()

        XCTAssertEqual(checkCalls, 2)
        XCTAssertEqual(form.result, .emailInUse)
    }

    func testCreateTimeInvalidEmailRemainsFormatErrorWhenRecheckIsNotTaken() async {
        var checkCalls = 0
        let dependencies = SignUpDependencies(
            checkEmailAvailability: { _ in
                checkCalls += 1
                return .available
            },
            createAccount: { _ in .invalidEmail }
        )
        let form = makeForm(dependencies: dependencies)

        await form.submit()

        XCTAssertEqual(checkCalls, 2)
        XCTAssertEqual(form.result, .invalidEmail)
    }

    func testServiceAndThrownFailuresUseAppOwnedStates() async {
        let serviceForm = makeForm(dependencies: SignUpDependencies(
            checkEmailAvailability: { _ in .serviceUnavailable },
            createAccount: { _ in .success }
        ))
        await serviceForm.submit()
        XCTAssertEqual(serviceForm.result, .serviceUnavailable)

        let thrownForm = makeForm(dependencies: SignUpDependencies(
            checkEmailAvailability: { _ in throw TestError.failed },
            createAccount: { _ in .success }
        ))
        await thrownForm.submit()
        XCTAssertEqual(thrownForm.result, .threw)
    }

    func testUnexpectedEmailOutcomeStopsBeforeCreate() async {
        var createCalls = 0
        let form = makeForm(dependencies: SignUpDependencies(
            checkEmailAvailability: { _ in .unexpected },
            createAccount: { _ in
                createCalls += 1
                return .success
            }
        ))

        await form.submit()

        XCTAssertEqual(form.result, .unexpected)
        XCTAssertEqual(createCalls, 0)
    }

    func testInFlightSubmissionIsSuppressed() async {
        var checkCalls = 0
        let form = makeForm(dependencies: SignUpDependencies(
            checkEmailAvailability: { _ in
                checkCalls += 1
                return .available
            },
            createAccount: { _ in .success }
        ))
        form.isSubmitting = true

        await form.submit()

        XCTAssertEqual(checkCalls, 0)
        XCTAssertNil(form.result)
    }

    func testEveryCreateOutcomeMapsToAnAppOwnedResult() async {
        let cases: [(AccountCreationDecision, SignUpFormState.Result)] = [
            (.invalidBirthday, .invalidBirthday),
            (.invalidHeight, .invalidHeight),
            (.invalidWeight, .invalidWeight),
            (.invalidAccessCode, .invalidAccessCode),
            (.accessCodeAlreadyInUse, .accessCodeAlreadyInUse),
            (.deviceSerialNumberRequired, .deviceSerialNumberRequired),
            (.deviceSerialNumberMismatch, .deviceSerialNumberMismatch),
            (.serviceUnavailable, .serviceUnavailable),
            (.unexpected, .unexpected),
        ]

        for (outcome, expected) in cases {
            let form = makeForm(dependencies: SignUpDependencies(
                checkEmailAvailability: { _ in .available },
                createAccount: { _ in outcome }
            ))
            await form.submit()
            XCTAssertEqual(form.result, expected, "Failed to map \(outcome)")
        }
    }
}

@MainActor
final class DeviceIdentityPresentationTests: XCTestCase {
    func testReplacingDeviceClearsOldSerialAndRejectsDelayedOldPublication() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-A",
            waitForConnection: false
        )
        identity.observe(serial: "SERIAL-A", currentSDKSerial: "SERIAL-B")
        identity.observe(serial: "SERIAL-A", currentSDKSerial: "SERIAL-A")

        XCTAssertEqual(identity.deviceID, "DEVICE-B")
        XCTAssertNil(identity.serialNumber)

        identity.observe(serial: "SERIAL-B", currentSDKSerial: "SERIAL-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
    }

    func testPairingWaitsForConnectionBeforeAcceptingCurrentDeviceSerial() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-A",
            waitForConnection: true
        )
        identity.observe(serial: "SERIAL-B", currentSDKSerial: "SERIAL-B")
        XCTAssertNil(identity.serialNumber)

        identity.connectionEstablished(deviceID: "DEVICE-B", currentSDKSerial: "SERIAL-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
    }

    func testMismatchedConnectionEventCannotUnlockCurrentDevice() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-A",
            waitForConnection: true
        )
        identity.connectionEstablished(deviceID: "DEVICE-A", currentSDKSerial: "SERIAL-A")
        identity.observe(serial: "SERIAL-A", currentSDKSerial: "SERIAL-A")
        XCTAssertNil(identity.serialNumber)

        identity.connectionEstablished(deviceID: "DEVICE-B", currentSDKSerial: "SERIAL-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
    }

    func testSerialPublishedBeforeNewPairedIdentityIsAcceptedAfterMatchingConnection() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-B",
            waitForConnection: true
        )
        identity.connectionEstablished(deviceID: "DEVICE-B", currentSDKSerial: "SERIAL-B")

        XCTAssertEqual(identity.deviceID, "DEVICE-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
    }

    func testReconnectingSameDeviceCanReuseItsVerifiedSerial() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-A",
            currentSDKSerial: "SERIAL-A",
            waitForConnection: true
        )
        identity.connectionEstablished(deviceID: "DEVICE-A", currentSDKSerial: "SERIAL-A")

        XCTAssertEqual(identity.deviceID, "DEVICE-A")
        XCTAssertEqual(identity.serialNumber, "SERIAL-A")
    }

    func testSameDeviceRejectsAChangedSerialUntilSDKClearsIdentity() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-B", serialNumber: "SERIAL-B")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-B",
            waitForConnection: true
        )
        identity.observe(serial: "SERIAL-A", currentSDKSerial: "SERIAL-A")
        identity.connectionEstablished(deviceID: "DEVICE-B", currentSDKSerial: "SERIAL-A")
        XCTAssertNil(identity.serialNumber)

        identity.observe(serial: nil, currentSDKSerial: nil)
        identity.observe(serial: "SERIAL-B", currentSDKSerial: "SERIAL-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
    }

    func testDelayedNilCannotUnlockPreviousDeviceSerial() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-A",
            waitForConnection: false
        )
        identity.observe(serial: "SERIAL-B", currentSDKSerial: "SERIAL-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")

        identity.observe(serial: nil, currentSDKSerial: nil)
        identity.observe(serial: "SERIAL-A", currentSDKSerial: "SERIAL-A")
        XCTAssertNil(identity.serialNumber)

        identity.observe(serial: "SERIAL-B", currentSDKSerial: "SERIAL-B")
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
    }

    func testNewDeviceRejectsPreviousSerialEvenWhenSDKWasAlreadyCleared() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(deviceID: nil, currentSDKSerial: nil, waitForConnection: true)
        identity.begin(deviceID: "DEVICE-B", currentSDKSerial: nil, waitForConnection: true)
        identity.connectionEstablished(deviceID: "DEVICE-B", currentSDKSerial: "SERIAL-A")

        XCTAssertEqual(identity.deviceID, "DEVICE-B")
        XCTAssertNil(identity.serialNumber)
    }

    func testUnavailableSerialAndDeviceRemovalNeverReusePreviousIdentity() {
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-A", serialNumber: "SERIAL-A")

        identity.begin(
            deviceID: "DEVICE-B",
            currentSDKSerial: "SERIAL-A",
            waitForConnection: false
        )
        identity.observe(serial: "   ", currentSDKSerial: "   ")
        XCTAssertEqual(identity.deviceID, "DEVICE-B")
        XCTAssertNil(identity.serialNumber)

        identity.begin(deviceID: nil, currentSDKSerial: "SERIAL-A", waitForConnection: false)
        identity.observe(serial: "SERIAL-A", currentSDKSerial: "SERIAL-A")
        XCTAssertNil(identity.deviceID)
        XCTAssertNil(identity.serialNumber)
    }

    func testSerialPublisherHopsOffMainPublicationToMainThread() async {
        let subject = PassthroughSubject<String?, Never>()
        let delivered = expectation(description: "serial delivered on main")
        var identity = DeviceIdentityPresentation(deviceID: "DEVICE-B", serialNumber: nil)
        var cancellable: AnyCancellable?

        cancellable = DeviceIdentityPresentation.serialsOnMain(subject)
            .sink { serial in
                XCTAssertTrue(Thread.isMainThread)
                identity.observe(serial: serial, currentSDKSerial: serial)
                delivered.fulfill()
            }

        DispatchQueue.global(qos: .userInitiated).async {
            subject.send("SERIAL-B")
        }

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(identity.serialNumber, "SERIAL-B")
        withExtendedLifetime(cancellable) {}
    }
}
