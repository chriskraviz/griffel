import Foundation
import ServiceManagement

enum AppCleanupService {
    struct CleanupItemFailure: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let errorDescription: String
    }

    struct CleanupReport: Equatable {
        let removedURLs: [URL]
        let failedItems: [CleanupItemFailure]
        let knownInstallBundleURLs: [URL]
        /// The recordings folder that was deliberately left in place.
        var preservedLibraryURL: URL?

        var didSucceedFully: Bool {
            failedItems.isEmpty
        }
    }

    /// `libraryRootURL` is the folder holding the user's recordings and
    /// transcripts. Two rules, both load-bearing:
    ///
    /// * a library the user pointed at a folder of their own is **never**
    ///   touched here — deleting `~/Dropbox/Notizen` because someone pressed
    ///   "bereinigen" is unrecoverable;
    /// * the default library lives inside Application Support, which this used
    ///   to delete wholesale. Unless `deletesLibrary` is set it is now kept and
    ///   everything around it is removed.
    static func cleanupUserData(
        libraryRootURL: URL? = nil,
        deletesLibrary: Bool = true
    ) -> CleanupReport {
        KeychainService.delete(key: .openAIAPIKey)
        KeychainService.deleteLegacyItems()

        let preservedLibrary = preservedLibraryURL(libraryRootURL, deletesLibrary: deletesLibrary)
        var paths: [URL] = [
            AppSupportPaths.settingsURL,
            AppSupportPaths.cachesDirectoryURL,
            AppSupportPaths.preferencesURL,
            AppSupportPaths.savedApplicationStateDirectoryURL
        ]
            + AppSupportPaths.legacyAppSupportDirectoryURLs
            + AppSupportPaths.legacyCachesDirectoryURLs
            + AppSupportPaths.legacyPreferencesURLs
            + AppSupportPaths.legacySavedApplicationStateDirectoryURLs

        if preservedLibrary == nil {
            paths.insert(AppSupportPaths.appSupportDirectoryURL, at: 1)
        } else {
            paths.append(contentsOf: appSupportContents(excluding: preservedLibrary))
        }

        var report = cleanup(paths: paths, unregisterLaunchAtLogin: true)
        // A library outside Application Support is deliberately absent from
        // `paths`; report it so the UI can say where it stayed.
        report.preservedLibraryURL = preservedLibrary ?? externalLibraryURL(libraryRootURL)
        return report
    }

    static func removeLaunchAtLoginRegistration() -> CleanupReport {
        cleanup(paths: [], unregisterLaunchAtLogin: true)
    }

    static func removeApplicationSupportFiles(
        libraryRootURL: URL? = nil,
        deletesLibrary: Bool = true
    ) -> CleanupReport {
        KeychainService.delete(key: .openAIAPIKey)
        KeychainService.deleteLegacyItems()

        let preservedLibrary = preservedLibraryURL(libraryRootURL, deletesLibrary: deletesLibrary)
        var paths: [URL] = [AppSupportPaths.settingsURL]
            + AppSupportPaths.legacyAppSupportDirectoryURLs
        if preservedLibrary == nil {
            paths.insert(AppSupportPaths.appSupportDirectoryURL, at: 1)
        } else {
            paths.append(contentsOf: appSupportContents(excluding: preservedLibrary))
        }

        var report = cleanup(paths: paths, unregisterLaunchAtLogin: false)
        report.preservedLibraryURL = preservedLibrary ?? externalLibraryURL(libraryRootURL)
        return report
    }

    /// The library directory to keep, or nil when there is nothing to spare
    /// inside Application Support.
    private static func preservedLibraryURL(_ libraryRootURL: URL?, deletesLibrary: Bool) -> URL? {
        guard !deletesLibrary, let libraryRootURL else { return nil }
        guard isInsideAppSupport(libraryRootURL) else { return nil }
        guard FileManager.default.fileExists(atPath: libraryRootURL.path) else { return nil }
        return libraryRootURL
    }

    /// A library the user placed outside Application Support is never in the
    /// delete list to begin with.
    private static func externalLibraryURL(_ libraryRootURL: URL?) -> URL? {
        guard let libraryRootURL, !isInsideAppSupport(libraryRootURL) else { return nil }
        return FileManager.default.fileExists(atPath: libraryRootURL.path) ? libraryRootURL : nil
    }

    private static func isInsideAppSupport(_ url: URL) -> Bool {
        let root = AppSupportPaths.appSupportDirectoryURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    /// Everything directly inside Application Support except whatever holds the
    /// library, so the folder survives to keep holding it. The library may sit
    /// deeper than one level (the user can pick any folder), so a direct child
    /// that *contains* it has to be spared as well — deleting the ancestor
    /// would take the library with it.
    private static func appSupportContents(excluding preserved: URL?) -> [URL] {
        let root = AppSupportPaths.appSupportDirectoryURL
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        guard let preserved = preserved?.standardizedFileURL else { return contents }
        return contents.filter { child in
            let childPath = child.standardizedFileURL.path
            return childPath != preserved.path && !preserved.path.hasPrefix(childPath + "/")
        }
    }

    static func removeCacheAndStateFiles() -> CleanupReport {
        cleanup(
            paths: [
                AppSupportPaths.cachesDirectoryURL,
                AppSupportPaths.preferencesURL,
                AppSupportPaths.savedApplicationStateDirectoryURL
            ]
                + AppSupportPaths.legacyCachesDirectoryURLs
                + AppSupportPaths.legacyPreferencesURLs
                + AppSupportPaths.legacySavedApplicationStateDirectoryURLs,
            unregisterLaunchAtLogin: false
        )
    }

    static func knownInstallBundleURLs() -> [URL] {
        InstallLocationService.knownInstallBundleURLs
    }

    static func cleanup(paths: [URL], unregisterLaunchAtLogin: Bool) -> CleanupReport {
        var removedURLs: [URL] = []
        var failedItems: [CleanupItemFailure] = []

        if unregisterLaunchAtLogin {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                failedItems.append(
                    CleanupItemFailure(
                        url: InstallLocationService.bundleURL,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        for url in paths {
            do {
                try removeItemIfNeeded(at: url)
                removedURLs.append(url)
            } catch {
                failedItems.append(
                    CleanupItemFailure(
                        url: url,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        return CleanupReport(
            removedURLs: removedURLs,
            failedItems: failedItems,
            knownInstallBundleURLs: InstallLocationService.otherInstalledBundleURLs
        )
    }

    private static func removeItemIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}
