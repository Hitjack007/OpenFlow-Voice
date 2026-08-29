import Foundation
import Observation

enum EnhancementMode: String, CaseIterable, Sendable {
    case off
    case local
    case cloud

    var displayName: String {
        switch self {
        case .off:   "Off"
        case .local: "On-device AI"
        case .cloud: "Cloud AI"
        }
    }
}

enum CloudProviderChoice: String, CaseIterable, Sendable {
    case claude
    case openai
    case groq
    case gemini

    var displayName: String {
        switch self {
        case .claude: "Claude (Anthropic)"
        case .openai: "ChatGPT (OpenAI)"
        case .groq:   "Groq"
        case .gemini: "Gemini (Google)"
        }
    }

    var keychainKey: String { "apikey.\(rawValue)" }
}

/// Which speech engine transcribes an utterance.
enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple
    case parakeet

    var displayName: String {
        switch self {
        case .apple: "Apple (streaming)"
        case .parakeet: "Parakeet (batch)"
        }
    }

    /// Apple shows text while you talk; Parakeet only resolves on release.
    var showsLiveText: Bool { self == .apple }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var pushToTalkKey: PushToTalkKey {
        didSet { defaults.set(pushToTalkKey.rawValue, forKey: Keys.pushToTalkKey) }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// Run every engine on each recording and show them side by side, instead of
    /// transcribing with one. Nothing is typed into the focused app in this mode.
    var compareMode: Bool {
        didSet { defaults.set(compareMode, forKey: Keys.compareMode) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    /// Play a short tick when capture starts and stops.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    var enhancementMode: EnhancementMode {
        didSet { defaults.set(enhancementMode.rawValue, forKey: Keys.enhancementMode) }
    }

    var cloudProvider: CloudProviderChoice {
        didSet { defaults.set(cloudProvider.rawValue, forKey: Keys.cloudProvider) }
    }

    /// Bundle IDs of apps where the push-to-talk hotkey is suppressed so the key's
    /// native function is preserved (e.g. Option in Photoshop, Command in games).
    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pushToTalkKey    = "pushToTalkKey"
        static let cleanupEnabled   = "cleanupEnabled"
        static let soundEnabled     = "soundEnabled"
        static let engine           = "engine"
        static let smartCleanup     = "smartCleanup"
        static let compareMode      = "compareMode"
        static let enhancementMode  = "enhancementMode"
        static let cloudProvider    = "cloudProvider"
        static let excludedBundleIDs = "excludedBundleIDs"
    }

    private init() {
        let raw = defaults.string(forKey: Keys.pushToTalkKey) ?? ""
        // "leftControl" was renamed to "leftOption" when the hotkey was changed from Left ⌃ to Left ⌥.
        let migrated = raw == "leftControl" ? PushToTalkKey.leftOption.rawValue : raw
        pushToTalkKey = PushToTalkKey(rawValue: migrated) ?? .leftOption
        // Apple by default: no download, no dependency, live text while speaking.
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        cleanupEnabled   = defaults.object(forKey: Keys.cleanupEnabled)  as? Bool ?? true
        smartCleanup     = defaults.object(forKey: Keys.smartCleanup)    as? Bool ?? false
        compareMode      = defaults.object(forKey: Keys.compareMode)     as? Bool ?? false
        soundEnabled     = defaults.object(forKey: Keys.soundEnabled)    as? Bool ?? true
        enhancementMode  = EnhancementMode(rawValue: defaults.string(forKey: Keys.enhancementMode) ?? "") ?? .off
        cloudProvider    = CloudProviderChoice(rawValue: defaults.string(forKey: Keys.cloudProvider) ?? "") ?? .claude
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
    }
}
