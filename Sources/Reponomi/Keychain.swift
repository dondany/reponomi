import Foundation
import Security
import ReponomiCore

/// Access tokens, stored per GitHub host in the login keychain.
enum Keychain {
    private static let service = "Reponomi"

    static func token(for host: String) -> String? {
        var query = item(host)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `token` for `host`; an empty token removes the entry.
    @discardableResult
    static func setToken(_ token: String, for host: String) -> Bool {
        SecItemDelete(item(host) as CFDictionary)
        guard !token.isEmpty else { return true }
        var attributes = item(host)
        attributes[kSecValueData] = Data(token.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func item(_ host: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: host]
    }
}

enum Credentials {
    /// The token to authenticate with, or nil to make anonymous requests.
    /// May block briefly while running `gh`.
    static func token(for account: Account) throws -> String? {
        switch account.auth {
        case .token:
            guard let saved = Keychain.token(for: account.host), !saved.isEmpty else { return nil }
            return saved
        case .githubCLI:
            return try GitHubCLI.token(for: account.host)
        }
    }
}
