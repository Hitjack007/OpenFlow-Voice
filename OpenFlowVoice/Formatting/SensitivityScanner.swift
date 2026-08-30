import Foundation

struct SensitiveMatch: Equatable, Sendable {
    enum Kind: String, CaseIterable, Equatable, Hashable, Sendable {
        case pin, password, email, creditCard, ssn, phoneNumber, apiKey

        var displayName: String {
            switch self {
            case .pin:         "PIN / passcode"
            case .password:    "Password"
            case .email:       "Email address"
            case .creditCard:  "Credit card number"
            case .ssn:         "Social Security Number"
            case .phoneNumber: "Phone number"
            case .apiKey:      "API key / token"
            }
        }
    }

    let kind: Kind
    let placeholder: String   // "[REDACTED_0]"
    let original: String      // the actual sensitive value
    let nsRange: NSRange      // location in the scanned string
}

enum SensitivityScanner {
    private struct RulePattern {
        let kind: SensitiveMatch.Kind
        let regex: NSRegularExpression
        let captureGroup: Int
    }

    private static let rules: [RulePattern] = buildRules()

    /// Scans `text` and returns sensitive matches sorted by location.
    static func scan(_ text: String) -> [SensitiveMatch] {
        var results: [SensitiveMatch] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for rule in rules {
            for hit in rule.regex.matches(in: text, range: fullRange) {
                guard hit.numberOfRanges > rule.captureGroup else { continue }
                let valueRange = hit.range(at: rule.captureGroup)
                guard valueRange.location != NSNotFound else { continue }
                guard !results.contains(where: { overlaps($0.nsRange, valueRange) }) else { continue }
                results.append(SensitiveMatch(
                    kind: rule.kind,
                    placeholder: "[REDACTED_\(results.count)]",
                    original: nsText.substring(with: valueRange),
                    nsRange: valueRange
                ))
            }
        }
        return results.sorted { $0.nsRange.location < $1.nsRange.location }
    }

    /// Replaces each match's span with its placeholder token.
    /// Skips display-only matches (NSNotFound location) that carry no redactable range.
    static func redact(_ text: String, matches: [SensitiveMatch]) -> String {
        var result = text as NSString
        for match in matches.reversed() {
            guard match.nsRange.location != NSNotFound, match.nsRange.length > 0 else { continue }
            result = result.replacingCharacters(in: match.nsRange, with: match.placeholder) as NSString
        }
        return result as String
    }

    private static func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location < b.location + b.length && b.location < a.location + a.length
    }

    private static func buildRules() -> [RulePattern] {
        func rule(_ kind: SensitiveMatch.Kind, _ pattern: String, group: Int = 1) -> RulePattern? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return RulePattern(kind: kind, regex: re, captureGroup: group)
        }

        // Spoken digit words: "one two three four" or "one, two, three, four"
        let spokenDigits = #"(?:zero|one|two|three|four|five|six|seven|eight|nine)(?:[,\s]+(?:zero|one|two|three|four|five|six|seven|eight|nine)){2,7}"#

        // Bridges between a keyword and its value in natural speech.
        // Alternative 1: up to 8 non-"is" words then mandatory "is"  → "password to the door is 1234"
        // Alternative 2: direct, with optional "is"                   → "password is 1234" / "password 1234"
        let gap = #"(?:(?:\s+(?!is\b)\w+){1,8}\s+is\s+|\s+(?:is\s+)?)"#

        return [
            // PIN / passcode — broad keyword set, up to 8 intervening words
            rule(.pin, #"(?:pin(?:\s*code)?|passcode|pass\s*code|security\s*code|access\s*code|door\s*code|gate\s*code|entry\s*code|lock\s*code|combination)\#(gap)(\d{4,8}|\#(spokenDigits))"#),

            // Password — broad keyword set, up to 8 intervening words
            rule(.password, #"(?:password|passwd|passphrase|pass\s*phrase)\#(gap)([A-Za-z0-9!@#$%^&*\-_\.]{4,}|\#(spokenDigits))"#),

            // Email address — structural; @ makes these highly distinctive without needing a keyword
            rule(.email, #"(\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b)"#),

            // 16-digit credit card (optional spaces or dashes between groups)
            rule(.creditCard, #"(\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b)"#),

            // SSN: 000-00-0000
            rule(.ssn, #"(\b\d{3}[\s\-]\d{2}[\s\-]\d{4}\b)"#),

            // Phone numbers — structural US/international match
            rule(.phoneNumber, #"(\b(?:\+?1[\s\-\.]?)?\(?\d{3}\)?[\s\-\.]?\d{3}[\s\-\.]?\d{4}\b)"#),

            // Phone numbers — keyword-triggered for looser spoken forms ("my number is 555 1234567")
            rule(.phoneNumber, #"(?:phone(?:\s*number)?|cell(?:\s*phone)?|mobile|contact(?:\s*number)?|number)\#(gap)(\+?[\d][\d\s\-\.\(\)]{6,18}[\d])"#),

            // API key / token / secret — broad keyword set, up to 8 intervening words
            rule(.apiKey, #"(?:api[\s_\-]?key|token|secret|bearer|auth(?:entication)?\s*(?:key|token)?|private\s*key)\#(gap)([A-Za-z0-9_\-\.]{20,})"#),
        ].compactMap { $0 }
    }
}
