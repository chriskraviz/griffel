import Foundation
import OSLog

/// One-time migration of user data from an earlier generation of this app
/// (Application Support folder and Keychain service) to Griffel — the app is
/// derived from Blitztext. With more than one legacy generation on disk, the
/// newest one that exists wins.
enum LegacyMigrationService {
    private static let logger = Logger(subsystem: "app.griffel.mac", category: "Migration")

    /// True when this launch moved legacy data over. Read by the settings UI
    /// to show one-time hints (e.g. Login-Item neu aktivieren).
    private(set) static var didMigrateThisLaunch = false

    /// Idempotent. Must run BEFORE AppState loads settings, so settings.json
    /// is already at the new location when it is first read.
    /// No step deletes source data before its destination is verified.
    static func migrateIfNeeded() {
        migrateAppSupportFolderIfNeeded()
        KeychainService.migrateLegacyItemsIfNeeded()
    }

    private static func migrateAppSupportFolderIfNeeded() {
        let fileManager = FileManager.default
        let newURL = AppSupportPaths.appSupportDirectoryURL

        // Newest generation first: with more than one legacy folder on disk,
        // the newest holds the current data and the older ones are what its
        // own migration left behind.
        guard !fileManager.fileExists(atPath: AppSupportPaths.settingsURL.path),
              let legacyURL = AppSupportPaths.legacyAppSupportDirectoryURLs
                  .first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return
        }

        // An earlier launch may have created the new folder without writing anything.
        if let contents = try? fileManager.contentsOfDirectory(atPath: newURL.path), contents.isEmpty {
            try? fileManager.removeItem(at: newURL)
        }

        if !fileManager.fileExists(atPath: newURL.path) {
            // Same-volume rename: atomic and instant even with large local models.
            do {
                try fileManager.moveItem(at: legacyURL, to: newURL)
                didMigrateThisLaunch = true
                logger.info("Migrated legacy data folder to Griffel.")
                return
            } catch {
                logger.error("Legacy folder move failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Fallback: a partial new folder already exists or the move failed.
        // Copy only settings.json and leave the legacy folder untouched.
        let legacySettingsURL = legacyURL.appendingPathComponent("settings.json")
        guard fileManager.fileExists(atPath: legacySettingsURL.path) else { return }
        do {
            try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacySettingsURL, to: AppSupportPaths.settingsURL)
            didMigrateThisLaunch = true
            logger.info("Copied legacy settings.json; legacy folder left in place.")
        } catch {
            logger.error("Legacy settings copy failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
