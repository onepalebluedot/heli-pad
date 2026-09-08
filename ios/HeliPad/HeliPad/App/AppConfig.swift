import Foundation

public enum AppConfig {
    // Personal integration credentials are supplied by the user and kept in Keychain.
    public static let defaultNeonConnectionString = ""
    public static let defaultGoogleMapsApiKey = ""
    public static var isCloudConfigured: Bool { false }
}
