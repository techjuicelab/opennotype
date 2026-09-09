import XCTest
@testable import OpenNoTypeCore

final class WritingProfileTests: XCTestCase {
    func testKnownAppsChooseTheirFormatWithoutChangingSpokenTone() {
        let cases: [(String, WritingProfileKind)] = [
            ("com.openai.codex", .development),
            ("com.google.antigravity", .development),
            ("com.microsoft.VSCode", .development),
            ("com.kakao.KakaoTalkMac", .conversation),
            ("ru.keepcoder.Telegram", .conversation),
            ("com.hnc.Discord", .conversation),
            ("com.apple.Notes", .notes),
            ("notion.id", .notes),
            ("md.obsidian", .notes),
            ("com.apple.mail", .email)
        ]
        for (bundleID, kind) in cases {
            XCTAssertEqual(WritingProfile.defaultForApp(bundleID: bundleID), .init(kind: kind), bundleID)
        }
        for bundleID in WritingProfile.knownAppBundleIDs {
            XCTAssertEqual(WritingProfile.defaultForApp(bundleID: bundleID).tone, .preserve, bundleID)
        }
    }

    func testGeneralPurposeAIAndBrowsersDoNotImplyDevelopmentOrRecipientTone() {
        for bundleID in ["com.anthropic.claudefordesktop", "com.google.Chrome", "com.apple.Safari",
                         "com.microsoft.edgemac", "com.example.mail-client", "com.apple.Terminal"] {
            XCTAssertEqual(WritingProfile.defaultForApp(bundleID: bundleID), .init(), bundleID)
        }
    }

    func testMissingAndSimilarBundleIDsUseGeneralDefault() {
        for bundleID in [nil, "", "com.openai.codex.preview", "com.google.antigravity.other", "notion.id.fake"] {
            XCTAssertEqual(WritingProfile.defaultForApp(bundleID: bundleID), .init(), bundleID ?? "nil")
        }
    }

    func testExplicitProfileRoundTripsAcrossEveryFormatAndTone() throws {
        for kind in WritingProfileKind.allCases {
            for tone in WritingTone.allCases {
                let profile = WritingProfile(kind: kind, tone: tone)
                let restored = try JSONDecoder().decode(WritingProfile.self, from: JSONEncoder().encode(profile))
                XCTAssertEqual(restored, profile)
            }
        }
    }
}
