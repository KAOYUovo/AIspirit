import Testing
import Perception
import DebugTools

@Test func webMetadataGateDoesNotSearchWhenFlagIsDisabled() async {
    let metadata = WebMetadataResult(query: "NBA", title: "NBA", summary: "basketball")
    var flags = PerceptionFeatureFlags()
    flags.webMetadataSearch = false

    let result = await WebMetadataSearchGate(
        searcher: MockWebMetadataSearch(result: metadata),
        featureFlags: flags
    ).search(searchInput())

    #expect(result.didRun == false)
    #expect(result.query == nil)
    #expect(result.result == nil)
    #expect(result.errors.isEmpty)
}

@Test func webMetadataGateDoesNotSearchWhenPrivacyBlocked() async {
    var flags = PerceptionFeatureFlags()
    flags.webMetadataSearch = true

    let result = await WebMetadataSearchGate(
        searcher: MockWebMetadataSearch(),
        featureFlags: flags
    ).search(searchInput(privacyPassed: false))

    #expect(result.didRun == false)
    #expect(result.query == nil)
    #expect(result.errors.first?.code == "web_metadata_blocked_by_privacy")
}

@Test func webMetadataGateSearchesSanitizedTextQueryWhenEnabled() async {
    let metadata = WebMetadataResult(query: "sports NBA Finals", title: "NBA Finals", summary: "basketball")
    var flags = PerceptionFeatureFlags()
    flags.webMetadataSearch = true

    let result = await WebMetadataSearchGate(
        searcher: MockWebMetadataSearch(result: metadata),
        featureFlags: flags,
        maxQueryLength: 80
    ).search(searchInput())

    #expect(result.didRun)
    #expect(result.result == metadata)
    #expect(result.query?.contains("sports") == true)
    #expect(result.query?.contains("NBA") == true)
    #expect(result.query?.contains("98") == false)
    #expect(result.query?.contains("keyframes") == false)
}

@Test func webMetadataGateRecordsFallbackWhenSearchFails() async {
    var flags = PerceptionFeatureFlags()
    flags.webMetadataSearch = true

    let result = await WebMetadataSearchGate(
        searcher: MockWebMetadataSearch(error: .networkDisabled),
        featureFlags: flags
    ).search(searchInput())

    #expect(result.didRun)
    #expect(result.result == nil)
    #expect(result.errors.first?.code == "web_metadata_search_failed")
    #expect(result.errors.first?.isFallbackApplied == true)
}

private func searchInput(privacyPassed: Bool = true) -> WebMetadataSearchInput {
    WebMetadataSearchInput(
        contentType: .sports,
        windowTitles: ["NBA Finals Live"],
        ocrText: ["LAL 98 BOS 96"],
        audioTranscript: "final minute two point game",
        privacyPassed: privacyPassed
    )
}
