import Foundation

public enum AppConfig {
    // Personal integration credentials are supplied by the user and kept in Keychain.
    public static let defaultNeonConnectionString = ""
    public static let defaultGoogleMapsApiKey = ""
    public static let defaultGoogleClientId = "1037189020820-589hmin2r68cn1g852vk5dgbvodco6on.apps.googleusercontent.com"
    public static let defaultGoogleRedirectScheme = "helipad"
    public static var isCloudConfigured: Bool { false }

    public static var familyAPIURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FamilyAPIURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url.appendingPathComponent("")
    }
}
