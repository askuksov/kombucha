import Foundation
import KombuchaCore

/// Reads the tag of the latest release from GitHub. This is the only network request the app makes.
struct GitHubReleaseFetcher: ReleaseFetching {
    enum Failure: Error, Equatable {
        case status(Int)
        case badBody
        case draftOrPrerelease
        case tooLarge
    }

    static let endpoint = URL(string: "https://api.github.com/repos/askuksov/kombucha/releases/latest")!
    static let maximumBody = 1_000_000

    private let session: URLSession

    init(session: URLSession = GitHubReleaseFetcher.makeSession()) {
        self.session = session
    }

    /// No cookies, no cache, no stored credentials: nothing about the request outlives it.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    /// No version, no identifier: GitHub learns the address of the Mac and nothing else.
    static func request() -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Kombucha", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// The only field used from the body is the tag; the response's own URL is never read.
    static func tag(status: Int, body: Data) throws -> String {
        guard status == 200 else { throw Failure.status(status) }
        guard body.count <= maximumBody else { throw Failure.tooLarge }
        struct Release: Decodable {
            let tag: String
            let draft: Bool?
            let prerelease: Bool?
            enum CodingKeys: String, CodingKey {
                case tag = "tag_name"
                case draft
                case prerelease
            }
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: body) else { throw Failure.badBody }
        if release.draft == true || release.prerelease == true { throw Failure.draftOrPrerelease }
        return release.tag
    }

    func latestTag() async throws -> String {
        let (data, response) = try await session.data(for: Self.request())
        guard let http = response as? HTTPURLResponse else { throw Failure.badBody }
        return try Self.tag(status: http.statusCode, body: data)
    }
}
