import Foundation

actor MuseProvider: UsageProvider {
    nonisolated let id = ProviderID.muse
    private let authStore: MuseAuthStore
    private let client: MuseUsageClient
    private let dateProvider: any DateProviding
    private var retryAt: Date?

    init(
        authStore: MuseAuthStore = MuseAuthStore(),
        client: MuseUsageClient = MuseUsageClient(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.authStore = authStore
        self.client = client
        self.dateProvider = dateProvider
    }

    func fetch() async throws -> ProviderSnapshot {
        let now = dateProvider.now()
        if let retryAt, now < retryAt {
            throw ProviderFailure(.rateLimited, "Muse Code usage requests are rate limited.", retryAt: retryAt)
        }
        let token = try authStore.loadAccessToken()
        do {
            let response = try await client.fetchUsage(accessToken: token)
            let snapshot = try MuseUsageMapper.map(response: response, now: now)
            retryAt = nil
            return snapshot
        } catch let failure as ProviderFailure {
            if failure.kind == .rateLimited { retryAt = failure.retryAt }
            throw failure
        } catch {
            throw ProviderFailure(.transient, "Muse Code could not be reached.")
        }
    }
}
