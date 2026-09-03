/// This test suite checks the Roam date links attached to queued captures.
/// Swift Testing runs the `@Test`, which builds local dates and passes them to
/// `RoamAPI.roamDateLink(from:)`. The cases protect the ordinal suffixes that
/// `SyncWorker` uses when it chooses a capture's destination daily note.

import Foundation
import Testing
@testable import Capturr

struct RoamDateFormattingTests {
    @Test
    func formatsOrdinalSuffixes() throws {
        let cases = [
            (1, "[[January 1st, 2026]]"),
            (2, "[[January 2nd, 2026]]"),
            (3, "[[January 3rd, 2026]]"),
            (4, "[[January 4th, 2026]]"),
            (11, "[[January 11th, 2026]]"),
            (12, "[[January 12th, 2026]]"),
            (13, "[[January 13th, 2026]]"),
            (21, "[[January 21st, 2026]]"),
            (22, "[[January 22nd, 2026]]"),
            (23, "[[January 23rd, 2026]]"),
            (31, "[[January 31st, 2026]]"),
        ]

        // roamDateLink formats in the local time zone (Calendar.current), so build
        // the input dates the same way — a GMT-pinned date would land on the wrong
        // calendar day on machines at extreme UTC offsets.
        let calendar = Calendar.current

        for (day, expected) in cases {
            let date = try #require(
                calendar.date(
                    from: DateComponents(
                        year: 2026,
                        month: 1,
                        day: day,
                        hour: 12
                    )
                )
            )
            #expect(RoamAPI.roamDateLink(from: date) == expected)
        }
    }
}
