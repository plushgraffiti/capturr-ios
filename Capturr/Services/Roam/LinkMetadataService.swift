/// This service fetches useful title, description, and image details for a shared web link.
/// `SyncWorker` calls it before sending a Roam Reader item, so the resulting block can carry
/// richer information than the original URL alone. It downloads the page and reads common
/// Open Graph metadata, returning clear errors when the link or response is unusable.

import Foundation
import OSLog

// Whatever the page provided; each optional field is nil when nothing was found.
struct LinkMetadata {
    let title: String?
    let description: String?
    let imageURL: String?
    let url: URL
}

enum LinkMetadataError: Error {
    case fetchFailed(Error)
}

actor LinkMetadataService {
    private let maxLength = 500
    private let timeout: TimeInterval = 10
    private let logger = Logger(category: "LinkMetadataService")

    // Downloads the page and extracts the best available title, description,
    // and image. Any request, status, or encoding problem becomes fetchFailed.
    func fetchMetadata(for url: URL) async throws -> LinkMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LinkMetadataError.fetchFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LinkMetadataError.fetchFailed(NSError(domain: "HTTP", code: (response as? HTTPURLResponse)?.statusCode ?? -1))
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LinkMetadataError.fetchFailed(NSError(domain: "Encoding", code: -1))
        }

        // Preference order: Open Graph, then Twitter cards, then plain HTML fallbacks.
        let title = parseMetaTag(from: html, property: "og:title")
            ?? parseMetaTag(from: html, name: "twitter:title")
            ?? parseTitle(from: html)

        let description = parseMetaTag(from: html, property: "og:description")
            ?? parseMetaTag(from: html, name: "twitter:description")
            ?? parseMetaTag(from: html, name: "description")

        let imageURL = parseMetaTag(from: html, property: "og:image")
            ?? parseMetaTag(from: html, name: "twitter:image")

        logger.debug("Parsed metadata - title: \(title ?? "nil"), description: \(description?.prefix(50) ?? "nil")..., imageURL: \(imageURL ?? "nil")")

        return LinkMetadata(
            title: truncate(title),
            description: truncate(description),
            imageURL: imageURL,
            url: url
        )
    }

    // Parses a meta tag with property attribute (Open Graph style).
    private func parseMetaTag(from html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']\(property)[\"']"
        ]
        return firstMatch(patterns: patterns, in: html)
    }

    // Parses a meta tag with name attribute (standard HTML style).
    private func parseMetaTag(from html: String, name: String) -> String? {
        let patterns = [
            "<meta[^>]+name=[\"']\(name)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+name=[\"']\(name)[\"']"
        ]
        return firstMatch(patterns: patterns, in: html)
    }

    // Parses the <title> tag as fallback.
    private func parseTitle(from html: String) -> String? {
        let pattern = "<title[^>]*>([^<]+)</title>"
        return firstMatch(patterns: [pattern], in: html)
    }

    // Returns the first regex match from a list of patterns.
    private func firstMatch(patterns: [String], in html: String) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let value = String(html[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // Truncates text to maxLength characters, adding ellipsis if truncated.
    private func truncate(_ text: String?) -> String? {
        guard let text = text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }
}
