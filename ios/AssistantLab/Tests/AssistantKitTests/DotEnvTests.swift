import XCTest
@testable import AssistantDevRelay

/// The .env reader is the only new thing a key passes through, so it gets the
/// same treatment as the rest: quoting, `export`, comments and blanks.
final class DotEnvTests: XCTestCase {
    private func write(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotenv-\(UUID().uuidString).env")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testParsesTheShapesPeopleActuallyPaste() throws {
        let url = try write("""
        # a comment
        export OPENAI_API_KEY="sk-test-quoted"
        HELIPAD_ASSISTANT_MODEL=gpt-5.6-luna
          SPACED   =   value with spaces

        EMPTY=
        no_equals_sign
        """)
        let values = DotEnv.load(from: url)

        XCTAssertEqual(values["OPENAI_API_KEY"], "sk-test-quoted")
        XCTAssertEqual(values["HELIPAD_ASSISTANT_MODEL"], "gpt-5.6-luna")
        XCTAssertEqual(values["SPACED"], "value with spaces")
        XCTAssertNil(values["EMPTY"])
        XCTAssertNil(values["no_equals_sign"])
        XCTAssertNil(values["# a comment"])
    }

    func testStripsOnlyAMatchingQuotePair() throws {
        let url = try write("""
        A='single'
        B="double"
        C="mismatched'
        D=bare
        """)
        let values = DotEnv.load(from: url)

        XCTAssertEqual(values["A"], "single")
        XCTAssertEqual(values["B"], "double")
        XCTAssertEqual(values["C"], "\"mismatched'")
        XCTAssertEqual(values["D"], "bare")
    }

    func testAMissingFileIsNotAnError() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString).env")
        XCTAssertTrue(DotEnv.load(from: missing).isEmpty)
    }

    func testTheProcessEnvironmentWinsOverTheFile() throws {
        // PATH is always set, so it is a safe key to prove precedence with
        // without mutating the environment.
        let url = try write("PATH=/definitely/not/the/real/path")
        let merged = DotEnv.environment(from: url)

        XCTAssertEqual(merged["PATH"], ProcessInfo.processInfo.environment["PATH"])
        XCTAssertNotEqual(merged["PATH"], "/definitely/not/the/real/path")
    }
}
