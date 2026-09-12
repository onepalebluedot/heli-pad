import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Models

public struct GoogleCalendarChoice: Identifiable, Hashable, Codable {
    public var id: String
    public var title: String
    public var isPrimary: Bool
    public var backgroundColor: String?
    public var accessRole: String?

    public init(
        id: String,
        title: String,
        isPrimary: Bool = false,
        backgroundColor: String? = nil,
        accessRole: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
        self.backgroundColor = backgroundColor
        self.accessRole = accessRole
    }
}

public enum GoogleCalendarError: LocalizedError, Equatable {
    case missingClientId
    case unauthenticated
    case authFailed(String)
    case tokenRefreshFailed(String)
    case networkError(String)
    case serverError(Int, String)
    case conflict(String)
    case decodingError(String)
    case calendarNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientId:
            return "Google Calendar requires an OAuth Client ID. Enter one in Settings > API Credentials."
        case .unauthenticated:
            return "Google account is not connected. Sign in with Google in Settings or Calendar Review."
        case .authFailed(let msg):
            return "Google authentication failed: \(msg)"
        case .tokenRefreshFailed(let msg):
            return "Google session expired. Sign in again: \(msg)"
        case .networkError(let msg):
            return "Google Calendar network error: \(msg)"
        case .serverError(let code, let msg):
            return "Google Calendar server error (HTTP \(code)): \(msg)"
        case .conflict(let msg):
            return "Calendar event conflict: \(msg)"
        case .decodingError(let msg):
            return "Google Calendar data error: \(msg)"
        case .calendarNotFound(let id):
            return "Google calendar '\(id)' was not found."
        }
    }
}

public struct GoogleTokenResponse: Codable {
    public var access_token: String
    public var expires_in: Int
    public var refresh_token: String?
    public var token_type: String
    public var scope: String?
}

public struct GoogleUserInfo: Codable {
    public var email: String?
    public var name: String?
}

// MARK: - Calendar API v3 JSON Wire Models

public struct GoogleCalendarListResponse: Codable {
    public var items: [GoogleCalendarListItem]?
}

public struct GoogleCalendarListItem: Codable {
    public var id: String
    public var summary: String?
    public var primary: Bool?
    public var backgroundColor: String?
    public var accessRole: String?
}

public struct GoogleEventsListResponse: Codable {
    public var items: [GoogleCalendarEventItem]?
    public var nextPageToken: String?
}

public struct GoogleCalendarEventItem: Codable {
    public var id: String
    public var etag: String?
    public var status: String?
    public var summary: String?
    public var description: String?
    public var location: String?
    public var start: GoogleEventDateTime?
    public var end: GoogleEventDateTime?
    public var recurringEventId: String?
    public var originalStartTime: GoogleEventDateTime?
    public var recurrence: [String]?
}

public struct GoogleEventDateTime: Codable {
    public var date: String?
    public var dateTime: String?
    public var timeZone: String?

    public init(date: String? = nil, dateTime: String? = nil, timeZone: String? = nil) {
        self.date = date
        self.dateTime = dateTime
        self.timeZone = timeZone
    }
}

// MARK: - Protocol

public protocol GoogleCalendarProtocol: AnyObject {
    func isAuthenticated() -> Bool
    func currentEmail() -> String?
    func authenticate(clientId: String) async throws -> (userEmail: String, accessToken: String)
    func disconnect() async throws
    func listCalendars() async throws -> [GoogleCalendarChoice]
    func fetchEvents(
        calendarIDs: Set<String>,
        start: Date,
        end: Date,
        timeZone: TimeZone,
        homeName: String
    ) async throws -> [TaskRecord]
    func createEvent(
        calendarId: String,
        task: TaskRecord,
        timeZone: TimeZone
    ) async throws -> (eventId: String, etag: String)
    func updateEvent(
        calendarId: String,
        eventId: String,
        task: TaskRecord,
        expectedEtag: String?,
        timeZone: TimeZone
    ) async throws -> String
    func deleteEvent(
        calendarId: String,
        eventId: String
    ) async throws
}

// MARK: - PKCE & WebAuth Presentation

#if canImport(AuthenticationServices)
@MainActor
final class HeliWebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = HeliWebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? scenes.flatMap(\.windows).first {
            return window
        }
        return ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
#endif

// MARK: - GoogleCalendarService

public final class GoogleCalendarService: GoogleCalendarProtocol {
    public static let shared = GoogleCalendarService()

    private let session: URLSession
    private let secretStore: IntegrationSecretStore

    private let keyAccessToken = "googleAccessToken"
    private let keyRefreshToken = "googleRefreshToken"
    private let keyTokenExpiry = "googleTokenExpiration"
    private let keyAccountEmail = "googleAccountEmail"
    private let keyClientId = "googleClientId"

    public init(
        session: URLSession = .shared,
        secretStore: IntegrationSecretStore = KeychainIntegrationSecrets()
    ) {
        self.session = session
        self.secretStore = secretStore
    }

    // MARK: - Auth Status & Storage

    public func isAuthenticated() -> Bool {
        guard let token = try? secretStore.get(keyAccessToken), !token.isEmpty else {
            return false
        }
        return true
    }

    public func currentEmail() -> String? {
        try? secretStore.get(keyAccountEmail)
    }

    public func currentClientId() -> String? {
        try? secretStore.get(keyClientId)
    }

    public func disconnect() async throws {
        try secretStore.set("", for: keyAccessToken)
        try secretStore.set("", for: keyRefreshToken)
        try secretStore.set("", for: keyTokenExpiry)
        try secretStore.set("", for: keyAccountEmail)
    }

    // MARK: - OAuth 2.0 with PKCE

    @MainActor
    public func authenticate(clientId: String) async throws -> (userEmail: String, accessToken: String) {
        let cleanId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            throw GoogleCalendarError.missingClientId
        }
        try secretStore.set(cleanId, for: keyClientId)

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.generateCodeChallenge(for: verifier)
        let state = UUID().uuidString

        // Standard iOS Google redirect scheme uses the reverse of the client ID
        // e.g. com.googleusercontent.apps.123456789-xyz
        let redirectScheme: String
        let redirectUri: String
        if cleanId.contains(".apps.googleusercontent.com") {
            let prefix = cleanId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
            redirectScheme = "com.googleusercontent.apps.\(prefix)"
            redirectUri = "\(redirectScheme):/oauth2redirect"
        } else {
            redirectScheme = AppConfig.defaultGoogleRedirectScheme
            redirectUri = "\(redirectScheme):/oauth2redirect"
        }

        let scopes = [
            "https://www.googleapis.com/auth/calendar.events",
            "https://www.googleapis.com/auth/calendar.readonly",
            "https://www.googleapis.com/auth/userinfo.email"
        ].joined(separator: " ")

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: cleanId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authUrl = components.url else {
            throw GoogleCalendarError.authFailed("Could not construct authorization URL")
        }

        let authCode = try await performWebAuth(url: authUrl, callbackScheme: redirectScheme, expectedState: state)
        let tokenResponse = try await exchangeCodeForTokens(
            code: authCode,
            verifier: verifier,
            clientId: cleanId,
            redirectUri: redirectUri
        )

        let email = try await fetchUserInfoEmail(accessToken: tokenResponse.access_token) ?? "Google User"

        // Persist tokens securely in Keychain
        try secretStore.set(tokenResponse.access_token, for: keyAccessToken)
        if let refresh = tokenResponse.refresh_token, !refresh.isEmpty {
            try secretStore.set(refresh, for: keyRefreshToken)
        }
        let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        let expiryString = String(expiryDate.timeIntervalSince1970)
        try secretStore.set(expiryString, for: keyTokenExpiry)
        try secretStore.set(email, for: keyAccountEmail)

        return (email, tokenResponse.access_token)
    }

    @MainActor
    private func performWebAuth(url: URL, callbackScheme: String, expectedState: String) async throws -> String {
        #if canImport(AuthenticationServices)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: GoogleCalendarError.authFailed(error.localizedDescription))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleCalendarError.authFailed("No callback URL returned"))
                    return
                }
                let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                let queryItems = comps?.queryItems ?? []
                if let err = queryItems.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: GoogleCalendarError.authFailed(err))
                    return
                }
                let state = queryItems.first(where: { $0.name == "state" })?.value
                guard state == expectedState else {
                    continuation.resume(throwing: GoogleCalendarError.authFailed("OAuth state mismatch"))
                    return
                }
                guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleCalendarError.authFailed("No authorization code in response"))
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = HeliWebAuthContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        #else
        throw GoogleCalendarError.authFailed("AuthenticationServices unavailable on this platform")
        #endif
    }

    private func exchangeCodeForTokens(
        code: String,
        verifier: String,
        clientId: String,
        redirectUri: String
    ) async throws -> GoogleTokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "code": code,
            "client_id": clientId,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]
        req.httpBody = Data(Self.encodeQuery(bodyParams).utf8)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.networkError("Invalid response from token server")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.serverError(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        } catch {
            throw GoogleCalendarError.decodingError(error.localizedDescription)
        }
    }

    private func fetchUserInfoEmail(accessToken: String) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let user = try? JSONDecoder().decode(GoogleUserInfo.self, from: data)
            return user?.email
        } catch {
            return nil
        }
    }

    // MARK: - Token Refresh

    public func validAccessToken() async throws -> String {
        guard let token = try secretStore.get(keyAccessToken), !token.isEmpty else {
            throw GoogleCalendarError.unauthenticated
        }

        let expiryTimestamp = (try? secretStore.get(keyTokenExpiry)).flatMap(Double.init) ?? 0
        let now = Date().timeIntervalSince1970
        // Refresh if within 60 seconds of expiration
        if expiryTimestamp > 0 && now >= (expiryTimestamp - 60) {
            return try await refreshAccessToken()
        }
        return token
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = try secretStore.get(keyRefreshToken), !refreshToken.isEmpty else {
            throw GoogleCalendarError.unauthenticated
        }
        let clientId = try secretStore.get(keyClientId) ?? AppConfig.defaultGoogleClientId
        guard !clientId.isEmpty else {
            throw GoogleCalendarError.missingClientId
        }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token"
        ]
        req.httpBody = Data(Self.encodeQuery(bodyParams).utf8)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.networkError("Invalid response during token refresh")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.tokenRefreshFailed(msg)
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        try secretStore.set(tokenResponse.access_token, for: keyAccessToken)
        let expiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        try secretStore.set(String(expiryDate.timeIntervalSince1970), for: keyTokenExpiry)

        return tokenResponse.access_token
    }

    // MARK: - Calendar List

    public func listCalendars() async throws -> [GoogleCalendarChoice] {
        let token = try await validAccessToken()
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.networkError("Invalid response from calendar server")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.serverError(http.statusCode, msg)
        }

        let list = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
        let choices = (list.items ?? []).map { item in
            GoogleCalendarChoice(
                id: item.id,
                title: item.summary ?? item.id,
                isPrimary: item.primary ?? false,
                backgroundColor: item.backgroundColor,
                accessRole: item.accessRole
            )
        }
        return choices.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Read Events (Import)

    public func fetchEvents(
        calendarIDs: Set<String>,
        start: Date,
        end: Date,
        timeZone: TimeZone,
        homeName: String
    ) async throws -> [TaskRecord] {
        guard !calendarIDs.isEmpty else { return [] }
        let token = try await validAccessToken()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = timeZone
        let startISO = isoFormatter.string(from: start)
        let endISO = isoFormatter.string(from: end)

        var allRecords: [TaskRecord] = []

        for calendarId in calendarIDs {
            let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
            var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events")!
            comps.queryItems = [
                URLQueryItem(name: "timeMin", value: startISO),
                URLQueryItem(name: "timeMax", value: endISO),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250")
            ]

            guard let url = comps.url else { continue }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                continue
            }

            let eventsResponse = try? JSONDecoder().decode(GoogleEventsListResponse.self, from: data)
            let items = eventsResponse?.items ?? []

            for event in items {
                if event.status == "cancelled" { continue }
                if let record = Self.parseGoogleEvent(event, calendarId: calendarId, timeZone: timeZone, homeName: homeName) {
                    allRecords.append(record)
                }
            }
        }

        return allRecords
    }

    // MARK: - Event Parser Helper

    public static func parseGoogleEvent(
        _ event: GoogleCalendarEventItem,
        calendarId: String,
        timeZone: TimeZone,
        homeName: String
    ) -> TaskRecord? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let isAllDay: Bool
        let eventDate: String
        let startTime: String
        let endTime: String

        if let allDayDate = event.start?.date {
            isAllDay = true
            eventDate = allDayDate
            startTime = "00:00"
            endTime = "23:59"
        } else if let startStr = event.start?.dateTime, let endStr = event.end?.dateTime {
            isAllDay = false
            let parser = ISO8601DateFormatter()
            guard let sDate = parser.date(from: startStr), let eDate = parser.date(from: endStr) else {
                return nil
            }
            let sParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: sDate)
            let eParts = calendar.dateComponents([.hour, .minute], from: eDate)

            eventDate = String(format: "%04d-%02d-%02d", sParts.year ?? 0, sParts.month ?? 0, sParts.day ?? 0)
            startTime = String(format: "%02d:%02d", sParts.hour ?? 0, sParts.minute ?? 0)
            endTime = String(format: "%02d:%02d", eParts.hour ?? 0, eParts.minute ?? 0)
        } else {
            return nil
        }

        let origDate: String
        if let orig = event.originalStartTime?.date {
            origDate = orig
        } else if let origDT = event.originalStartTime?.dateTime,
                  let parsedOrig = ISO8601DateFormatter().date(from: origDT) {
            let parts = calendar.dateComponents([.year, .month, .day], from: parsedOrig)
            origDate = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        } else {
            origDate = eventDate
        }

        let providerKey = "google|\(calendarId)|\(event.id)"
        let providerSeriesId: String? = {
            if let recId = event.recurringEventId, !recId.isEmpty {
                return "google-series|\(calendarId)|\(recId)"
            }
            if let recurrence = event.recurrence, !recurrence.isEmpty {
                return "google-series|\(calendarId)|\(event.id)"
            }
            return nil
        }()

        let destination = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return TaskRecord(
            id: providerKey,
            date: eventDate,
            time: startTime,
            endTime: endTime,
            title: event.summary ?? "Calendar event",
            owner: "TBD",
            location: destination.isEmpty ? homeName : destination,
            mode: destination.isEmpty ? "Home" : "Drive",
            kind: destination.isEmpty ? .home : .other,
            gcal: true,
            notes: event.description ?? "",
            allDay: isAllDay,
            seriesId: providerSeriesId,
            originalOccurrenceDate: providerSeriesId == nil ? nil : origDate,
            calendarId: providerKey
        )
    }

    // MARK: - Write Events (Create, Update, Delete)

    public func createEvent(
        calendarId: String,
        task: TaskRecord,
        timeZone: TimeZone
    ) async throws -> (eventId: String, etag: String) {
        let token = try await validAccessToken()
        let encodedCalId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events")!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = Self.taskToEventPayload(task: task, timeZone: timeZone)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.networkError("Invalid response during event creation")
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.serverError(http.statusCode, msg)
        }

        let created = try JSONDecoder().decode(GoogleCalendarEventItem.self, from: data)
        return (created.id, created.etag ?? "")
    }

    public func updateEvent(
        calendarId: String,
        eventId: String,
        task: TaskRecord,
        expectedEtag: String?,
        timeZone: TimeZone
    ) async throws -> String {
        let token = try await validAccessToken()
        let encodedCalId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEvId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEvId)")!

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let expectedEtag, !expectedEtag.isEmpty {
            req.setValue(expectedEtag, forHTTPHeaderField: "If-Match")
        }

        let payload = Self.taskToEventPayload(task: task, timeZone: timeZone)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.networkError("Invalid response during event update")
        }
        if http.statusCode == 412 {
            throw GoogleCalendarError.conflict("The event was modified on Google Calendar since last sync.")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.serverError(http.statusCode, msg)
        }

        let updated = try JSONDecoder().decode(GoogleCalendarEventItem.self, from: data)
        return updated.etag ?? ""
    }

    public func deleteEvent(
        calendarId: String,
        eventId: String
    ) async throws {
        let token = try await validAccessToken()
        let encodedCalId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedEvId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalId)/events/\(encodedEvId)")!

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.networkError("Invalid response during event deletion")
        }
        guard http.statusCode == 204 || http.statusCode == 200 || http.statusCode == 404 || http.statusCode == 410 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GoogleCalendarError.serverError(http.statusCode, msg)
        }
    }

    public static func taskToEventPayload(task: TaskRecord, timeZone: TimeZone) -> [String: Any] {
        var payload: [String: Any] = [
            "summary": task.title,
            "description": task.notes.isEmpty ? "Exported from HeliPad" : task.notes
        ]
        if !task.location.isEmpty {
            payload["location"] = task.formattedAddress ?? task.location
        }

        if task.allDay {
            payload["start"] = ["date": task.date]
            // Google all-day end date is exclusive, so next calendar day
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let parts = task.date.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3,
               let startDate = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
               let nextDay = cal.date(byAdding: .day, value: 1, to: startDate) {
                let nextParts = cal.dateComponents([.year, .month, .day], from: nextDay)
                let nextStr = String(format: "%04d-%02d-%02d", nextParts.year ?? 0, nextParts.month ?? 0, nextParts.day ?? 0)
                payload["end"] = ["date": nextStr]
            } else {
                payload["end"] = ["date": task.date]
            }
        } else {
            let tzName = timeZone.identifier
            let startRFC = "\(task.date)T\(task.time):00"
            let endRFC = "\(task.date)T\(task.endTime):00"
            payload["start"] = ["dateTime": startRFC, "timeZone": tzName]
            payload["end"] = ["dateTime": endRFC, "timeZone": tzName]
        }

        return payload
    }

    // MARK: - PKCE Utilities

    public static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func generateCodeChallenge(for verifier: String) -> String {
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #else
        return verifier
        #endif
    }

    private static func encodeQuery(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedVal = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedVal)"
        }.joined(separator: "&")
    }
}
