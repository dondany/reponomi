import Foundation

public enum GitHubError: LocalizedError, Equatable {
    case tokenRequired
    case unauthorized
    case notFound
    case unknownOwner(String)
    case rateLimited(reset: Date?)
    case http(status: Int, message: String)
    case badResponse
    case invalidHost(String)
    case malformedToken

    public var errorDescription: String? {
        switch self {
        case .tokenRequired:
            return "An access token is required."
        case .unauthorized:
            return "GitHub rejected the access token."
        case .notFound:
            return "Not found."
        case .unknownOwner(let name):
            return "No organization or user named “\(name)”, or the token can’t see it."
        case .rateLimited(let reset):
            guard let reset else { return "GitHub rate limit reached." }
            return "GitHub rate limit reached; try again after \(reset.formatted(date: .omitted, time: .shortened))."
        case .http(let status, let message):
            return message.isEmpty ? "GitHub returned HTTP \(status)." : "GitHub returned HTTP \(status): \(message)"
        case .badResponse:
            return "Unexpected response from GitHub."
        case .invalidHost(let host):
            return "“\(host)” isn’t a valid hostname."
        case .malformedToken:
            return "The access token contains characters a token can’t have."
        }
    }
}

public struct GitHubClient {
    public let host: String
    public let token: String?
    private let session: URLSession

    /// 100 repositories per page, so this caps a single source at 10,000.
    private static let maxPages = 100
    /// A page of 100 repositories is well under a megabyte.
    private static let maxPageBytes = 16_000_000

    /// Keeps nothing on disk and carries no cookies, so responses (which
    /// name private repositories) and sessions never outlive a request.
    private static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    public init(host: String = "github.com", token: String? = nil) {
        self.init(host: host, token: token, session: Self.privateSession)
    }

    init(host: String, token: String?, session: URLSession) {
        self.host = host
        self.token = token
        self.session = session
    }

    /// github.com and GitHub Enterprise Cloud with data residency (`*.ghe.com`)
    /// serve the API from an `api.` subdomain; GitHub Enterprise Server serves
    /// it under `/api/v3`.
    var apiBase: String {
        host == "github.com" || host.hasSuffix(".ghe.com") ? "https://api.\(host)" : "https://\(host)/api/v3"
    }

    /// Repositories of an organization, or of a user when no such organization exists.
    public func repos(owner: String) async throws -> [Repo] {
        // The name becomes part of the request's path.
        guard Repo.isSafeName(owner) else { throw GitHubError.unknownOwner(owner) }
        do {
            return try await fetchAll("\(apiBase)/orgs/\(owner)/repos?per_page=100&type=all")
        } catch GitHubError.notFound {
            do {
                return try await fetchAll("\(apiBase)/users/\(owner)/repos?per_page=100&type=owner")
            } catch GitHubError.notFound {
                throw GitHubError.unknownOwner(owner)
            }
        }
    }

    /// Every repository the authenticated user owns, collaborates on, or can reach through an organization.
    public func myRepos() async throws -> [Repo] {
        guard token != nil else { throw GitHubError.tokenRequired }
        return try await fetchAll("\(apiBase)/user/repos?per_page=100&affiliation=owner,collaborator,organization_member")
    }

    private func fetchAll(_ start: String) async throws -> [Repo] {
        // The token goes to this host, so it has to be a host and nothing more.
        guard Config.isValidHost(host) else { throw GitHubError.invalidHost(host) }
        if let token, !token.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }) {
            throw GitHubError.malformedToken
        }
        var repos: [Repo] = []
        var next = URL(string: start)
        var pages = 0
        while let url = next, pages < Self.maxPages {
            var request = URLRequest(url: url)
            // An internal host that is unreachable off the VPN should fail fast.
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw GitHubError.badResponse }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                // Don't let a server fill memory with an endless response.
                guard data.count <= Self.maxPageBytes else { throw GitHubError.badResponse }
            }
            guard http.statusCode == 200 else { throw Self.error(for: http, body: data) }
            repos += try decodeRepos(data)
            next = http.value(forHTTPHeaderField: "Link").flatMap(nextPage)
            pages += 1
        }
        return repos
    }

    private static func error(for response: HTTPURLResponse, body: Data) -> GitHubError {
        struct Body: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(Body.self, from: body))?.message ?? ""
        let quotaExhausted = response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
        switch response.statusCode {
        case 401:
            return .unauthorized
        case 404:
            return .notFound
        case 403 where quotaExhausted, 429 where quotaExhausted:
            let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
            return .rateLimited(reset: reset.map(Date.init(timeIntervalSince1970:)))
        default:
            return .http(status: response.statusCode, message: message)
        }
    }

    /// The `rel="next"` target of a `Link` response header, if any.
    static func nextLink(_ header: String) -> URL? {
        for part in header.components(separatedBy: ",") {
            let pieces = part.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.dropFirst().contains(#"rel="next""#),
                  let target = pieces.first, target.hasPrefix("<"), target.hasSuffix(">")
            else { continue }
            return URL(string: String(target.dropFirst().dropLast()))
        }
        return nil
    }

    /// The next page to fetch, which must be on this host's API over HTTPS:
    /// the request carries the token, so a response must not be able to
    /// send it elsewhere.
    func nextPage(_ header: String) -> URL? {
        guard let next = Self.nextLink(header),
              next.scheme == "https",
              let host = next.host, host.lowercased() == URL(string: apiBase)?.host
        else { return nil }
        return next
    }

    /// The repositories in an API response. The response is not trusted to
    /// say where a repository lives: its URL is built from this client's
    /// host, and entries with malformed names are dropped.
    func decodeRepos(_ data: Data) throws -> [Repo] {
        struct Payload: Decodable {
            struct Owner: Decodable { let login: String }
            let id: Int
            let name: String
            let owner: Owner
            let description: String?
            let `private`: Bool
            let archived: Bool?
            let fork: Bool?
            let pushedAt: Date?
            let defaultBranch: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Payload].self, from: data).compactMap {
            guard Repo.isSafeName($0.owner.login), Repo.isSafeName($0.name) else { return nil }
            return Repo(
                id: $0.id,
                name: $0.name,
                owner: $0.owner.login,
                htmlURL: "https://\(host)/\($0.owner.login)/\($0.name)",
                description: $0.description.map(Self.displayable),
                isPrivate: $0.private,
                isArchived: $0.archived ?? false,
                isFork: $0.fork ?? false,
                pushedAt: $0.pushedAt,
                defaultBranch: $0.defaultBranch.flatMap { $0.count <= 255 ? Self.displayable($0) : nil }
            )
        }
    }

    /// Free text from the server, cut to a sensible length and stripped of
    /// control characters and of the direction overrides that can make text
    /// read as something other than what it is.
    static func displayable(_ text: String) -> String {
        let scalars = text.unicodeScalars.prefix(400).filter { scalar in
            scalar.properties.generalCategory != .control
                && !(0x202A...0x202E).contains(scalar.value)
                && !(0x2066...0x2069).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
