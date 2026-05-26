import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class ClaudeHookHelpersTests: XCTestCase {

    // MARK: - classifyNotification

    func testClassifyPermissionPrompt() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "Notification permission_prompt",
            message: "Claude needs your permission to use Bash"
        )
        XCTAssertEqual(result.subtitle, "Permission")
        XCTAssertEqual(result.body, "Claude needs your permission to use Bash")
    }

    func testClassifyApprovalNeeded() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "approval",
            message: ""
        )
        XCTAssertEqual(result.subtitle, "Permission")
        XCTAssertEqual(result.body, "Approval needed")
    }

    func testClassifyError() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "error",
            message: "Build failed with exit code 1"
        )
        XCTAssertEqual(result.subtitle, "Error")
        XCTAssertEqual(result.body, "Build failed with exit code 1")
    }

    func testClassifyErrorEmptyMessage() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "failed",
            message: ""
        )
        XCTAssertEqual(result.subtitle, "Error")
        XCTAssertEqual(result.body, "Claude reported an error")
    }

    func testClassifyWaiting() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "idle",
            message: "Waiting for user input"
        )
        XCTAssertEqual(result.subtitle, "Waiting")
        XCTAssertEqual(result.body, "Waiting for user input")
    }

    func testClassifyWaitingEmptyMessage() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "waiting",
            message: ""
        )
        XCTAssertEqual(result.subtitle, "Waiting")
        XCTAssertEqual(result.body, "Claude is waiting for your input")
    }

    func testClassifyAttentionFallback() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "something_else",
            message: "Check this out"
        )
        XCTAssertEqual(result.subtitle, "Attention")
        XCTAssertEqual(result.body, "Check this out")
    }

    func testClassifyAttentionEmptyMessage() {
        let result = ClaudeHookHelpers.classifyNotification(
            signal: "unknown",
            message: ""
        )
        XCTAssertEqual(result.subtitle, "Attention")
        XCTAssertEqual(result.body, "Claude needs your input")
    }

    // MARK: - parseInput

    func testParseInputValidJSON() {
        let json = """
        {"session_id":"abc-123","cwd":"/Users/test/project","notification_type":"permission_prompt","transcript_path":"/tmp/t.jsonl"}
        """
        let parsed = ClaudeHookHelpers.parseInput(json)
        XCTAssertEqual(parsed.sessionId, "abc-123")
        XCTAssertEqual(parsed.cwd, "/Users/test/project")
        XCTAssertEqual(parsed.notificationType, "permission_prompt")
        XCTAssertEqual(parsed.transcriptPath, "/tmp/t.jsonl")
        XCTAssertNotNil(parsed.object)
    }

    func testParseInputEmptyString() {
        let parsed = ClaudeHookHelpers.parseInput("")
        XCTAssertNil(parsed.sessionId)
        XCTAssertNil(parsed.cwd)
        XCTAssertNil(parsed.notificationType)
        XCTAssertNil(parsed.object)
    }

    func testParseInputInvalidJSON() {
        let parsed = ClaudeHookHelpers.parseInput("not json at all")
        XCTAssertNil(parsed.sessionId)
        XCTAssertNil(parsed.object)
        XCTAssertEqual(parsed.rawInput, "not json at all")
    }

    func testParseInputNestedSessionId() {
        let json = """
        {"notification":{"session_id":"nested-id"},"cwd":"/tmp"}
        """
        let parsed = ClaudeHookHelpers.parseInput(json)
        XCTAssertEqual(parsed.sessionId, "nested-id")
    }

    func testParseInputCamelCaseKeys() {
        let json = """
        {"sessionId":"camel-123","workingDirectory":"/tmp/wd","notificationType":"stop"}
        """
        let parsed = ClaudeHookHelpers.parseInput(json)
        XCTAssertEqual(parsed.sessionId, "camel-123")
        XCTAssertEqual(parsed.notificationType, "stop")
    }

    func testParseInputWhitespace() {
        let json = "   \n  "
        let parsed = ClaudeHookHelpers.parseInput(json)
        XCTAssertNil(parsed.object)
    }

    // MARK: - summarizeNotification

    func testSummarizePermissionPromptJSON() {
        let json = """
        {"session_id":"958997fa","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        XCTAssertEqual(summary.subtitle, "Permission")
        XCTAssertTrue(summary.body.contains("Claude needs your permission to use Bash"))
    }

    func testSummarizeEmptyInput() {
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: "")
        XCTAssertEqual(summary.subtitle, "Waiting")
        XCTAssertEqual(summary.body, "Claude is waiting for your input")
    }

    func testSummarizePlainTextFallback() {
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: "Something happened")
        XCTAssertEqual(summary.subtitle, "Attention")
        XCTAssertEqual(summary.body, "Something happened")
    }

    func testSummarizeErrorNotification() {
        let json = """
        {"hook_event_name":"Notification","message":"Build failed","notification_type":"error"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        XCTAssertEqual(summary.subtitle, "Error")
        XCTAssertTrue(summary.body.contains("Build failed"))
    }

    func testSummarizeAppendsSessionId() {
        let json = """
        {"session_id":"abcdef12-3456-7890","message":"Hello world"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        XCTAssertTrue(summary.body.contains("[abcdef12]"))
    }

    func testSummarizeSessionIdNotDuplicated() {
        let json = """
        {"session_id":"abcdef12-3456","message":"Already contains abcdef12 in text"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        let occurrences = summary.body.components(separatedBy: "abcdef12").count - 1
        XCTAssertEqual(occurrences, 1, "Session ID should not be appended when already present")
    }

    // MARK: - Helper Functions

    func testFirstStringFindsFirstMatch() {
        let obj: [String: Any] = ["a": "", "b": "found", "c": "also"]
        XCTAssertEqual(ClaudeHookHelpers.firstString(in: obj, keys: ["a", "b", "c"]), "found")
    }

    func testFirstStringSkipsEmptyAndWhitespace() {
        let obj: [String: Any] = ["a": "  ", "b": "\n", "c": "real"]
        XCTAssertEqual(ClaudeHookHelpers.firstString(in: obj, keys: ["a", "b", "c"]), "real")
    }

    func testFirstStringReturnsNilWhenNoMatch() {
        let obj: [String: Any] = ["a": 42, "b": ""]
        XCTAssertNil(ClaudeHookHelpers.firstString(in: obj, keys: ["a", "b", "missing"]))
    }

    func testNormalizedSingleLine() {
        XCTAssertEqual(
            ClaudeHookHelpers.normalizedSingleLine("  hello\n  world  \t "),
            "hello world"
        )
    }

    func testTruncateShortString() {
        XCTAssertEqual(ClaudeHookHelpers.truncate("short", maxLength: 10), "short")
    }

    func testTruncateLongString() {
        let long = String(repeating: "a", count: 200)
        let result = ClaudeHookHelpers.truncate(long, maxLength: 10)
        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testSanitizeNotificationFieldReplacesPipe() {
        let result = ClaudeHookHelpers.sanitizeNotificationField("title|subtitle|body")
        XCTAssertFalse(result.contains("|"))
        XCTAssertTrue(result.contains("¦"))
    }

    func testSanitizeNotificationFieldNormalizesWhitespace() {
        let result = ClaudeHookHelpers.sanitizeNotificationField("  hello\n  world  ")
        XCTAssertEqual(result, "hello world")
    }

    func testDedupeBranchContextLinesSingleLine() {
        XCTAssertEqual(
            ClaudeHookHelpers.dedupeBranchContextLines("just one line"),
            "just one line"
        )
    }

    func testDedupeBranchContextLinesDeduplicates() {
        let input = "main • /Users/test/project\nfeature • /Users/test/project\nother line"
        let result = ClaudeHookHelpers.dedupeBranchContextLines(input)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2, "Duplicate path lines should be deduped to keep only the last")
        XCTAssertTrue(lines[0].hasPrefix("feature"))
        XCTAssertEqual(lines[1], "other line")
    }

    func testDedupeBranchContextLinesNoPathLines() {
        let input = "line one\nline two\nline three"
        XCTAssertEqual(
            ClaudeHookHelpers.dedupeBranchContextLines(input),
            input,
            "Lines without branch•path format should pass through unchanged"
        )
    }

    // MARK: - Redaction

    func testRedactEmail() {
        let result = ClaudeHookHelpers.redactClaudeSensitiveSpans("Contact user@example.com for details")
        XCTAssertTrue(result.contains("<email>"))
        XCTAssertFalse(result.contains("user@example.com"))
    }

    func testRedactPath() {
        let result = ClaudeHookHelpers.redactClaudeSensitiveSpans("Error in /Users/secret/project")
        XCTAssertTrue(result.contains("<path>"))
        XCTAssertFalse(result.contains("/Users/secret/project"))
    }

    func testRedactToken() {
        let result = ClaudeHookHelpers.redactClaudeSensitiveSpans("Key: sk-abc1234567890abcdefg")
        XCTAssertTrue(result.contains("<token>"))
        XCTAssertFalse(result.contains("sk-abc1234567890abcdefg"))
    }

    // MARK: - summarizeNotification redaction

    func testSummarizePlainTextFallbackRedactsPaths() {
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: "/Users/secret/project crashed")
        XCTAssertFalse(summary.body.contains("/Users/secret/project"))
        XCTAssertTrue(summary.body.contains("<path>"))
    }

    func testSummarizePlainTextFallbackRedactsEmails() {
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: "admin@evil.com sent a message")
        XCTAssertFalse(summary.body.contains("admin@evil.com"))
        XCTAssertTrue(summary.body.contains("<email>"))
    }

    // MARK: - firstStringOrStringified

    func testFirstStringOrStringifiedString() {
        let obj: [String: Any] = ["error": "something broke"]
        XCTAssertEqual(ClaudeHookHelpers.firstStringOrStringified(in: obj, keys: ["error"]), "something broke")
    }

    func testFirstStringOrStringifiedObject() {
        let obj: [String: Any] = ["error": ["code": 42, "msg": "fail"]]
        let result = ClaudeHookHelpers.firstStringOrStringified(in: obj, keys: ["error"])
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"code\""))
        XCTAssertTrue(result!.contains("\"msg\""))
    }

    func testFirstStringOrStringifiedSkipsEmpty() {
        let obj: [String: Any] = ["error": "  ", "detail": "real"]
        XCTAssertEqual(ClaudeHookHelpers.firstStringOrStringified(in: obj, keys: ["error", "detail"]), "real")
    }

    // MARK: - Non-string error payloads

    func testSummarizeNonStringErrorPayload() {
        let json = """
        {"hook_event_name":"Notification","error":{"code":-1,"message":"timeout"},"notification_type":"error"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        XCTAssertEqual(summary.subtitle, "Error")
        XCTAssertTrue(summary.body.contains("timeout") || summary.body.contains("code"),
                       "Non-string error payload should be stringified and included")
    }

    // MARK: - Completed classification with "complete" prefix

    func testClassifyCompletedComplete() {
        let result = ClaudeHookHelpers.classifyNotification(signal: "complete", message: "Task finished successfully")
        XCTAssertEqual(result.subtitle, "Completed")
        XCTAssertEqual(result.body, "Task finished successfully")
    }

    // MARK: - Completed negation (substring false positives)

    func testClassifyIncompleteNotCompleted() {
        let result = ClaudeHookHelpers.classifyNotification(signal: "incomplete", message: "Build incomplete")
        XCTAssertNotEqual(result.subtitle, "Completed")
        XCTAssertEqual(result.subtitle, "Attention")
    }

    func testClassifyUnsuccessfulNotCompleted() {
        let result = ClaudeHookHelpers.classifyNotification(signal: "unsuccessful", message: "Attempt was unsuccessful")
        XCTAssertNotEqual(result.subtitle, "Completed")
        XCTAssertEqual(result.subtitle, "Attention")
    }

    func testClassifyUnfinishedNotCompleted() {
        let result = ClaudeHookHelpers.classifyNotification(signal: "unfinished", message: "Work unfinished")
        XCTAssertNotEqual(result.subtitle, "Completed")
        XCTAssertEqual(result.subtitle, "Attention")
    }

    func testClassifyFinishingUpNotCompleted() {
        let result = ClaudeHookHelpers.classifyNotification(signal: "status", message: "Finishing up, please wait")
        XCTAssertNotEqual(result.subtitle, "Completed")
        XCTAssertEqual(result.subtitle, "Waiting")
    }

    // MARK: - Message priority over stringified error objects

    func testSummarizePrefersPlainMessageOverErrorObject() {
        let json = """
        {"message":"Build timeout","error":{"code":-1,"msg":"timeout"},"notification_type":"error"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        XCTAssertTrue(summary.body.hasPrefix("Build timeout"),
                       "Plain message should take priority over stringified error object")
    }

    // MARK: - Prompt not classified as Waiting

    func testClassifyPromptNotWaiting() {
        let result = ClaudeHookHelpers.classifyNotification(signal: "attention-prompt", message: "Needs response")
        XCTAssertEqual(result.subtitle, "Attention")
        XCTAssertNotEqual(result.subtitle, "Waiting")
    }

    // MARK: - sanitizeNotificationField does not truncate

    func testSanitizeNotificationFieldNoTruncation() {
        let long = String(repeating: "abc ", count: 100)
        let result = ClaudeHookHelpers.sanitizeNotificationField(long)
        XCTAssertTrue(result.count > 180, "sanitizeNotificationField should not truncate — that is summarize's job")
    }

    // MARK: - Nested session ID appended to body

    func testSummarizeNestedSessionIdAppended() {
        let json = """
        {"notification":{"session_id":"nested-sess"},"message":"Hello"}
        """
        let summary = ClaudeHookHelpers.summarizeNotification(rawInput: json)
        XCTAssertTrue(summary.body.contains("[nested-s]"), "Nested session ID should be extracted and appended")
    }
}
