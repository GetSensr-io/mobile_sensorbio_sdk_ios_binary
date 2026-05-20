Pod::Spec.new do |s|
  s.name             = 'SensorBioSDK'
  s.version          = '0.3.1'
  s.summary          = 'Sensr-Bio SDK for iOS — binary distribution.'
  s.description      = <<~DESC
    Customer-facing iOS SDK for the Sensr-Bio biometric platform. This is
    the binary podspec — it vendors the three xcframeworks under SensorBio/
    (SensorBioSDK + SensorBioBTSDK + LibFXC) and declares the third-party
    CocoaPods that have to be pulled fresh from CocoaPods trunk
    (gRPC-Core/ProtoRPC, SwiftProtobuf, the keychain helpers, SwiftQueue,
    CocoaMQTT).

    Customer Podfile:

        pod 'SensorBioSDK',
          :git => 'git@github.com:GetSensr-io/mobile_sensorbio_sdk_ios_binary.git',
          :tag => 'v0.3.1'

    No source code is shipped; no manual file copy. CocoaPods clones the
    repo at the tag, finds this podspec at the root, links the three
    xcframeworks from SensorBio/, and resolves the transitive pods from
    trunk.
  DESC
  s.homepage         = 'https://github.com/GetSensr-io/mobile_sensorbio_sdk_ios_binary'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Sensr-Bio.' }
  s.author           = { 'Sensr-Bio' => 'engineering@sensr.ai' }
  s.source           = {
    :git => 'git@github.com:GetSensr-io/mobile_sensorbio_sdk_ios_binary.git',
    :tag => "v#{s.version}"
  }

  s.ios.deployment_target = '18.0'
  s.swift_versions        = ['6.1']

  # All three xcframeworks ship together. SensorBioSDK is the customer-facing
  # Swift API; SensorBioBTSDK and LibFXC are linked transitively (the SDK's
  # BLE and FXC-sleep paths call into them) — declaring them as vendored
  # frameworks here means the customer's app links all three automatically.
  s.vendored_frameworks = [
    'SensorBio/SensorBioSDK.xcframework',
    'SensorBio/SensorBioBTSDK.xcframework',
    'SensorBio/LibFXC.xcframework'
  ]

  # Third-party transitive deps. SensorBioSDK.xcframework was built with
  # MACH_O_TYPE=staticlib, so symbols from these libraries stay UNDEFINED
  # in the binary and get resolved at the customer's link step. The
  # customer's `pod install` resolves each via CocoaPods trunk.
  s.dependency 'gRPC-ProtoRPC'                    # brings gRPC-Core + abseil + BoringSSL-GRPC + Protobuf
  s.dependency 'SwiftProtobuf',         '~> 1.37'
  s.dependency 'SwiftKeychainWrapper',  '~> 4.0'
  s.dependency 'KeychainAccess',        '~> 4.0'
  s.dependency 'SwiftQueue',            '~> 6.0'
  s.dependency 'CocoaMQTT',             '~> 2.2'

  # Push `FX_PLATFORM_UNIX=1` into the customer's compile too. The
  # fx_datatypes.h header inside SensorBioSDK.xcframework/Headers/ `#error`s
  # without one of FX_PLATFORM_{WIN32, UNIX, ARM_M3, ARM_M4, MSP430} defined.
  # When the customer's Swift compiler builds its precompiled module of the
  # framework's umbrella header, it hits that header at the consumer level —
  # so the define has to propagate to the user target's xcconfig.
  s.user_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) FX_PLATFORM_UNIX=1',
    'OTHER_CFLAGS'                 => '$(inherited) -DFX_PLATFORM_UNIX=1'
  }

  s.requires_arc = true
end
