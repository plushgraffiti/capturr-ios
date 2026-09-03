/// This client handles Roam Backend API operations that need queries or block updates.
/// `TodoSyncManager` uses it to pull TODO blocks, and `SyncWorker` uses it to apply queued
/// TODO state changes. It builds authenticated requests, decodes query results, and turns
/// expected HTTP failures into errors the sync layer can classify for retry behavior.

import Foundation
import OSLog

private let logger = Logger(category: "RoamBackendAPI")

enum RoamBackendAPIError: LocalizedError {
    case unauthorized           // 401
    case badRequest(String)     // 400
    case rateLimitExceeded      // 429
    case serverError(String)    // 500
    case serviceUnavailable     // 503
    case invalidResponse
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized. Check your Backend API token."
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let message):
            return "Server error: \(message)"
        case .serviceUnavailable:
            return "Service unavailable. Please try again later."
        case .invalidResponse:
            return "Invalid response from server."
        case .invalidRequest:
            return "Invalid request parameters."
        }
    }
}

class RoamBackendAPI {
    private let apiToken: String
    private let session: URLSession

    init(apiToken: String) {
        self.apiToken = apiToken

        // Configure URLSession to handle redirects
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: configuration)
    }

    // Execute a Datalog query against the Roam graph
    // - Parameters:
    //   - graphName: Name of the Roam graph
    //   - query: Datalog query string
    //   - args: Optional query arguments (default: empty array)
    // - Returns: Array of query results, where each result is an array of values
    func executeQuery(graphName: String, query: String, args: [String] = []) async throws -> [[Any]] {
        guard let encodedGraphName = graphName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.roamresearch.com/api/graph/\(encodedGraphName)/q") else {
            throw RoamBackendAPIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "X-Authorization")

        let body: [String: Any] = [
            "query": query,
            "args": args
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Executing query on graph: \(graphName)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoamBackendAPIError.invalidResponse
        }

        logger.info("Query response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            // Parse successful response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [[Any]] else {
                throw RoamBackendAPIError.invalidResponse
            }
            logger.info("Query returned \(result.count) results")

            return result

        case 400:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Bad request: \(errorMessage)")
            throw RoamBackendAPIError.badRequest(errorMessage)

        case 401, 403:
            logger.error("Unauthorized request")
            throw RoamBackendAPIError.unauthorized

        case 429:
            logger.warning("Rate limit exceeded")
            throw RoamBackendAPIError.rateLimitExceeded

        case 500...599:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            logger.error("Server error: \(errorMessage)")
            if httpResponse.statusCode == 503 {
                throw RoamBackendAPIError.serviceUnavailable
            }
            throw RoamBackendAPIError.serverError(errorMessage)

        default:
            logger.error("Unexpected status code: \(httpResponse.statusCode)")
            throw RoamBackendAPIError.invalidResponse
        }
    }

    // Update a block's string content in Roam
    // - Parameters:
    //   - graphName: Name of the Roam graph
    //   - blockUid: UID of the block to update
    //   - newString: New string content for the block
    func updateBlock(graphName: String, blockUid: String, newString: String) async throws {
        guard let encodedGraphName = graphName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.roamresearch.com/api/graph/\(encodedGraphName)/write") else {
            throw RoamBackendAPIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "X-Authorization")

        let body: [String: Any] = [
            "action": "update-block",
            "block": [
                "uid": blockUid,
                "string": newString
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Updating block \(blockUid) in graph: \(graphName)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoamBackendAPIError.invalidResponse
        }

        logger.info("Update block response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            logger.info("Block updated successfully")
            return

        case 400:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Bad request: \(errorMessage)")
            throw RoamBackendAPIError.badRequest(errorMessage)

        case 401, 403:
            logger.error("Unauthorized request")
            throw RoamBackendAPIError.unauthorized

        case 429:
            logger.warning("Rate limit exceeded")
            throw RoamBackendAPIError.rateLimitExceeded

        case 500...599:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            logger.error("Server error: \(errorMessage)")
            if httpResponse.statusCode == 503 {
                throw RoamBackendAPIError.serviceUnavailable
            }
            throw RoamBackendAPIError.serverError(errorMessage)

        default:
            logger.error("Unexpected status code: \(httpResponse.statusCode)")
            throw RoamBackendAPIError.invalidResponse
        }
    }

}
