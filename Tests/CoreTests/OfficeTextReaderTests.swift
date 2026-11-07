import Foundation
import XCTest
@testable import SightlineCore

/// The .docx and .odt samples are tiny archives, embedded so the tests need no fixture files.
/// The docx entry is deflated and the odt entry is stored, so both zip methods are covered.
final class OfficeTextReaderTests: XCTestCase {
    private let docxBase64 = "UEsDBBQAAAAIAJVRWF2ZTS2bkgAAALMAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbCWOSw7CMAxE95wi8r51YYEQStIFnxOUA1jB/Yg2iRqDyu1J6dLzZjyj62Ua1YfnNARvYF9WoNi78Bx8Z+DR3IsT1Hanm2/kpLLXJwO9SDwjJtfzRKkMkX0mbZgnknzOHUZyL+oYD1V1RBe8sJdC1h9g9ZVbeo+ibkuWt94cB3XZfGuVAYpxHBxJxrhStBr/I+wPUEsDBBQAAAAIAJVRWF3Q4rrI3gAAAIQBAAARAAAAd29yZC9kb2N1bWVudC54bWx9kLFuAyEMhvc+BWJvuHaoKnRHtqh70gcg4F6QwEaY5JK3L3dRkrZDlx/b8H827tfnFMUJCgfCQb6sOikAHfmA4yA/d5vndym4WvQ2EsIgL8BybZ76SXtyxwRYRSMg62mQh1qzVordAZLlFWXAdvdFJdna0jKqiYrPhRwwtwYpqteue1PJBpQLc0/+sgTZNCmzVPMBMVKv5nDWsmj++2weQ3O2rg2ZCzCUE0izBUfoxS/3zWH36togBoR/+B6imHTwbT3y7m7FHZyrGenqveUPQqv8JKl2qPsP1WN/5htQSwECFAMUAAAACACVUVhdmU0tm5IAAACzAAAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAJVRWF3Q4rrI3gAAAIQBAAARAAAAAAAAAAAAAACAAcMAAAB3b3JkL2RvY3VtZW50LnhtbFBLBQYAAAAAAgACAIAAAADQAQAAAAA="
    private let odtBase64 = "UEsDBBQAAAAAAJVRWF3ZsGVKdQEAAHUBAAALAAAAY29udGVudC54bWw8P3htbCB2ZXJzaW9uPSIxLjAiIGVuY29kaW5nPSJVVEYtOCI/Pgo8b2ZmaWNlOmRvY3VtZW50LWNvbnRlbnQgeG1sbnM6b2ZmaWNlPSJ1cm46b2FzaXM6bmFtZXM6dGM6b3BlbmRvY3VtZW50OnhtbG5zOm9mZmljZToxLjAiIHhtbG5zOnRleHQ9InVybjpvYXNpczpuYW1lczp0YzpvcGVuZG9jdW1lbnQ6eG1sbnM6dGV4dDoxLjAiPgo8b2ZmaWNlOmJvZHk+PG9mZmljZTp0ZXh0Pgo8dGV4dDpoPlRpdGxlPC90ZXh0Omg+Cjx0ZXh0OnA+U29tZSA8dGV4dDpzcGFuPnN0eWxlZDwvdGV4dDpzcGFuPiB0ZXh0PHRleHQ6cyB0ZXh0OmM9IjMiLz5lbmQ8L3RleHQ6cD4KPC9vZmZpY2U6dGV4dD48L29mZmljZTpib2R5Pjwvb2ZmaWNlOmRvY3VtZW50LWNvbnRlbnQ+UEsBAhQDFAAAAAAAlVFYXdmwZUp1AQAAdQEAAAsAAAAAAAAAAAAAAIABAAAAAGNvbnRlbnQueG1sUEsFBgAAAAABAAEAOQAAAJ4BAAAAAA=="

    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    func testWordDocumentKeepsParagraphsAndTabsAndSkipsDeletedText() throws {
        let url = try write(docxBase64, named: "sample.docx")

        let text = try OfficeTextReader.text(at: url, format: .wordprocessing)

        // Two paragraphs with text, the deleted-only paragraph, and the empty one.
        XCTAssertEqual(text, "Hello\nSecond \tline\n\n")
    }

    func testOpenDocumentReadsHeadingsSpansAndSpaces() throws {
        let url = try write(odtBase64, named: "sample.odt")

        let text = try OfficeTextReader.text(at: url, format: .opendocument)

        XCTAssertEqual(text, "Title\nSome styled text   end")
    }

    func testFileThatIsNotAZipIsRejected() throws {
        let url = folder.appendingPathComponent("plain.docx")
        try Data("not a zip archive".utf8).write(to: url)

        XCTAssertThrowsError(try OfficeTextReader.text(at: url, format: .wordprocessing))
    }

    private func write(_ base64: String, named name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
        return url
    }
}
