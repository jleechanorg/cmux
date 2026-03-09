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
}
