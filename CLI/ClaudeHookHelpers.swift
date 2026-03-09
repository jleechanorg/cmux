// ClaudeHookHelpers.swift — Testable pure-logic helpers for claude-hook notification processing.
// Extracted from cmux.swift so unit tests can exercise classification, parsing, and summarization
// without needing a live socket connection or workspace.

import Foundation

/// Parsed representation of the JSON stdin that Claude Code sends to hook commands.
struct ClaudeHookParsedNotification {
    let rawInput: String
    let object: [String: Any]?
    let sessionId: String?
    let cwd: String?
    let transcriptPath: String?
    let notificationType: String?
}

// MARK: - Notification Helpers

enum ClaudeHookHelpers {

    // MARK: Parse

    /// Parse raw JSON stdin from a Claude Code hook invocation into structured fields.
    static func parseInput(_ rawInput: String) -> ClaudeHookParsedNotification {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any] else {
            return ClaudeHookParsedNotification(
                rawInput: rawInput, object: nil, sessionId: nil,
                cwd: nil, transcriptPath: nil, notificationType: nil
            )
        }

        let sessionId = extractSessionId(from: object)
        let cwd = extractCWD(from: object)
        let transcriptPath = firstString(in: object, keys: ["transcript_path", "transcriptPath"])
        let notificationType = firstString(in: object, keys: ["notification_type", "notificationType"])
        return ClaudeHookParsedNotification(
            rawInput: rawInput, object: object, sessionId: sessionId,
            cwd: cwd, transcriptPath: transcriptPath, notificationType: notificationType
        )
    }

    // MARK: Classify

    /// Classify a notification into a category (subtitle) and descriptive body.
    static func classifyNotification(signal: String, message: String) -> (subtitle: String, body: String) {
        let lower = "\(signal) \(message)".lowercased()
        if lower.contains("permission") || lower.contains("approve") || lower.contains("approval") {
            let body = message.isEmpty ? "Approval needed" : message
            return ("Permission", body)
        }
        if lower.contains("error") || lower.contains("failed") || lower.contains("exception") {
            let body = message.isEmpty ? "Claude reported an error" : message
            return ("Error", body)
        }
        if lower.contains("idle") || lower.contains("wait") || lower.contains("input") || lower.contains("prompt") {
            let body = message.isEmpty ? "Claude is waiting for your input" : message
            return ("Waiting", body)
        }
        let body = message.isEmpty ? "Claude needs your input" : message
        return ("Attention", body)
    }

    // MARK: Summarize

    /// Build a (subtitle, body) summary from raw Claude Code notification JSON.
    static func summarizeNotification(rawInput: String) -> (subtitle: String, body: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("Waiting", "Claude is waiting for your input")
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any] else {
            let fallback = truncate(normalizedSingleLine(trimmed), maxLength: 180)
            return classifyNotification(signal: fallback, message: fallback)
        }

        let nested = (object["notification"] as? [String: Any]) ?? (object["data"] as? [String: Any]) ?? [:]
        let signalParts = [
            firstString(in: object, keys: ["event", "event_name", "hook_event_name", "type", "kind"]),
            firstString(in: object, keys: ["notification_type", "matcher", "reason"]),
            firstString(in: nested, keys: ["type", "kind", "reason"])
        ]
        let messageCandidates = [
            firstString(in: object, keys: ["message", "body", "text", "prompt", "error", "description"]),
            firstString(in: nested, keys: ["message", "body", "text", "prompt", "error", "description"])
        ]
        let session = firstString(in: object, keys: ["session_id", "sessionId"])
        let message = messageCandidates.compactMap { $0 }.first ?? "Claude needs your input"
        let dedupedMessage = dedupeBranchContextLines(message)
        let normalizedMessage = normalizedSingleLine(dedupedMessage)
        let signal = signalParts.compactMap { $0 }.joined(separator: " ")
        var classified = classifyNotification(signal: signal, message: normalizedMessage)

        if let session, !session.isEmpty {
            let shortSession = String(session.prefix(8))
            if !classified.body.contains(shortSession) {
                classified.body = "\(classified.body) [\(shortSession)]"
            }
        }

        classified.body = truncate(classified.body, maxLength: 180)
        return classified
    }

    // MARK: - Internal Helpers

    static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func normalizedSingleLine(_ value: String) -> String {
        let collapsed = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        let index = value.index(value.startIndex, offsetBy: max(0, maxLength - 1))
        return String(value[..<index]) + "…"
    }

    static func sanitizeNotificationField(_ value: String) -> String {
        let normalized = normalizedSingleLine(value)
            .replacingOccurrences(of: "|", with: "¦")
        return truncate(normalized, maxLength: 180)
    }

    static func dedupeBranchContextLines(_ value: String) -> String {
        let lines = value.components(separatedBy: .newlines)
        guard lines.count > 1 else { return value }

        var lastIndexByPath: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            guard let path = branchContextPath(from: line) else { continue }
            lastIndexByPath[path] = index
        }
        guard !lastIndexByPath.isEmpty else { return value }

        let deduped = lines.enumerated().compactMap { index, line -> String? in
            guard let path = branchContextPath(from: line) else { return line }
            return lastIndexByPath[path] == index ? line : nil
        }
        return deduped.joined(separator: "\n")
    }

    // MARK: - Private

    private static func branchContextPath(from line: String) -> String? {
        let parts = line.split(separator: "•", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let branch = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, !path.isEmpty else { return nil }

        let looksLikePath = path.hasPrefix("/") || path.hasPrefix("~") || path.hasPrefix(".") || path.contains("/")
        guard looksLikePath else { return nil }

        let trimmedQuotes = path.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
        let expanded = NSString(string: trimmedQuotes).expandingTildeInPath
        let standardized = NSString(string: expanded).standardizingPath
        let normalized = standardized.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func extractSessionId(from object: [String: Any]) -> String? {
        if let id = firstString(in: object, keys: ["session_id", "sessionId"]) {
            return id
        }
        for nestedKey in ["notification", "data", "session", "context"] {
            if let nested = object[nestedKey] as? [String: Any] {
                let keys = nestedKey == "session" ? ["id", "session_id", "sessionId"] : ["session_id", "sessionId"]
                if let id = firstString(in: nested, keys: keys) {
                    return id
                }
            }
        }
        return nil
    }

    private static func extractCWD(from object: [String: Any]) -> String? {
        let cwdKeys = ["cwd", "working_directory", "workingDirectory", "project_dir", "projectDir"]
        if let cwd = firstString(in: object, keys: cwdKeys) {
            return cwd
        }
        for nestedKey in ["notification", "data", "context"] {
            if let nested = object[nestedKey] as? [String: Any],
               let cwd = firstString(in: nested, keys: cwdKeys) {
                return cwd
            }
        }
        return nil
    }
}
