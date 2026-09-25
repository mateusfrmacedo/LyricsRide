import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Spotify integration based on OAuth PKCE and the Web API. Unlike App Remote,
/// it doesn't keep a fragile socket to the Spotify app and can refresh its own
/// credentials while Drive Mode keeps Lyrics Ride running.
@MainActor
final class SpotifyManager: NSObject, ObservableObject {
    @Published private(set) var status: String
    @Published private(set) var snapshot: SpotifySnapshot?
    @Published private(set) var artwork: UIImage?
    @Published private(set) var artworkTint: UIColor?
    @Published private(set) var isConnected: Bool

    private let clientID: String
    private let redirectURI: String
    private let callbackScheme: String
    private let tokenStore: SpotifyTokenStore
    private let presenter = SpotifyAuthorizationPresenter()
    private var authorizationSession: ASWebAuthenticationSession?
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<SpotifyToken, Error>?
    private var artworkURL = ""

    private static let scopes = [
        "user-read-currently-playing",
        "user-read-playback-state",
        "user-modify-playback-state",
    ]
    private static let activePollInterval: TimeInterval = 5
    private static let idlePollInterval: TimeInterval = 15

    override init() {
        let storedTokens = SpotifyTokenStore()
        clientID = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        redirectURI = Bundle.main.object(forInfoDictionaryKey: "SpotifyRedirectURI") as? String ?? "lyricsride://spotify-callback"
        callbackScheme = URL(string: redirectURI)?.scheme ?? "lyricsride"
        tokenStore = storedTokens
        let hasStoredToken = storedTokens.load() != nil
        isConnected = hasStoredToken
        status = hasStoredToken ? "Spotify conectado" : "Spotify não conectado"
        super.init()
        if hasStoredToken { startPolling() }
    }

    var isConfigured: Bool {
        !clientID.isEmpty && !clientID.contains("PREENCHA")
    }

    func connect() {
        Task {
            do {
                try await authorize()
                isConnected = true
                status = "Spotify conectado"
                startPolling()
                await pollNow()
            } catch {
                status = "Não foi possível conectar ao Spotify"
            }
        }
    }

    /// ASWebAuthenticationSession receives the callback itself. This remains
    /// available for a future manual callback or universal-link configuration.
    func handleOpenURL(_ url: URL) {}

    func reconnectWhenActive() {
        guard tokenStore.load() != nil else { return }
        isConnected = true
        startPolling()
        Task { await pollNow() }
    }

    func disconnectWhenInactive() {}

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        tokenStore.clear()
        snapshot = nil
        artwork = nil
        artworkTint = nil
        artworkURL = ""
        isConnected = false
        status = "Spotify não conectado"
    }

    func togglePlayback() {
        guard let snapshot else { return }
        let endpoint = snapshot.isPaused ? "play" : "pause"
        Task { await sendPlayerCommand(endpoint, method: "PUT") }
    }

    func skipToNext() {
        Task { await sendPlayerCommand("next", method: "POST") }
    }

    func skipToPrevious() {
        Task { await sendPlayerCommand("previous", method: "POST") }
    }

    // MARK: - OAuth PKCE

    private func authorize() async throws {
        guard isConfigured else { throw SpotifyError.missingClientID }
        let verifier = PKCE.randomVerifier()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
        ]

        status = "Conecte sua conta Spotify"
        let callback = try await openAuthorization(components.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        guard items?.first(where: { $0.name == "state" })?.value == state,
              let code = items?.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.invalidCallback
        }

        let token = try await exchangeCode(code, verifier: verifier)
        tokenStore.save(token)
    }

    private func openAuthorization(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                self.authorizationSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? SpotifyError.invalidCallback)
                }
            }
            session.presentationContextProvider = presenter
            authorizationSession = session
            session.start()
        }
    }

    // MARK: - Playback polling

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.pollPlayback()
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func pollNow() async {
        _ = await pollPlayback()
    }

    @discardableResult
    private func pollPlayback() async -> TimeInterval {
        do {
            let response = try await authorizedRequest(path: "me/player", method: "GET")
            guard let http = response.response as? HTTPURLResponse else { return Self.idlePollInterval }
            switch http.statusCode {
            case 200:
                guard let playback = try? JSONDecoder().decode(SpotifyPlaybackResponse.self, from: response.data),
                      let track = playback.item else {
                    return Self.idlePollInterval
                }
                let newSnapshot = SpotifySnapshot(
                    title: track.name,
                    artist: track.artists.first?.name ?? "",
                    duration: Double(track.durationMS) / 1_000,
                    position: Double(playback.progressMS ?? 0) / 1_000,
                    isPaused: !(playback.isPlaying ?? false),
                    deviceID: playback.device?.id
                )
                snapshot = newSnapshot
                status = "Spotify conectado"
                isConnected = true
                await loadArtwork(url: track.album?.images.first?.url)
                return newSnapshot.isPaused ? Self.idlePollInterval : Self.activePollInterval
            case 204:
                snapshot = nil
                return Self.idlePollInterval
            case 401:
                _ = try await refreshAccessToken()
                return 1
            case 429:
                return Self.retryAfter(from: http) ?? Self.idlePollInterval
            default:
                status = "Spotify aguardando resposta"
                return Self.idlePollInterval
            }
        } catch SpotifyError.notConnected {
            isConnected = false
            status = "Reconecte sua conta Spotify"
            return Self.idlePollInterval
        } catch {
            // A rede pode oscilar enquanto o iPhone está no carro. Preserve a
            // última posição, deixe o motor de letras interpolar e tente de novo.
            return Self.idlePollInterval
        }
    }

    private func sendPlayerCommand(_ endpoint: String, method: String) async {
        do {
            let deviceQuery = snapshot?.deviceID.map { "?device_id=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? ""
            let response = try await authorizedRequest(path: "me/player/\(endpoint)\(deviceQuery)", method: method)
            guard let http = response.response as? HTTPURLResponse else { return }
            if (200..<300).contains(http.statusCode) || http.statusCode == 204 {
                try? await Task.sleep(for: .milliseconds(350))
                await pollNow()
            } else {
                status = "O Spotify não permitiu este controle"
            }
        } catch {
            status = "Não foi possível controlar o Spotify"
        }
    }

    private func loadArtwork(url: String?) async {
        guard let url, url != artworkURL, let imageURL = URL(string: url) else { return }
        artworkURL = url
        guard let (data, response) = try? await URLSession.shared.data(from: imageURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return }
        artwork = image
        artworkTint = image.averageColor
    }

    // MARK: - Tokens and requests

    private func authorizedRequest(path: String, method: String) async throws -> (data: Data, response: URLResponse) {
        let token = try await validAccessToken()
        guard let url = URL(string: "https://api.spotify.com/v1/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
    }

    private func validAccessToken() async throws -> String {
        guard let token = tokenStore.load() else { throw SpotifyError.notConnected }
        if Date.now < token.expiresAt.addingTimeInterval(-60) { return token.accessToken }
        return try await refreshAccessToken().accessToken
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> SpotifyToken {
        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        guard let refresh = response.refreshToken else { throw SpotifyError.invalidCallback }
        return SpotifyToken(accessToken: response.accessToken, refreshToken: refresh, expiresAt: .now.addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    private func refreshAccessToken() async throws -> SpotifyToken {
        if let refreshTask { return try await refreshTask.value }
        guard let oldToken = tokenStore.load() else { throw SpotifyError.notConnected }
        let task = Task { [clientID] in
            try await SpotifyManager.refresh(oldToken, clientID: clientID)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokenStore.save(fresh)
            isConnected = true
            return fresh
        } catch {
            tokenStore.clear()
            isConnected = false
            throw error
        }
    }

    private static func refresh(_ oldToken: SpotifyToken, clientID: String) async throws -> SpotifyToken {
        let response = try await spotifyTokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": oldToken.refreshToken,
            "client_id": clientID,
        ])
        return SpotifyToken(accessToken: response.accessToken, refreshToken: response.refreshToken ?? oldToken.refreshToken, expiresAt: .now.addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    private func tokenRequest(_ parameters: [String: String]) async throws -> SpotifyTokenResponse {
        try await Self.spotifyTokenRequest(parameters)
    }

    private static func spotifyTokenRequest(_ parameters: [String: String]) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData(parameters)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SpotifyError.tokenRejected }
        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private static func formData(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let form = values.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        .sorted()
        .joined(separator: "&")
        return Data(form.utf8)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
    }
}

private extension UIImage {
    /// A one-pixel render provides a lightweight album-derived color for the
    /// player surface without retaining or analyzing the full artwork.
    var averageColor: UIColor? {
        guard let cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }
}

extension UIColor {
    func playerSurfaceColor(brightnessMultiplier: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: min(1, saturation * 0.9),
            brightness: min(1, max(0, brightness * brightnessMultiplier)),
            alpha: alpha
        )
    }
}

struct SpotifySnapshot: Equatable {
    let title: String
    let artist: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPaused: Bool
    let deviceID: String?
}

private enum SpotifyError: Error {
    case missingClientID
    case invalidCallback
    case notConnected
    case tokenRejected
}

private enum PKCE {
    static func randomVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct SpotifyToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

private final class SpotifyTokenStore {
    private let service = "com.mateus.lyricsride.spotify"
    private let account = "pkce-token"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> SpotifyToken? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    func save(_ token: SpotifyToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        SecItemDelete(query as CFDictionary)
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(request as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct SpotifyPlaybackResponse: Decodable {
    struct Device: Decodable { let id: String? }
    struct Artist: Decodable { let name: String }
    struct Album: Decodable {
        struct Image: Decodable { let url: String }
        let images: [Image]
    }
    struct Track: Decodable {
        let name: String
        let durationMS: Int
        let artists: [Artist]
        let album: Album?

        enum CodingKeys: String, CodingKey {
            case name, artists, album
            case durationMS = "duration_ms"
        }
    }

    let device: Device?
    let progressMS: Int?
    let isPlaying: Bool?
    let item: Track?

    enum CodingKeys: String, CodingKey {
        case device, item
        case progressMS = "progress_ms"
        case isPlaying = "is_playing"
    }
}

private final class SpotifyAuthorizationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}
