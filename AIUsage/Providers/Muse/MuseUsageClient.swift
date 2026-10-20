import Foundation

struct MuseUsageClient: Sendable {
    static let usageURL = URL(string: "https://api.meta.ai/muse-code/key")!
    let http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func fetchUsage(accessToken: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: .post,
            url: Self.usageURL,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "x-api-version": "1.0.0",
                "User-Agent": "AIUsage/0.1"
            ],
            body: Data(#"{"onboard":false}"#.utf8)
        ))
    }
}
