import AppKit
import XCTest
@testable import AIUsage

@MainActor
final class MenuBarLimitDisplayTests: XCTestCase {
    func testAutoChoosesHigherUsageInBothNumberModes() async {
        let store = await makeStore(windows: [
            QuotaWindow(kind: .session, usedPercent: 85, resetsAt: nil),
            QuotaWindow(kind: .weekly, usedPercent: 40, resetsAt: nil)
        ])
        let selectedLimits = [MenuBarProviderConfiguration(provider: .muse, metrics: [.session, .weekly])]
        for mode in UsageDisplayMode.allCases {
            let group = store.menuBarProviderReadings(for: selectedLimits, displayMode: mode,
                                                      limitDisplay: .automatic)[0]
            XCTAssertEqual(group.readings.map(\.metric), [.session])
            XCTAssertEqual(group.readings[0].value, .percentage(mode == .used ? 85 : 15))
            XCTAssertEqual(MenuBarProviderPresentation(group: group).metrics.first?.label, "S")

            let weeklyOnly = store.menuBarProviderReadings(for: configuration, displayMode: mode,
                                                           limitDisplay: .automatic)[0]
            XCTAssertEqual(weeklyOnly.readings.map(\.metric), [.weekly])
            XCTAssertNil(MenuBarProviderPresentation(group: weeklyOnly).metrics.first?.label)

            let hiddenLabels = store.menuBarProviderReadings(for: selectedLimits, displayMode: mode,
                limitDisplay: .automatic, showsSessionWeeklyLabels: false)[0]
            XCTAssertNil(MenuBarProviderPresentation(group: hiddenLabels).metrics.first?.label)
        }
    }

    func testAutoCanChooseWeeklyAndFallsBackToSingleWindow() async {
        for windows in [[QuotaWindow(kind: .weekly, usedPercent: 75, resetsAt: nil)],
                        [QuotaWindow(kind: .session, usedPercent: 20, resetsAt: nil),
                         QuotaWindow(kind: .weekly, usedPercent: 75, resetsAt: nil)]] {
            let store = await makeStore(windows: windows)
            XCTAssertEqual(store.menuBarProviderReadings(for: configuration,
                limitDisplay: .automatic)[0].readings.map(\.metric), [.weekly])
            let selectedLimits = [MenuBarProviderConfiguration(provider: .muse, metrics: [.session, .weekly])]
            let automatic = store.menuBarProviderReadings(for: selectedLimits, limitDisplay: .automatic)[0]
            XCTAssertEqual(MenuBarProviderPresentation(group: automatic).metrics.first?.label, "W")
            if windows.count == 1 {
                let stacked = store.menuBarProviderReadings(for: configuration, limitDisplay: .stacked)[0]
                XCTAssertEqual(stacked.readings.map(\.metric), [.weekly])
                XCTAssertFalse(stacked.isStacked)
            }
        }
    }

    func testBothIncludesSessionEvenWhenOnlyWeeklyWasSelected() async {
        let store = await makeStore(windows: [
            QuotaWindow(kind: .session, usedPercent: 20, resetsAt: nil),
            QuotaWindow(kind: .weekly, usedPercent: 75, resetsAt: nil)
        ])
        let selected = store.menuBarProviderReadings(for: configuration)[0]
        let both = store.menuBarProviderReadings(for: configuration, limitDisplay: .both)[0]
        let stacked = store.menuBarProviderReadings(for: configuration, limitDisplay: .stacked)[0]
        XCTAssertEqual(selected.readings.map(\.metric), [.weekly])
        XCTAssertEqual(both.readings.map(\.metric), [.session, .weekly])
        XCTAssertEqual(stacked.readings, both.readings)
        XCTAssertTrue(stacked.isStacked)
        let font = NSFont.menuBarFont(ofSize: 0)
        let horizontalImage = MenuBarStatusImageRenderer.image(for: [both], font: font)
        let stackedImage = MenuBarStatusImageRenderer.image(for: [stacked], font: font)
        XCTAssertTrue(stackedImage.isTemplate)
        XCTAssertLessThan(stackedImage.size.width, horizontalImage.size.width)
        XCTAssertLessThanOrEqual(stackedImage.size.height, 22)

        var withoutSigns = stacked
        withoutSigns.showsPercentSign = false
        let previewImages = [horizontalImage, stackedImage,
            MenuBarStatusImageRenderer.image(for: [withoutSigns], font: font)]
        let preview = NSImage(size: NSSize(width: 460, height: 180), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (index, title) in ["Side by side", "Stacked", "Stacked, percent signs hidden"].enumerated() {
                let y = CGFloat(140 - index * 50)
                (title as NSString).draw(at: NSPoint(x: 12, y: y), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black
                ])
                let image = previewImages[index]
                image.draw(in: NSRect(x: 220, y: y - 7, width: image.size.width * 2,
                                       height: image.size.height * 2),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        let attachment = XCTAttachment(image: preview)
        attachment.name = "Menu bar limit display modes"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLimitModesPreserveAdditionalSelectedMetrics() async {
        let store = await makeStore(windows: [
            QuotaWindow(kind: .session, usedPercent: 20, resetsAt: nil),
            QuotaWindow(kind: .weekly, usedPercent: 75, resetsAt: nil),
            QuotaWindow(kind: .sonnet, usedPercent: 42, resetsAt: nil)
        ])
        let configuration = [MenuBarProviderConfiguration(provider: .muse, metrics: [.weekly, .sonnet])]
        for mode in [MenuBarLimitDisplay.both, .stacked] {
            XCTAssertEqual(store.menuBarProviderReadings(for: configuration,
                limitDisplay: mode)[0].readings.map(\.metric), [.session, .weekly, .sonnet])
        }
        XCTAssertEqual(store.menuBarProviderReadings(for: configuration,
            limitDisplay: .automatic)[0].readings.map(\.metric), [.weekly, .sonnet])
    }

    func testHiddenPercentSignsPreserveAccessibilityAndMoney() {
        let readings = [MenuBarReading(provider: .muse, metric: .session, value: .percentage(48),
                                       displayMode: .remaining, isStale: true),
                        MenuBarReading(provider: .muse, metric: .weekly, value: .percentage(20),
                                       displayMode: .remaining, isStale: true)]
        for stacked in [false, true] {
            let group = MenuBarProviderReadings(provider: .muse, selectedMetrics: [.session, .weekly],
                readings: readings, isStacked: stacked, showsPercentSign: false)
            let presentation = MenuBarProviderPresentation(group: group)
            XCTAssertEqual(presentation.metrics.map(\.valueText), ["48", "20"])
            XCTAssertNil(presentation.sharedSuffix)
            XCTAssertTrue(presentation.metrics.allSatisfy(\.showsStaleIndicator))
            XCTAssertTrue(MenuBarReadingsPresentation(groups: [group]).accessibilityLabel.contains("48 percent left"))
        }
        let money = MenuBarReading(provider: .codex, metric: .extraUsage,
                                   value: .money(amount: 12, currencyCode: "USD"),
                                   displayMode: .used, isStale: false)
        XCTAssertEqual(MenuBarPresentation(reading: money).valueText,
                       MenuBarPresentation(reading: money, showsPercentSign: false).valueText)
    }

    func testPreferencesPersistAndMuseMigrationRunsOnce() throws {
        let suite = "LimitDisplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([ProviderID.claude]), forKey: "trackedProviderIDs.v1")
        defaults.set(true, forKey: "openUsageProvidersAdded.v1")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.menuBarLimitDisplay, .selected)
        XCTAssertTrue(preferences.showsMenuBarPercentSign)
        XCTAssertTrue(preferences.isTracking(.muse))
        preferences.menuBarLimitDisplay = .stacked
        preferences.showsMenuBarPercentSign = false
        preferences.setTracking(false, for: .muse)
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.menuBarLimitDisplay, .stacked)
        XCTAssertFalse(restored.showsMenuBarPercentSign)
        XCTAssertFalse(restored.isTracking(.muse))
    }

    private var configuration: [MenuBarProviderConfiguration] {
        [MenuBarProviderConfiguration(provider: .muse, metrics: [.weekly])]
    }

    private func makeStore(windows: [QuotaWindow]) async -> UsageStore {
        let snapshot = ProviderSnapshot(provider: .muse, planName: "Power", windows: windows, fetchedAt: Date())
        let store = UsageStore(providers: [SequencedProvider(id: .muse, results: [.success(snapshot)])],
                               availabilityChecker: FixedProviderAvailabilityChecker())
        await store.refresh()
        return store
    }
}
