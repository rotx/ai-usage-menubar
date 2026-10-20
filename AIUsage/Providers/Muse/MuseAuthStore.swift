import Foundation

struct MuseAuthStore: Sendable {
    static let keychainService = "ai.meta.dev.credentials"
    static let keychainAccount = "meta"
    // The first read may wait for the user to authenticate in a macOS prompt.
    static let keychainReadTimeout: TimeInterval = 60

    let environment: any EnvironmentReading
    let files: any TextFileAccessing
    let keychain: any KeychainAccessing

    init(
        environment: any EnvironmentReading = ProcessEnvironmentReader(),
        files: any TextFileAccessing = LocalTextFileAccessor(),
        keychain: any KeychainAccessing = SecurityKeychainAccessor(
            readTimeout: MuseAuthStore.keychainReadTimeout
        )
    ) {
        self.environment = environment
        self.files = files
        self.keychain = keychain
    }

    func loadAccessToken() throws -> String {
        let path = environment.value(for: "MUSE_AUTH_PATH") ??
            environment.value(for: "XDG_CONFIG_HOME").map { "\($0)/muse/auth.json" } ??
            "~/.config/muse/auth.json"
        if files.exists(path) {
            guard let text = try? files.readText(path),
                  let data = text.data(using: .utf8),
                  let document = try? JSONDecoder().decode(AuthDocument.self, from: data) else {
                throw ProviderFailure(.authentication, "Muse Code login could not be read. Run `muse login`.")
            }
            if let token = document.providers?.meta?.accessToken,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // An inline token selects the account. Never silently query another Keychain login.
                return try validated(token)
            }
        }
        let payload: String?
        do {
            payload = try keychain.readGenericPassword(
                service: Self.keychainService,
                account: Self.keychainAccount
            )
        } catch is ProcessRunnerError {
            throw ProviderFailure(
                .storage,
                "Muse Code Keychain access timed out. Choose Always Allow in the macOS prompt, then refresh."
            )
        } catch {
            throw ProviderFailure(
                .storage,
                "Muse Code Keychain access failed. Unlock your login keychain and allow access, then refresh."
            )
        }
        guard let payload, let data = payload.data(using: .utf8),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            throw ProviderFailure(.authentication, "Not logged in. Run `muse login`.")
        }
        return try validated(credentials.accessToken)
    }

    private func validated(_ raw: String?) throws -> String {
        let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard token.hasPrefix("dca:"), token.count > 4 else {
            throw ProviderFailure(.authentication, "Muse Code requires a subscription login. Run `muse login`.")
        }
        return token
    }

    private struct Credentials: Decodable {
        let accessToken: String?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    private struct AuthDocument: Decodable {
        let providers: Providers?
        struct Providers: Decodable { let meta: Credentials? }
    }
}
