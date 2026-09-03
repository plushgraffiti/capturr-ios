/// This test suite protects the app's external capture-link contract.
/// Swift Testing runs each `@Test`, which passes URLs to `CaptureRoute.from(url:)`
/// and checks route metadata shared by capture menus and widgets. `ContentView` uses
/// the same parser when the app receives a capture deep link.

import Foundation
import Testing
@testable import Capturr

struct CaptureRouteTests {
    @Test
    func parsesEverySupportedDeepLink() throws {
        let cases: [(String, CaptureRoute)] = [
            ("capturr://capture/note", .note),
            ("capturr://capture/todo", .todo),
            ("capturr://capture/voice", .voice),
            ("capturr://capture/scan", .scan),
        ]

        for (rawURL, expectedRoute) in cases {
            let url = try #require(URL(string: rawURL))
            #expect(CaptureRoute.from(url: url) == expectedRoute)
        }
    }

    @Test
    func parsingIsCaseInsensitive() throws {
        let url = try #require(URL(string: "CAPTURR://CAPTURE/VOICE"))

        #expect(CaptureRoute.from(url: url) == .voice)
    }

    @Test
    func rejectsInvalidDeepLinks() throws {
        let invalidURLs = [
            "https://capture/note",
            "capturr://other/note",
            "capturr://capture/unknown",
            "capturr://capture",
        ]

        for rawURL in invalidURLs {
            let url = try #require(URL(string: rawURL))
            #expect(CaptureRoute.from(url: url) == nil)
        }
    }

    @Test
    func routeMetadataIsComplete() {
        for route in CaptureRoute.allCases {
            #expect(!route.menuTitle.isEmpty)
            #expect(!route.widgetTitle.isEmpty)
            #expect(!route.systemImageName.isEmpty)
            #expect(route.id == route.rawValue)
        }
    }
}
