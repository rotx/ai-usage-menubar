import XCTest
@testable import AIUsage

final class MuseTests: XCTestCase {
    func testInlineLoginTakesPrecedenceOverKeychain() throws {
        let keychain = MemoryKeychain(generic: [MuseAuthStore.keychainService: #"{"access_token":"dca:other"}"#])
        let files = MemoryFiles(["/custom/auth.json": #"{"providers":{"meta":{"access_token":" dca:inline "}}}"#])
        let store = MuseAuthStore(environment: MockEnvironment(values: ["MUSE_AUTH_PATH": "/custom/auth.json"]),
                                  files: files, keychain: keychain)
        XCTAssertEqual(try store.loadAccessToken(), "dca:inline")
        XCTAssertTrue(keychain.accountReads.isEmpty)
    }

    func testKeychainLoginAndXDGOverride() throws {
        let files = MemoryFiles(["/config/muse/auth.json": #"{"providers":{"meta":{"mechanism":"oauth","storage":"keychain"}}}"#])
        let keychain = MemoryKeychain(generic: [MuseAuthStore.keychainService: #"{"api_key":"LLM|ignored","access_token":"dca:keychain"}"#])
        let store = MuseAuthStore(environment: MockEnvironment(values: ["XDG_CONFIG_HOME": "/config"]),
                                  files: files, keychain: keychain)
        XCTAssertEqual(try store.loadAccessToken(), "dca:keychain")
        XCTAssertEqual(keychain.accountReads.first?.service, MuseAuthStore.keychainService)
        XCTAssertEqual(keychain.accountReads.first?.account, "meta")
    }

    func testKeychainAuthenticationCanTakeLongerThanFiveSeconds() throws {
        let runner = PromptingKeychainRunner()
        let keychain = SecurityKeychainAccessor(
            processRunner: runner,
            readTimeout: MuseAuthStore.keychainReadTimeout
        )
        let store = MuseAuthStore(environment: MockEnvironment(), files: MemoryFiles(), keychain: keychain)

        XCTAssertEqual(try store.loadAccessToken(), "dca:authenticated")
        XCTAssertEqual(runner.lastTimeout, 60)
        XCTAssertEqual(runner.lastArguments, [
            "find-generic-password", "-s", MuseAuthStore.keychainService, "-a", "meta", "-w"
        ])
    }

    func testKeychainTimeoutExplainsHowToRetryWithoutRequestingUsage() async {
        let runner = PromptingKeychainRunner(alwaysTimesOut: true)
        let http = MockHTTPClient([])
        let provider = MuseProvider(
            authStore: MuseAuthStore(environment: MockEnvironment(), files: MemoryFiles(),
                keychain: SecurityKeychainAccessor(processRunner: runner,
                    readTimeout: MuseAuthStore.keychainReadTimeout)),
            client: MuseUsageClient(http: http)
        )
        do {
            _ = try await provider.fetch()
            XCTFail("Expected Keychain timeout")
        } catch let failure as ProviderFailure {
            XCTAssertEqual(failure.kind, .storage)
            XCTAssertTrue(failure.message.contains("Keychain access timed out"))
            XCTAssertTrue(failure.message.contains("Always Allow"))
            XCTAssertFalse(failure.message.contains("dca:"))
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }
        let requests = await http.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testInferenceKeyIsRejectedWithoutFallingBackToAnotherAccount() {
        let keychain = MemoryKeychain(generic: [MuseAuthStore.keychainService: #"{"access_token":"dca:other"}"#])
        let store = MuseAuthStore(environment: MockEnvironment(), files: MemoryFiles([
            "~/.config/muse/auth.json": #"{"providers":{"meta":{"access_token":"LLM|inference"}}}"#
        ]), keychain: keychain)
        XCTAssertThrowsError(try store.loadAccessToken())
        XCTAssertTrue(keychain.accountReads.isEmpty)
    }

    func testProviderRequestsSubscriptionWindowsWithDeviceToken() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = MockHTTPClient([httpResponse(json: """
        {"is_subs_active":true,"subs_tier_name":"Muse Code Power Usage",
         "api_key":"discarded","payment_method":"discarded",
         "subs_usage":{"window":{"window_duration_mins":300,"used_percent":24,"resets_at":1800018000},
                       "weekly":{"used_percent":68,"resets_at":1800604800}}}
        """)])
        let provider = MuseProvider(authStore: MuseAuthStore(environment: MockEnvironment(), files: MemoryFiles(),
            keychain: MemoryKeychain(generic: [MuseAuthStore.keychainService: #"{"access_token":"dca:login"}"#])),
            client: MuseUsageClient(http: http), dateProvider: FixedDateProvider(value: now))
        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.provider, .muse)
        XCTAssertEqual(snapshot.planName, "Muse Code Power Usage")
        XCTAssertEqual(snapshot.windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [24, 68])
        XCTAssertEqual(snapshot.sessionWindow?.resetsAt, Date(timeIntervalSince1970: 1_800_018_000))
        let requests = await http.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, MuseUsageClient.usageURL)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers["Authorization"], "Bearer dca:login")
        XCTAssertEqual(request.headers["x-api-version"], "1.0.0")
        XCTAssertEqual(request.body, Data(#"{"onboard":false}"#.utf8))
    }

    func testMissingWeeklyQuotaIsTreatedAsExhausted() throws {
        for usage in ["", ",\"subs_usage\":null"] {
            let snapshot = try MuseUsageMapper.map(response: httpResponse(json:
                "{\"is_subs_active\":true,\"subs_tier_name\":\"Power\"\(usage)}"), now: Date())
            XCTAssertEqual(snapshot.planName, "Power")
            XCTAssertNil(snapshot.sessionWindow)
            XCTAssertEqual(snapshot.window(for: .weekly)?.usedPercent, 100)
            XCTAssertEqual(snapshot.menuBarValue(for: .weekly, displayMode: .remaining), .percentage(0))
        }
    }

    func testMalformedAndInactiveResponsesAreRejected() {
        for json in [#"{"is_subs_active":true,"subs_usage":{"window":{"used_percent":"bad"}}}"#,
                     #"{"is_subs_active":true,"subs_usage":[]}"#,
                     #"{"is_subs_active":false}"#,
                     #"{"is_subs_active":true,"require_payment":true}"#] {
            XCTAssertThrowsError(try MuseUsageMapper.map(response: httpResponse(json: json), now: Date()))
        }
    }

    func testRateLimitCooldownPreventsManualRetry() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = MockHTTPClient([httpResponse(429, headers: ["Retry-After": "120"])])
        let provider = MuseProvider(authStore: MuseAuthStore(environment: MockEnvironment(), files: MemoryFiles(),
            keychain: MemoryKeychain(generic: [MuseAuthStore.keychainService: #"{"access_token":"dca:login"}"#])),
            client: MuseUsageClient(http: http), dateProvider: FixedDateProvider(value: now))
        for _ in 0..<2 {
            do { _ = try await provider.fetch(); XCTFail("Expected cooldown") }
            catch let failure as ProviderFailure {
                XCTAssertEqual(failure.kind, .rateLimited)
                XCTAssertEqual(failure.retryAt, now.addingTimeInterval(120))
            }
        }
        let requests = await http.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }
}

/// Simulates an eight-second macOS authorization prompt without a real delay or Keychain access.
private final class PromptingKeychainRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let alwaysTimesOut: Bool
    private var timeout: TimeInterval?
    private var arguments: [String]?

    init(alwaysTimesOut: Bool = false) { self.alwaysTimesOut = alwaysTimesOut }

    var lastTimeout: TimeInterval? { lock.withLock { timeout } }
    var lastArguments: [String]? { lock.withLock { arguments } }

    func run(executable: String, arguments: [String], environment: [String: String],
             timeout: TimeInterval) throws -> ProcessResult {
        lock.withLock {
            self.timeout = timeout
            self.arguments = arguments
        }
        guard !alwaysTimesOut, timeout >= 8 else {
            throw ProcessRunnerError.timedOut(executable: executable, timeout: timeout)
        }
        return ProcessResult(exitCode: 0, stdout: #"{"access_token":"dca:authenticated"}"#, stderr: "")
    }
}
