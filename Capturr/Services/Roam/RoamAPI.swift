/// This client sends new text and nested blocks through Roam's Append API.
/// `SyncWorker` creates it while draining queued captures. The client converts
/// app block models and destination choices into Roam's request format, waits
/// for the HTTP response, and reports server failures to the worker.

import Foundation

struct RoamAPIError: LocalizedError {
    let message: String
    let statusCode: Int?
    var errorDescription: String? { message }
}

public enum RoamLocation {
    case dailyNote(Date)
    case page(String)
}

class RoamAPI {
    private let graphName: String
    private let apiToken: String
    private let session = URLSession.shared

    init(graphName: String, apiToken: String) {
        self.graphName = graphName
        self.apiToken = apiToken
    }

    // MARK: - Date Formatting for Roam

    // Formats a date as a Roam date link: [[January 29th, 2026]]
    static func roamDateLink(from date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)

        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)

        return "[[\(month) \(day)\(ordinalSuffix(for: day)), \(year)]]"
    }

    private static func ordinalSuffix(for day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // MARK: - Public API

    // Sends a single text block.
    func sendNoteBlock(_ content: String, _ location: RoamLocation, nestUnder: String? = nil) async throws {
        let appendData: [[String: Any]] = [["string": content]]
        try await sendAppendData(appendData, location: location, nestUnder: nestUnder)
    }

    // Sends a single TODO block (wraps content with Roam TODO syntax).
    func sendTodoBlock(_ content: String, _ location: RoamLocation, nestUnder: String? = nil) async throws {
        try await sendNoteBlock("{{[[TODO]]}} \(content)", location, nestUnder: nestUnder)
    }

    // Sends an array of RoamBlocks as top-level append-data entries.
    // Used by Write capture (nested blocks) and Scan capture (wrapped in parent by caller).
    func sendBlocks(_ blocks: [RoamBlock], _ location: RoamLocation, nestUnder: String? = nil) async throws {
        let appendData = blocks.map { blockToDict($0) }
        try await sendAppendData(appendData, location: location, nestUnder: nestUnder)
    }

    // Sends blocks to a specific page (used for Roam Reader).
    func sendToPage(_ blocks: [RoamBlock], pageName: String) async throws {
        let appendData = blocks.map { blockToDict($0) }
        try await sendAppendData(appendData, location: .page(pageName), nestUnder: nil)
    }

    // MARK: - Private Helpers

    // Converts a RoamBlock tree into the dictionary format expected by the Roam API.
    private func blockToDict(_ block: RoamBlock) -> [String: Any] {
        var dict: [String: Any] = ["string": block.string]
        if !block.children.isEmpty {
            dict["children"] = block.children.map { blockToDict($0) }
        }
        return dict
    }

    // Builds the location payload for a Roam API request.
    private func locationPayload(for location: RoamLocation, nestUnder: String?) -> [String: Any] {
        var payload: [String: Any]
        switch location {
        case .dailyNote(let captureDate):
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "MM-dd-yyyy"
            let dateKey = dateFormatter.string(from: captureDate)
            payload = ["page": ["title": ["daily-note-page": dateKey]]]
        case .page(let title):
            payload = ["page": ["title": title]]
        }

        if let nest = nestUnder?.trimmingCharacters(in: .whitespacesAndNewlines), !nest.isEmpty {
            payload["nest-under"] = ["string": nest]
        }

        return payload
    }

    // Shared method that constructs and sends the append-blocks API request.
    private func sendAppendData(_ appendData: [[String: Any]], location: RoamLocation, nestUnder: String?) async throws {
        guard let url = URL(string: "https://append-api.roamresearch.com/api/graph/\(graphName)/append-blocks") else {
            throw NSError(domain: "InvalidURL", code: -1)
        }

        let payload: [String: Any] = [
            "location": locationPayload(for: location, nestUnder: nestUnder),
            "append-data": appendData
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NoHTTPResponse", code: -2)
        }

        guard httpResponse.statusCode == 200 else {
            var serverMessage: String?
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["message"] as? String, !msg.isEmpty {
                serverMessage = msg
            } else if let bodyString = String(data: data, encoding: .utf8), !bodyString.isEmpty {
                serverMessage = bodyString
            }
            let message = serverMessage.map { "HTTP \(httpResponse.statusCode) - \($0)" }
                ?? "HTTP \(httpResponse.statusCode)"
            throw RoamAPIError(message: message, statusCode: httpResponse.statusCode)
        }
    }
}
