import Foundation

// MARK: - Format Profiles

enum FormatProfile: String, Codable, CaseIterable, Identifiable {
    case terminal
    case email
    case chat
    case code

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .email: return "E-Mail"
        case .chat: return "Chat"
        case .code: return "Code-Kommentar"
        }
    }

    var promptInstruction: String {
        switch self {
        case .terminal:
            return "Der Text wird in ein Terminal eingefuegt. Gib ihn als knappe, technische Zeile(n) ohne Floskeln zurueck; klingt er nach einer Anweisung, formuliere einen praezisen Einzeiler. Keine Emojis, keine umschliessenden Anfuehrungszeichen."
        case .email:
            return "Der Text wird in eine E-Mail eingefuegt. Formatiere ihn als E-Mail-Text mit Absaetzen und, falls erkennbar, kurzer Anrede und Grussformel. Sachlich und freundlich."
        case .chat:
            return "Der Text wird in einen Chat (z.B. Slack oder Teams) eingefuegt. Formatiere ihn locker und knapp mit kurzen Saetzen; keine foermliche Anrede und keine Grussformel."
        case .code:
            return "Der Text wird in einen Code-Editor eingefuegt. Formatiere ihn als Code-Kommentar: kurze praezise Zeilen, Fachbegriffe unveraendert, keine Emojis."
        }
    }
}

struct FormatRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var bundleIdentifier: String
    var profile: FormatProfile
}

extension FormatRule {
    static let defaultRules: [FormatRule] = [
        FormatRule(bundleIdentifier: "com.apple.Terminal", profile: .terminal),
        FormatRule(bundleIdentifier: "com.googlecode.iterm2", profile: .terminal),
        FormatRule(bundleIdentifier: "dev.warp.Warp-Stable", profile: .terminal),
        FormatRule(bundleIdentifier: "com.mitchellh.ghostty", profile: .terminal),
        FormatRule(bundleIdentifier: "com.microsoft.Outlook", profile: .email),
        FormatRule(bundleIdentifier: "com.apple.mail", profile: .email),
        FormatRule(bundleIdentifier: "com.tinyspeck.slackmacgap", profile: .chat),
        FormatRule(bundleIdentifier: "com.microsoft.teams2", profile: .chat),
        FormatRule(bundleIdentifier: "com.hnc.Discord", profile: .chat),
        FormatRule(bundleIdentifier: "com.apple.dt.Xcode", profile: .code),
        FormatRule(bundleIdentifier: "com.microsoft.VSCode", profile: .code),
    ]
}

struct FormatProfileSettings: Codable {
    var enabled: Bool = false
    var rules: [FormatRule] = FormatRule.defaultRules

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        rules = try container.decodeIfPresent([FormatRule].self, forKey: .rules) ?? FormatRule.defaultRules
    }
}

enum FormatProfileService {
    static func profile(for bundleIdentifier: String?, settings: FormatProfileSettings) -> FormatProfile? {
        guard settings.enabled,
              let bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return nil
        }
        return settings.rules
            .first { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }?
            .profile
    }
}
