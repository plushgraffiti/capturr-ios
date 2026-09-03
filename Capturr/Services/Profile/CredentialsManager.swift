/// This actor is the app's safe, shared gateway to Roam API credentials.
/// Settings and onboarding save tokens through it, while sync and TODO features read them.
/// It keeps an in-memory cache over `KeychainService` and clears blocked outbox work
/// when changed credentials make a retry possible.

import Foundation
import SwiftData
import OSLog

actor CredentialsManager {
    static let shared = CredentialsManager()

    private let logger = Logger(category: "Credentials")

    // MARK: - In-Memory Cache

    private var cachedPrimaryAppendToken: String?
    private var cachedPrimaryBackendToken: String?
    private var cachedGraphTokens: [String: String] = [:]

    private init() {}

    // MARK: - Load Credentials

    // Load all credentials from Keychain into memory cache.
    // Call on app launch and when returning to foreground.
    func loadCredentials() {
        cachedPrimaryAppendToken = KeychainService.shared.load(for: .primaryAppendToken)
        cachedPrimaryBackendToken = KeychainService.shared.load(for: .primaryBackendToken)
        logger.info("Loaded credentials from Keychain")
    }

    // MARK: - Get Tokens

    // Primary graph Append API token (for creating blocks).
    var primaryAppendToken: String? {
        if let cached = cachedPrimaryAppendToken {
            return cached
        }
        // Fallback to Keychain read if cache is empty
        let token = KeychainService.shared.load(for: .primaryAppendToken)
        cachedPrimaryAppendToken = token
        return token
    }

    // Primary graph Backend API token (for TODOs).
    var primaryBackendToken: String? {
        if let cached = cachedPrimaryBackendToken {
            return cached
        }
        // Fallback to Keychain read if cache is empty
        let token = KeychainService.shared.load(for: .primaryBackendToken)
        cachedPrimaryBackendToken = token
        return token
    }

    // Returns the cached Append token for an additional graph, falling back to Keychain.
    func appendToken(forGraphId id: String) -> String? {
        if let cached = cachedGraphTokens[id] {
            return cached
        }
        let token = KeychainService.shared.load(for: .graphAppendToken(graphId: id))
        if let token {
            cachedGraphTokens[id] = token
        }
        return token
    }

    // MARK: - Check Token Existence (nonisolated)

    // Check if primary Append token is configured.
    // Nonisolated: goes directly to Keychain (thread-safe at OS level).
    nonisolated var hasPrimaryAppendToken: Bool {
        KeychainService.shared.exists(for: .primaryAppendToken)
    }

    // Check if primary Backend token is configured.
    // Nonisolated: goes directly to Keychain (thread-safe at OS level).
    nonisolated var hasPrimaryBackendToken: Bool {
        KeychainService.shared.exists(for: .primaryBackendToken)
    }

    // Check if a graph-specific Append token is configured.
    nonisolated func hasAppendToken(forGraphId id: String) -> Bool {
        KeychainService.shared.exists(for: .graphAppendToken(graphId: id))
    }

    // MARK: - Save Tokens

    // Save primary Append API token.
    // Also clears hardError on pending OutboxItems so they retry with new credentials.
    func savePrimaryAppendToken(_ token: String, context: ModelContext) throws {
        try KeychainService.shared.save(token, for: .primaryAppendToken)
        cachedPrimaryAppendToken = token

        // Clear hardError on items so they retry with new credentials
        let clearedCount = clearHardErrors(in: context)
        logger.info("Saved primary Append token, cleared \(clearedCount) hardError items")
    }

    // Save primary Backend API token.
    // Also clears hardError on pending OutboxItems so they retry with new credentials.
    func savePrimaryBackendToken(_ token: String, context: ModelContext) throws {
        try KeychainService.shared.save(token, for: .primaryBackendToken)
        cachedPrimaryBackendToken = token

        // Clear hardError on items so they retry with new credentials
        let clearedCount = clearHardErrors(in: context)
        logger.info("Saved primary Backend token, cleared \(clearedCount) hardError items")
    }

    // Save Append token for a specific graph.
    // Also clears hardError on pending OutboxItems for this graph so they retry with new credentials.
    func saveGraphAppendToken(_ token: String, graphId: String, context: ModelContext? = nil) throws {
        try KeychainService.shared.save(token, for: .graphAppendToken(graphId: graphId))
        cachedGraphTokens[graphId] = token

        // Clear hardError on items targeting this graph so they retry with new credentials
        if let context {
            let clearedCount = clearHardErrors(in: context, forGraphId: graphId)
            logger.info("Saved graph Append token for: \(graphId), cleared \(clearedCount) hardError items")
        } else {
            logger.info("Saved graph Append token for: \(graphId)")
        }
    }

    // MARK: - Delete Tokens

    // Delete Append token for a specific graph.
    func deleteGraphAppendToken(graphId: String) throws {
        try KeychainService.shared.delete(for: .graphAppendToken(graphId: graphId))
        cachedGraphTokens.removeValue(forKey: graphId)
        logger.info("Deleted graph Append token for: \(graphId)")
    }

    // MARK: - Private Helpers

    // Clear hardError flag on all pending OutboxItems.
    // Returns count of items cleared.
    private func clearHardErrors(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { item in
                item.hardError == true
            }
        )

        guard let items = try? context.fetch(descriptor) else {
            return 0
        }

        for item in items {
            item.hardError = false
            item.nextAttemptAt = Date() // Retry soon
        }

        try? context.save()
        return items.count
    }

    // Clear hardError flag on OutboxItems targeting a specific graph.
    // Returns count of items cleared.
    private func clearHardErrors(in context: ModelContext, forGraphId graphId: String) -> Int {
        let descriptor = FetchDescriptor<OutboxItem>(
            predicate: #Predicate { item in
                item.hardError == true && item.targetGraphId == graphId
            }
        )

        guard let items = try? context.fetch(descriptor) else {
            return 0
        }

        for item in items {
            item.hardError = false
            item.nextAttemptAt = Date() // Retry soon
        }

        try? context.save()
        return items.count
    }
}
