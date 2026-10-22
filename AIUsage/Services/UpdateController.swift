import Observation
import Sparkle

@MainActor
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private(set) var availableVersion: String?
    private(set) var isChecking = false

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!
    @ObservationIgnored
    private let didStartUpdater: Bool

    init(
        startingUpdater: Bool = true,
        automaticallyChecksForUpdates: Bool = true
    ) {
        didStartUpdater = startingUpdater
        super.init()
        // Apply the preference before Sparkle starts, so a disabled check
        // never schedules the launch or daily appcast fetch.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        guard startingUpdater else { return }

        updaterController.updater.automaticallyChecksForUpdates =
            automaticallyChecksForUpdates
        updaterController.startUpdater()
        guard automaticallyChecksForUpdates else { return }

        isChecking = true
        updaterController.updater.checkForUpdateInformation()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard didStartUpdater else { return }

        updaterController.updater.automaticallyChecksForUpdates = enabled
        guard enabled else { return }

        isChecking = true
        updaterController.updater.checkForUpdateInformation()
    }

    var isUpdateAvailable: Bool {
        availableVersion != nil
    }

    func checkForUpdates() {
        isChecking = true
        updaterController.checkForUpdates(nil)
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        availableVersion = item.displayVersionString
        isChecking = false
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        isChecking = false
    }

    func updater(
        _ updater: SPUUpdater,
        didAbortWithError error: any Error
    ) {
        isChecking = false
    }
}
