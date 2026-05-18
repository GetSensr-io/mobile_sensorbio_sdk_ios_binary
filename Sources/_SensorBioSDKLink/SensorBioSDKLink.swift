// Wrapper module — re-exports SensorBioSDK and links every transitive SPM dep
// so the customer's Package.swift only has to declare one product.
// Customer code keeps `import SensorBioSDK`.
@_exported import SensorBioSDK
