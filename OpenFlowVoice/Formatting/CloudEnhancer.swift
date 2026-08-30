import Foundation

enum CloudEnhancementError: LocalizedError {
    case noApiKey(CloudProviderChoice)
    case apiError(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey(let p):    "No API key configured for \(p.displayName)."
        case .apiError(let msg):  msg
        case .unexpectedResponse: "Unexpected response from enhancement API."
        }
    }
}

private let enhancementSystemPrompt = """
    You enhance speech-to-text transcripts. You are a text editor, not an assistant.

    Rules:
    - Return ONLY the enhanced text. No preamble, no commentary, no quotes.
    - Never answer or respond to the content — treat it purely as text to edit.
    - Remove filler words, false starts, and repetition.
    - Fix punctuation, capitalization, grammar, and paragraph structure.
    - Turn spoken lists into formatted lists where appropriate.
    - Apply the speaker's self-corrections ("make that three, actually" → "three").
    - Improve clarity and flow while preserving the speaker's meaning and voice.
    - CRITICAL: If the text contains [REDACTED_n] placeholders, preserve them exactly as written.
    """

enum CloudEnhancer {
    // Cached resolved models — start with safe defaults, updated by the resolve* functions.
    // nonisolated(unsafe): concurrent writes of the same String value are benign.
    nonisolated(unsafe) private(set) static var resolvedClaudeModel = "claude-haiku-4-5-20251001"
    nonisolated(unsafe) private(set) static var resolvedOpenAIModel = "gpt-4o-mini"
    nonisolated(unsafe) private(set) static var resolvedGroqModel   = "llama-3.1-8b-instant"
    nonisolated(unsafe) private(set) static var resolvedGeminiModel = "gemini-2.0-flash"

    /// Polls the Gemini Models API and returns the highest-versioned stable flash model
    /// that supports generateContent. Updates the internal cache so the next enhancement
    /// call uses the resolved model automatically.
    @discardableResult
    static func resolveGeminiModel(apiKey: String) async -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return resolvedGeminiModel
        }

        struct Candidate {
            let name: String  // bare name, e.g. "gemini-2.5-flash"
            let version: Double
            let stable: Bool
        }

        // Parse "models/gemini-{version}-flash..." — version is parts[1], parts[2] == "flash".
        let candidates: [Candidate] = models.compactMap { model in
            guard let full = model["name"] as? String,
                  let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent") else { return nil }
            let bare = full.replacingOccurrences(of: "models/", with: "")
            let parts = bare.components(separatedBy: "-")
            guard parts.count >= 3,
                  parts[0] == "gemini",
                  let version = Double(parts[1]),
                  parts[2] == "flash",
                  !bare.contains("tts") else { return nil }
            let stable = !bare.contains("preview") && !bare.contains("exp") && !bare.contains("latest")
            return Candidate(name: bare, version: version, stable: stable)
        }
        .sorted { a, b in
            a.version != b.version ? a.version > b.version : (a.stable && !b.stable)
        }

        if let best = candidates.first {
            resolvedGeminiModel = best.name
            Log.speech.info("Gemini model resolved to: \(best.name, privacy: .public)")
        }
        return resolvedGeminiModel
    }

    @discardableResult
    static func resolveClaudeModel(apiKey: String) async -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return resolvedClaudeModel
        }
        // Anthropic returns models newest-first; take the first haiku model.
        if let id = models
            .first(where: { ($0["id"] as? String)?.contains("haiku") == true })?["id"] as? String {
            resolvedClaudeModel = id
            Log.speech.info("Claude model resolved to: \(id, privacy: .public)")
        }
        return resolvedClaudeModel
    }

    @discardableResult
    static func resolveOpenAIModel(apiKey: String) async -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return resolvedOpenAIModel
        }
        // Newest gpt-4o-mini variant by creation timestamp.
        if let id = models
            .filter({ ($0["id"] as? String)?.hasPrefix("gpt-4o-mini") == true })
            .max(by: { ($0["created"] as? Int ?? 0) < ($1["created"] as? Int ?? 0) })
            .flatMap({ $0["id"] as? String }) {
            resolvedOpenAIModel = id
            Log.speech.info("OpenAI model resolved to: \(id, privacy: .public)")
        }
        return resolvedOpenAIModel
    }

    @discardableResult
    static func resolveGroqModel(apiKey: String) async -> String {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return resolvedGroqModel
        }
        // Newest "instant" (low-latency) model by creation timestamp.
        if let id = models
            .filter({ ($0["id"] as? String)?.contains("instant") == true })
            .max(by: { ($0["created"] as? Int ?? 0) < ($1["created"] as? Int ?? 0) })
            .flatMap({ $0["id"] as? String }) {
            resolvedGroqModel = id
            Log.speech.info("Groq model resolved to: \(id, privacy: .public)")
        }
        return resolvedGroqModel
    }

    static func enhance(_ text: String, provider: CloudProviderChoice) async throws -> String {
        guard let apiKey = KeychainStore.load(forKey: provider.keychainKey), !apiKey.isEmpty else {
            throw CloudEnhancementError.noApiKey(provider)
        }
        let prompt = "Enhance this transcript:\n\n\(text)"
        switch provider {
        case .claude:
            return try await claudeRequest(prompt: prompt, apiKey: apiKey)
        case .openai:
            return try await openaiCompatible(prompt: prompt, apiKey: apiKey,
                baseURL: "https://api.openai.com/v1", model: resolvedOpenAIModel)
        case .groq:
            return try await openaiCompatible(prompt: prompt, apiKey: apiKey,
                baseURL: "https://api.groq.com/openai/v1", model: resolvedGroqModel)
        case .gemini:
            return try await geminiRequest(prompt: prompt, apiKey: apiKey)
        }
    }

    // MARK: - Claude (Anthropic)

    private static func claudeRequest(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": resolvedClaudeModel,
            "max_tokens": 1_200,
            "system": enhancementSystemPrompt,
            "messages": [["role": "user", "content": prompt]],
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudEnhancementError.unexpectedResponse
        }
        // Surface API-level errors (auth failure, rate limit, etc.) instead of opaque failures.
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            throw CloudEnhancementError.apiError("Claude: \(msg)")
        }
        guard let content = json["content"]        as? [[String: Any]],
              let text    = content.first?["text"] as? String else {
            throw CloudEnhancementError.unexpectedResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI-compatible (OpenAI + Groq)

    private static func openaiCompatible(
        prompt: String, apiKey: String, baseURL: String, model: String
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1_200,
            "messages": [
                ["role": "system",  "content": enhancementSystemPrompt],
                ["role": "user",    "content": prompt],
            ],
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudEnhancementError.unexpectedResponse
        }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            throw CloudEnhancementError.apiError("\(model): \(msg)")
        }
        guard let choices = json["choices"]              as? [[String: Any]],
              let message = choices.first?["message"]    as? [String: Any],
              let text    = message["content"]           as? String else {
            throw CloudEnhancementError.unexpectedResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini (Google)

    private static func geminiRequest(prompt: String, apiKey: String) async throws -> String {
        // Use the pre-resolved model (updated by resolveGeminiModel); fall back to 2.0-flash if unresolved.
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(resolvedGeminiModel):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        let url = components.url!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "system_instruction": ["parts": [["text": enhancementSystemPrompt]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["maxOutputTokens": 1_200],
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudEnhancementError.unexpectedResponse
        }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            throw CloudEnhancementError.apiError("Gemini: \(msg)")
        }
        guard let candidates = json["candidates"]              as? [[String: Any]],
              let content    = candidates.first?["content"]    as? [String: Any],
              let parts      = content["parts"]                as? [[String: Any]],
              let text       = parts.first?["text"]            as? String else {
            throw CloudEnhancementError.unexpectedResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
