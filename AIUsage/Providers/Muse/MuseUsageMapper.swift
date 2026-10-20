import Foundation

/// Decode quota fields only; inference keys and payment metadata are never retained.
enum MuseUsageMapper {
    static func map(response: HTTPResponse, now: Date) throws -> ProviderSnapshot {
        switch response.statusCode {
        case 401, 403:
            throw ProviderFailure(.authentication, "Muse Code session expired. Run `muse login`.")
        case 429:
            throw ProviderFailure(.rateLimited, "Muse Code usage requests are rate limited.",
                                  retryAt: ProviderParsing.retryDate(from: response, now: now))
        case 500...599:
            throw ProviderFailure(.transient, "Muse Code could not be reached.")
        case 200..<300: break
        default:
            throw ProviderFailure(.invalidResponse, "Muse Code usage request failed (\(response.statusCode)).")
        }
        guard let document = try? JSONDecoder().decode(UsageDocument.self, from: response.body) else {
            throw ProviderFailure(.invalidResponse, "Muse Code quota response changed.")
        }
        guard document.requirePayment != true else {
            throw ProviderFailure(.authentication, "Finish Muse Code billing at dev.meta.ai.")
        }
        guard document.isSubscriptionActive == true else {
            throw ProviderFailure(.authentication, "No Muse Code subscription is active on this login.")
        }
        var windows: [QuotaWindow] = []
        if let usage = document.usage {
            for (kind, window) in [(QuotaKind.session, usage.window), (.weekly, usage.weekly)] {
                guard let window else { continue }
                guard window.usedPercent.isFinite else {
                    throw ProviderFailure(.invalidResponse, "Muse Code returned an invalid quota percentage.")
                }
                if kind == .session,
                   let minutes = window.durationMinutes,
                   (!minutes.isFinite || minutes <= 0) {
                    throw ProviderFailure(.invalidResponse, "Muse Code returned an invalid session duration.")
                }
                let reset = window.resetsAt.flatMap { seconds -> Date? in
                    guard seconds.isFinite, seconds > 0, seconds <= 64_092_211_200 else { return nil }
                    return Date(timeIntervalSince1970: seconds)
                }
                windows.append(QuotaWindow(kind: kind,
                                           usedPercent: min(max(window.usedPercent, 0), 100),
                                           resetsAt: reset))
            }
        }
        // Requested fallback for an exhausted Meta subscription whose login omits weekly usage.
        if !windows.contains(where: { $0.kind == .weekly }) {
            windows.append(QuotaWindow(kind: .weekly, usedPercent: 100, resetsAt: nil))
        }
        return ProviderSnapshot(provider: .muse, planName: document.planName,
                                windows: windows, fetchedAt: now)
    }

    private struct UsageDocument: Decodable {
        let isSubscriptionActive: Bool?
        let requirePayment: Bool?
        let planName: String?
        let usage: Usage?
        enum CodingKeys: String, CodingKey {
            case isSubscriptionActive = "is_subs_active"
            case requirePayment = "require_payment"
            case planName = "subs_tier_name"
            case usage = "subs_usage"
        }
    }

    private struct Usage: Decodable {
        let window: Window?
        let weekly: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let resetsAt: Double?
        let durationMinutes: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetsAt = "resets_at"
            case durationMinutes = "window_duration_mins"
        }
    }
}
