#if os(macOS)
import SwiftUI
import Security
import AuthenticationServices
import CryptoKit

struct NativeSession: Codable {
    var account: CloudAccount
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var admitted: Bool
    let configuration: CloudConfiguration
}
enum SessionKeychain {
    static func query(_ origin: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "tech.gnyanarushi.MyNotes.cloud.\(CloudCodec.hash(Data(origin.utf8)))", kSecAttrAccount as String: "active-session"] }
    static func load(_ origin: String) throws -> NativeSession? {
        var q = query(origin); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CloudError.message("Unable to read the saved session from Keychain.") }
        return try JSONDecoder().decode(NativeSession.self, from: data)
    }
    static func save(_ session: NativeSession, origin: String) throws {
        let data = try CloudCodec.encode(session), q = query(origin)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CloudError.message("Unable to save the session in Keychain.") }
        } else if status != errSecSuccess { throw CloudError.message("Unable to update the session in Keychain.") }
    }
    static func clear(_ origin: String) throws {
        let status = SecItemDelete(query(origin) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw CloudError.message("Unable to clear the Keychain session. Retry sign-out.") }
    }
}
struct TokenResponse: Decodable {
    struct User: Decodable { let id: String; let email: String? }
    let access_token: String; let refresh_token: String; let expires_in: Int; let user: User
}

@MainActor final class CloudSession: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var origin = UserDefaults.standard.string(forKey: "MyNotes.APIOrigin") ?? "https://mynotes.gnyanarushi.tech"
    @Published var workspace: DesktopSyncEngine?
    @Published var busy = false
    @Published var signingOut = false
    @Published var error = ""
    @Published var needsOfflineSignOut = false
    private var session: NativeSession?
    private var generation = UUID()
    private var refreshTask: Task<NativeSession, Error>?
    private var oauth: ASWebAuthenticationSession?
    private var restored = false
    private var signOutKey: String { "MyNotes.SignedOut.\(CloudCodec.hash(Data(origin.utf8)))" }

    static func validatedOrigin(_ value: String) throws -> URL {
        guard let url = URL(string: value), let host = url.host, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else { throw CloudError.message("Enter an HTTPS application origin, without a path. Localhost HTTP is supported for development.") }
        return url
    }
    private func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudError.message("Invalid server response.") }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 403, url.path.hasPrefix("/api/"), session != nil {
                session?.admitted = false
                if let session { try? SessionKeychain.save(session, origin: origin) }
                UserDefaults.standard.set(true, forKey: "MyNotes.Denied.\(origin)")
                workspace?.stop(); workspace = nil; self.error = "Account access was revoked or is unavailable. Local pending work is retained."
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw CloudError.http(response.statusCode, json?["error"] as? String ?? json?["msg"] as? String ?? json?["message"] as? String ?? "Request failed (\(response.statusCode)).")
        }
        return data
    }
    private func configuration() async throws -> CloudConfiguration {
        let url = try Self.validatedOrigin(origin); origin = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(origin, forKey: "MyNotes.APIOrigin")
        let config = try JSONDecoder().decode(CloudConfiguration.self, from: await request(URL(string: origin + "/api/v1/config")!))
        _ = try Self.validatedOrigin(config.supabaseUrl)
        return config
    }
    private func exchange(config: CloudConfiguration, grant: String, body: [String: String]) async throws -> TokenResponse {
        let url = URL(string: config.supabaseUrl + "/auth/v1/token?grant_type=" + grant)!
        return try JSONDecoder().decode(TokenResponse.self, from: await request(url, method: "POST", headers: ["apikey": config.publishableKey], body: CloudCodec.encode(body)))
    }
    private func accept(_ tokens: TokenResponse, config: CloudConfiguration, attempt: UUID) async throws {
        let data = try await request(URL(string: origin + "/api/v1/account")!, headers: ["Authorization": "Bearer \(tokens.access_token)"])
        let account = try JSONDecoder().decode(CloudAccount.self, from: data)
        guard attempt == generation, account.id.lowercased() == tokens.user.id.lowercased() else { throw CloudError.signedOut }
        let value = NativeSession(account: account, accessToken: tokens.access_token, refreshToken: tokens.refresh_token, expiresAt: Date().addingTimeInterval(Double(tokens.expires_in)), admitted: true, configuration: config)
        try SessionKeychain.save(value, origin: origin); UserDefaults.standard.set(false, forKey: signOutKey); session = value
        UserDefaults.standard.set(false, forKey: "MyNotes.Denied.\(origin)")
        needsOfflineSignOut = false
        try openWorkspace(account)
    }
    func signIn(email: String, password: String) async {
        guard !busy else { return }; busy = true; error = ""; generation = UUID(); let attempt = generation
        defer { busy = false }
        do { let config = try await configuration(); let token = try await exchange(config: config, grant: "password", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), "password": password]); try await accept(token, config: config, attempt: attempt) }
        catch { self.error = error.localizedDescription }
    }
    static func callbackCode(_ url: URL, expectedState: String) throws -> String {
        guard url.scheme == "mynotes", url.host == "auth", url.path == "/callback", url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw CloudError.invalidCallback }
        let items = parts.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == expectedState,
              items.filter({ $0.name == "code" }).count == 1, let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              !items.contains(where: { $0.name == "error" }) else { throw CloudError.invalidCallback }
        return code
    }
    func google() async {
        guard !busy else { return }; busy = true; error = ""; generation = UUID(); let attempt = generation
        defer { busy = false; oauth = nil }
        do {
            let config = try await configuration()
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CloudError.message("Unable to create a secure sign-in request.") }
            let verifier = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let state = UUID().uuidString.lowercased()
            var url = URLComponents(string: config.supabaseUrl + "/auth/v1/authorize")!
            url.queryItems = [URLQueryItem(name: "provider", value: "google"), URLQueryItem(name: "redirect_to", value: "mynotes://auth/callback?state=\(state)"), URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "s256")]
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let authentication = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "mynotes") { url, failure in
                    if let failure { continuation.resume(throwing: failure) } else if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: CloudError.invalidCallback) }
                }
                authentication.presentationContextProvider = self; oauth = authentication
                if !authentication.start() { continuation.resume(throwing: CloudError.message("Unable to open Google sign-in.")) }
            }
            guard attempt == generation else { throw CloudError.signedOut }
            let code = try Self.callbackCode(callback, expectedState: state)
            let token = try await exchange(config: config, grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
            try await accept(token, config: config, attempt: attempt)
        } catch { self.error = error.localizedDescription }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow() }
    func restore() async {
        guard !restored else { return }; restored = true; busy = true; defer { busy = false }
        do {
            _ = try Self.validatedOrigin(origin)
            try DesktopSyncEngine.cleanupMarkedAccounts(origin: origin)
            if UserDefaults.standard.bool(forKey: signOutKey) { try SessionKeychain.clear(origin); return }
            if UserDefaults.standard.bool(forKey: "MyNotes.Denied.\(origin)") { throw CloudError.message("Sign in again after your administrator restores access. Local pending work is retained.") }
            guard let cached = try SessionKeychain.load(origin), cached.admitted else { return }
            session = cached
            do {
                let account = try JSONDecoder().decode(CloudAccount.self, from: await api("/api/v1/account"))
                guard account.id == cached.account.id else { throw CloudError.signedOut }
                session?.account = account; try SessionKeychain.save(session!, origin: origin); try openWorkspace(account)
            } catch {
                if error is URLError || (error as? CloudError).map({ if case .http(let code, _) = $0 { return code >= 500 }; return false }) == true {
                    try openWorkspace(cached.account); workspace?.status = "Offline · local notebooks"
                } else { session?.admitted = false; if let session { try SessionKeychain.save(session, origin: origin) }; throw error }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func token(force: Bool = false) async throws -> String {
        guard let current = session, current.admitted else { throw CloudError.signedOut }
        if !force && current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        if let task = refreshTask { return try await task.value.accessToken }
        let attempt = generation
        let task = Task { @MainActor in
            let response = try await self.exchange(config: current.configuration, grant: "refresh_token", body: ["refresh_token": current.refreshToken])
            guard attempt == self.generation, response.user.id.lowercased() == current.account.id.lowercased() else { throw CloudError.signedOut }
            var next = current; next.accessToken = response.access_token; next.refreshToken = response.refresh_token; next.expiresAt = Date().addingTimeInterval(Double(response.expires_in))
            try SessionKeychain.save(next, origin: self.origin); self.session = next; return next
        }
        refreshTask = task; defer { refreshTask = nil }
        return try await task.value.accessToken
    }
    func api(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let attempt = generation
        do {
            let token = try await token(); let data = try await request(URL(string: origin + path)!, method: method, headers: ["Authorization": "Bearer \(token)"], body: body)
            guard attempt == generation else { throw CloudError.signedOut }; return data
        } catch CloudError.http(let code, _) where code == 401 {
            let token = try await token(force: true); let data = try await request(URL(string: origin + path)!, method: method, headers: ["Authorization": "Bearer \(token)"], body: body)
            guard attempt == generation else { throw CloudError.signedOut }; return data
        }
    }
    private func openWorkspace(_ account: CloudAccount) throws {
        let engine = try DesktopSyncEngine(account: account, origin: origin) { [weak self] path, method, body in guard let self else { throw CloudError.signedOut }; return try await self.api(path, method: method, body: body) }
        workspace = engine; engine.start()
    }
    func signOut(retainingWork: Bool = false) async {
        guard !signingOut else { return }; signingOut = true; error = ""; defer { signingOut = false }
        do {
            if !retainingWork, let workspace { try await workspace.synchronize(); guard try workspace.isClean() else { throw CloudError.message("Some local edits still need synchronization.") } }
            UserDefaults.standard.set(true, forKey: signOutKey)
            if let session { _ = try? await request(URL(string: session.configuration.supabaseUrl + "/auth/v1/logout?scope=local")!, method: "POST", headers: ["apikey": session.configuration.publishableKey, "Authorization": "Bearer \(session.accessToken)"]) }
            try SessionKeychain.clear(origin)
            let old = workspace; old?.stop(); generation = UUID(); refreshTask?.cancel(); refreshTask = nil; session = nil; workspace = nil
            if !retainingWork {
                old?.markForCleanup()
                let server = origin
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    if self?.workspace == nil { try? DesktopSyncEngine.cleanupMarkedAccounts(origin: server) }
                }
            }
            needsOfflineSignOut = false
        } catch { self.error = error.localizedDescription; needsOfflineSignOut = true }
    }
}
#endif
