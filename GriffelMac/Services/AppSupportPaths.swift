import Foundation

enum AppSupportPaths {
    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.griffel.mac"

    /// Bundle identifiers of earlier generations of this app, newest first.
    /// Griffel is derived from Blitztext. Order matters: migration takes the
    /// first generation it finds, so the most recent data wins over an older
    /// folder left behind beside it — a future rename adds an entry at the
    /// top of these lists rather than replacing them.
    static let legacyBundleIdentifiers = [
        "app.blitztext.mac"
    ]

    /// Application Support folder names of those same generations, in the
    /// same order.
    private static let legacyAppSupportFolderNames = [
        "Blitztext"
    ]

    static var appSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Griffel", isDirectory: true)
    }

    /// Application Support folders of earlier generations, newest first.
    static var legacyAppSupportDirectoryURLs: [URL] {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return legacyAppSupportFolderNames.map { root.appendingPathComponent($0, isDirectory: true) }
    }

    static var settingsURL: URL {
        appSupportDirectoryURL.appendingPathComponent("settings.json")
    }

    static var statsURL: URL {
        appSupportDirectoryURL.appendingPathComponent("stats.json")
    }

    static var braindumpURL: URL {
        appSupportDirectoryURL.appendingPathComponent("braindump.json")
    }

    static var phrasesURL: URL {
        appSupportDirectoryURL.appendingPathComponent("phrases.json")
    }

    /// Default home for imported recordings and their transcripts. Inside
    /// Application Support on purpose: it is never picked up by iCloud Drive's
    /// Desktop & Documents sync, so audio does not start uploading itself
    /// behind a privacy promise. The user can point the library anywhere via
    /// `AppSettings.libraryPath`.
    static var defaultLibraryDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("Aufnahmen", isDirectory: true)
    }

    /// Index file at the root of whichever directory the library uses.
    static let libraryIndexFileName = "bibliothek.json"

    static var localModelsDirectoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("models", isDirectory: true)
    }

    static var whisperKitModelsDirectoryURL: URL {
        localModelsDirectoryURL.appendingPathComponent("whisperkit", isDirectory: true)
    }

    /// Hugging Face cache root for the local rewrite models (MLX/Qwen). Laid
    /// out by `HubCache`, so it holds `models--<org>--<repo>` folders rather
    /// than the flat variant folders WhisperKit uses.
    static var mlxModelsDirectoryURL: URL {
        localModelsDirectoryURL.appendingPathComponent("mlx", isDirectory: true)
    }

    static var defaultWhisperKitModelURL: URL {
        whisperKitModelsDirectoryURL.appendingPathComponent(
            "openai_whisper-large-v3-v20240930_626MB",
            isDirectory: true
        )
    }

    static var cachesDirectoryURL: URL {
        cachesDirectoryURL(for: bundleIdentifier)
    }

    static var legacyCachesDirectoryURLs: [URL] {
        legacyBundleIdentifiers.map(cachesDirectoryURL(for:))
    }

    static var preferencesURL: URL {
        preferencesURL(for: bundleIdentifier)
    }

    static var legacyPreferencesURLs: [URL] {
        legacyBundleIdentifiers.map(preferencesURL(for:))
    }

    static var savedApplicationStateDirectoryURL: URL {
        savedApplicationStateDirectoryURL(for: bundleIdentifier)
    }

    static var legacySavedApplicationStateDirectoryURLs: [URL] {
        legacyBundleIdentifiers.map(savedApplicationStateDirectoryURL(for:))
    }

    static func ensureAppSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: appSupportDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func cachesDirectoryURL(for identifier: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(identifier, isDirectory: true)
    }

    private static func preferencesURL(for identifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(identifier).plist")
    }

    private static func savedApplicationStateDirectoryURL(for identifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(identifier).savedState", isDirectory: true)
    }
}
