import Foundation
import Testing
@testable import Kombucha

private func body(_ json: String) -> Data { Data(json.utf8) }

@Test func theRequestAsksGitHubForTheLatestReleaseAndNothingElse() {
    let request = GitHubReleaseFetcher.request()
    #expect(request.url == URL(string: "https://api.github.com/repos/askuksov/kombucha/releases/latest"))
    #expect(request.httpMethod == "GET")
    #expect(request.httpBody == nil)
    #expect(request.timeoutInterval == 10)
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "Kombucha")
    #expect(request.allHTTPHeaderFields?.keys.sorted() == ["Accept", "User-Agent"])
}

@Test func theSessionKeepsNothingOnDisk() {
    let configuration = GitHubReleaseFetcher.makeSession().configuration
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.timeoutIntervalForRequest == 10)
}

@Test func theTagIsReadFromAGoodResponse() throws {
    let json = #"{"tag_name":"v0.2.0","draft":false,"prerelease":false,"html_url":"https://example.com/elsewhere","assets":[]}"#
    #expect(try GitHubReleaseFetcher.tag(status: 200, body: body(json)) == "v0.2.0")
    #expect(try GitHubReleaseFetcher.tag(status: 200, body: body(#"{"tag_name":"v1.0.0"}"#)) == "v1.0.0")
}

@Test(arguments: [403, 404, 500, 304])
func aStatusOtherThan200IsAnError(status: Int) {
    #expect(throws: GitHubReleaseFetcher.Failure.status(status)) {
        try GitHubReleaseFetcher.tag(status: status, body: body(#"{"tag_name":"v0.2.0"}"#))
    }
}

@Test(arguments: ["", "not json", "[]", #"{"name":"x"}"#, #"{"tag_name":7}"#])
func aBodyWithoutATagIsAnError(json: String) {
    #expect(throws: GitHubReleaseFetcher.Failure.badBody) {
        try GitHubReleaseFetcher.tag(status: 200, body: body(json))
    }
}

@Test func aDraftOrAPreReleaseIsAnError() {
    #expect(throws: GitHubReleaseFetcher.Failure.draftOrPrerelease) {
        try GitHubReleaseFetcher.tag(status: 200, body: body(#"{"tag_name":"v0.2.0","draft":true}"#))
    }
    #expect(throws: GitHubReleaseFetcher.Failure.draftOrPrerelease) {
        try GitHubReleaseFetcher.tag(status: 200, body: body(#"{"tag_name":"v0.2.0","prerelease":true}"#))
    }
}

@Test func aHugeBodyIsRefusedBeforeItIsParsed() {
    let huge = Data(repeating: 0x20, count: GitHubReleaseFetcher.maximumBody + 1)
    #expect(throws: GitHubReleaseFetcher.Failure.tooLarge) {
        try GitHubReleaseFetcher.tag(status: 200, body: huge)
    }
}
