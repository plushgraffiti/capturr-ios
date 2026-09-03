/// This logging helper creates app loggers from a category alone.
/// Services throughout the main target use it so their messages share the
/// `com.capturr.app` subsystem in Console; extensions define their own subsystem.

import OSLog

extension Logger {
    // A logger for the given category, under CAPTURR's subsystem.
    init(category: String) {
        self.init(subsystem: "com.capturr.app", category: category)
    }
}
