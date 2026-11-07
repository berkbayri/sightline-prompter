import XCTest
@testable import SightlineCore

final class FreeTierTests: XCTestCase {
    func testFreeLanguages() {
        XCTAssertTrue(FreeTier.allowsLanguage("en-US"))
        XCTAssertTrue(FreeTier.allowsLanguage("en-GB"))
        XCTAssertTrue(FreeTier.allowsLanguage("tr-TR"))
        XCTAssertTrue(FreeTier.allowsLanguage("es-MX"))
        XCTAssertFalse(FreeTier.allowsLanguage("de-DE"))
        XCTAssertFalse(FreeTier.allowsLanguage("ja-JP"))
        XCTAssertFalse(FreeTier.allowsLanguage("zh-CN"))
    }

    func testLimitsMatchThePublishedPlan() {
        XCTAssertEqual(FreeTier.maxRecordSeconds, 120)
        XCTAssertEqual(FreeTier.maxTrackingSeconds, 120)
        XCTAssertEqual(FreeTier.maxVideoHeight, 1080)
        XCTAssertEqual(FreeTier.maxFrameRate, 30)
    }

    @MainActor
    func testProductIDsAreStable() {
        // These IDs are registered in App Store Connect; changing one orphans the product.
        XCTAssertEqual(ProStore.yearlyID, "com.berkbayri.SightlinePrompter.pro.yearly")
        XCTAssertEqual(ProStore.monthlyID, "com.berkbayri.SightlinePrompter.pro.monthly")
        XCTAssertEqual(ProStore.lifetimeID, "com.berkbayri.SightlinePrompter.pro.lifetime")
    }
}
