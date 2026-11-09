import Foundation
import Testing
@testable import AIBarCore

@Test func decodesBarPayloadStringClass() throws {
    let data = Data(#"{"text":"O(2) → 42%","tooltip":"Codex","class":"warning provider-codex","percentage":12,"percentageLabel":"Session","resetCredits":2,"resetCreditDetails":[{"title":"Full reset","expiresAt":1800000000},{"title":"Full reset","expiresAt":1900000000}],"updatedAt":"2026-07-11T08:10:00.000Z","accessState":"available"}"#.utf8)
    let payload = try JSONDecoder().decode(AIBarPayload.self, from: data)

    #expect(payload.text == "O(2) → 42%")
    #expect(payload.classes == ["warning", "provider-codex"])
    #expect(payload.percentage == 12)
    #expect(payload.percentageLabel == "Session")
    #expect(payload.resetCredits == 2)
    #expect(payload.resetCreditDetails.map(\.title) == ["Full reset", "Full reset"])
    #expect(payload.resetCreditDetails.map(\.expiresAt) == [1_800_000_000, 1_900_000_000])
    #expect(payload.resetCreditDetails[0].displayText.contains("Full reset\nExpires "))
    #expect(payload.updatedAt == "2026-07-11T08:10:00.000Z")
    #expect(payload.updatedTimeText != nil)
    #expect(payload.severity == .warning)
}

@Test func resetCreditExpiryUrgencyUsesTwoAndOneWeekThresholds() {
    let now = 2_000_000_000.0
    let day = 24.0 * 60 * 60

    #expect(aiBarExpiryUrgency(expiresAt: now + 14 * day + 1, now: now) == nil)
    #expect(aiBarExpiryUrgency(expiresAt: now + 14 * day, now: now) == .warning)
    #expect(aiBarExpiryUrgency(expiresAt: now + 7 * day + 1, now: now) == .warning)
    #expect(aiBarExpiryUrgency(expiresAt: now + 7 * day, now: now) == .critical)
}

@Test func decodesBarPayloadArrayClassAndSeverityPriority() throws {
    let data = Data(#"{"text":"A ↑ 95%","tooltip":"Claude","class":["stale","critical","provider-claude"],"accessState":"stale"}"#.utf8)
    let payload = try JSONDecoder().decode(AIBarPayload.self, from: data)

    #expect(payload.classes == ["stale", "critical", "provider-claude"])
    #expect(payload.severity == .critical)
    #expect(payload.resetCreditDetails.isEmpty)
}

@Test func decodesStructuredUsageRows() throws {
    let data = Data(#"{"text":"X → ◉42% ⧖42%","tooltip":"Week 42% · reset 3d\nUpdated: 12:00 PM","class":["provider-grok"],"percentage":42,"percentageLabel":"Weekly","accessState":"available","usageRows":[{"label":"Cursor Models (Monthly)","percentage":12,"resetText":"14d6h","severity":"normal","isCurrent":true,"pacing":{"expectedPercentage":10}},{"label":"Other Models (Monthly)","percentage":8,"resetText":"14d6h","severity":"normal","isCurrent":true,"pacing":{"expectedPercentage":10}},{"label":"GrokBot (Weekly)","percentage":42,"resetText":"3d","severity":"critical","isCurrent":true,"pacing":{"expectedPercentage":42}}]}"#.utf8)
    let payload = try JSONDecoder().decode(AIBarPayload.self, from: data)

    #expect(payload.classes == ["provider-grok"])
    #expect(payload.percentage == 42)
    #expect(payload.percentageLabel == "Weekly")
    #expect(payload.severity == .normal)
    #expect(payload.accessState == .available)
    #expect(payload.usageRows.map(\.label) == ["Cursor Models (Monthly)", "Other Models (Monthly)", "GrokBot (Weekly)"])
    #expect(payload.usageRows.map(\.percentage) == [12, 8, 42])
    #expect(payload.usageRows.last?.severity == .critical)
    #expect(payload.usageRows[0].pacing?.expectedPercentage == 10)
    #expect(payload.macOSDetail.isEmpty)
}

@Test func decodesRequiredProviderAccessState() throws {
    let requiredData = Data(#"{"text":"⚠ X","tooltip":"Grok sign-in required.","class":["error","provider-grok"],"accessState":"login_required"}"#.utf8)
    let required = try JSONDecoder().decode(AIBarPayload.self, from: requiredData)
    #expect(required.accessState == .loginRequired)

    let legacyData = Data(#"{"text":"X","tooltip":"Week 1%","class":["provider-grok"],"authenticationRequired":true}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(AIBarPayload.self, from: legacyData)
    }
}

@Test func decodesUnavailableQuotaWithoutInventingUsage() throws {
    let data = Data(#"{"text":"S -4%","tooltip":"Week unavailable","accessState":"available","unavailableUsageLabels":["GrokBot (Weekly)"],"usageRows":[{"label":"Cursor Models (Monthly)","percentage":100,"resetText":"1d3h","severity":"warning","isCurrent":true}]}"#.utf8)
    let payload = try JSONDecoder().decode(AIBarPayload.self, from: data)
    #expect(payload.unavailableUsageLabels == ["GrokBot (Weekly)"])
    #expect(payload.usageRows.map(\.label) == ["Cursor Models (Monthly)"])
    #expect(payload.usageRows.first?.percentage == 100)
    #expect(AIBarPayload(text: "O", tooltip: "Week 10%").unavailableUsageLabels.isEmpty)
}

@Test func structuredRowsRemoveDuplicatedQuotaAndCreditDetail() throws {
    let data = Data(#"{"text":"O(1) ↑ ◉21% ⧖13%","tooltip":"Session unavailable\nWeek 21% · critical · reset 6d1h\nCredits 1\nUpdated: 03:51 PM","class":["critical","provider-codex"],"accessState":"available","resetCredits":1,"usageRows":[{"label":"Weekly","percentage":21,"resetText":"6d1h","severity":"critical","isCurrent":true}]}"#.utf8)
    let payload = try JSONDecoder().decode(AIBarPayload.self, from: data)

    #expect(payload.macOSDetail == "Session unavailable")
}

@Test func providerMetadataMatchesSharedEngine() {
    #expect(AIBarProvider.codex.displayName == "OpenAI")
    #expect(AIBarProvider.claude.displayName == "Anthropic")
    #expect(AIBarProvider.grok.displayName == "SpaceXSI")
    #expect(AIBarProvider.codex.badge == "O")
    #expect(AIBarProvider.claude.badge == "A")
    #expect(AIBarProvider.grok.badge == "S")
    #expect(AIBarProvider.dashboardOrder == [.claude, .codex, .grok])
}

@Test func presentsProviderAccessStatesConsistently() {
    #expect(AIBarAccessState.available.statusLabel == nil)
    #expect(AIBarAccessState.stale.statusLabel == "Usage unavailable")
    #expect(AIBarAccessState.unavailable.statusLabel == "Usage unavailable")
    #expect(AIBarAccessState.loginRequired.statusLabel == "Login required")
    #expect(AIBarAccessState.subscriptionExpired.statusLabel == "Subscription expired")
    #expect(AIBarAccessState.loginRequired.showsLoginAction)
    #expect(!AIBarAccessState.subscriptionExpired.showsLoginAction)
}

@Test func derivesMenuBarBadgeSeverityFromWeeklyUsage() throws {
    let data = Data(#"{"providers":[{"provider":"claude","weeklyPace":1,"payload":{"text":"A","tooltip":"Claude","accessState":"available","usageRows":[{"label":"Weekly","percentage":74.99,"resetText":"1d","severity":"normal","isCurrent":true}]}},{"provider":"codex","weeklyPace":1,"payload":{"text":"O","tooltip":"Codex","accessState":"available","usageRows":[{"label":"Weekly","percentage":75,"resetText":"1d","severity":"normal","isCurrent":true}]}},{"provider":"grok","weeklyPace":1,"payload":{"text":"S","tooltip":"SpaceXSI","accessState":"available","usageRows":[{"label":"Cursor Models (Monthly)","percentage":99,"resetText":"1d","severity":"critical","isCurrent":true},{"label":"GrokBot (Weekly)","percentage":89.99,"resetText":"1d","severity":"normal","isCurrent":true}]}}]}"#.utf8)
    let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)

    #expect(aggregate.payload(for: .claude)?.menuBarBadgeSeverity == .normal)
    #expect(aggregate.payload(for: .codex)?.menuBarBadgeSeverity == .warning)
    #expect(aggregate.payload(for: .grok)?.weeklyUsagePercentage == 89.99)
    #expect(aggregate.payload(for: .grok)?.menuBarBadgeSeverity == .warning)
}

@Test func makesMenuBarBadgeCriticalAtNinetyPercent() throws {
    let data = Data(#"{"providers":[{"provider":"claude","weeklyPace":1,"payload":{"text":"A","tooltip":"Claude","accessState":"available","usageRows":[{"label":"Weekly","percentage":1,"resetText":"2d","severity":"normal","isCurrent":true}]}},{"provider":"codex","weeklyPace":1,"payload":{"text":"O","tooltip":"Codex","accessState":"available","usageRows":[{"label":"Weekly","percentage":90,"resetText":"1d","severity":"normal","isCurrent":true}]}}]}"#.utf8)
    let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)

    #expect(aggregate.payload(for: .claude)?.menuBarBadgeSeverity == .normal)
    #expect(aggregate.payload(for: .codex)?.menuBarBadgeSeverity == .critical)
}

@Test func decodesCombinedProviderPaceForMenuBar() throws {
    let data = Data(#"{"providers":[{"provider":"grok","weeklyPace":39,"payload":{"text":"X","tooltip":"Grok","accessState":"available","usageRows":[{"label":"GrokBot (Weekly)","percentage":1,"resetText":"2d","severity":"normal","isCurrent":true}]}},{"provider":"claude","weeklyPace":-1,"payload":{"text":"A","tooltip":"Claude","accessState":"available","usageRows":[{"label":"Weekly","percentage":1,"resetText":"2d","severity":"normal","isCurrent":true}]}},{"provider":"codex","weeklyPace":4,"payload":{"text":"O","tooltip":"Codex","accessState":"available","usageRows":[{"label":"Weekly","percentage":1,"resetText":"2d","severity":"normal","isCurrent":true}]}}]}"#.utf8)
    let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)

    #expect(aggregate.payload(for: .claude)?.paceText == "-1%")
    #expect(aggregate.payload(for: .codex)?.paceText == "+4%")
    #expect(aggregate.payload(for: .grok)?.paceText == "+39%")
    #expect(aggregate.menuBarText == "A -1%  O +4%  S +39%")
}

@Test func menuBarSelectionOverridesSignedPaceSummary() throws {
    let data = Data(#"{"providers":[{"provider":"codex","weeklyPace":-2,"payload":{"text":"O","tooltip":"Codex","accessState":"available","usageRows":[{"label":"Weekly","percentage":78,"resetText":"1d","severity":"warning","isCurrent":true}]}}],"menuBar":{"text":"O 78%  SC 88%","rows":["codex:Weekly","grok:Cursor Models (Monthly)"],"segments":[{"text":"O 78%","severity":"warning","isCurrent":true},{"text":"SC 88%","severity":"critical","isCurrent":true}]}}"#.utf8)
    let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)

    #expect(aggregate.menuBarText == "O 78%  SC 88%")
    #expect(aggregate.menuBar?.rows == ["codex:Weekly", "grok:Cursor Models (Monthly)"])
    #expect(aggregate.menuBar?.segments.map(\.severity) == [.warning, .critical])
}

@Test func combinedProviderPaceOmitsLostAccessOnly() throws {
    let data = Data(#"{"providers":[{"provider":"claude","weeklyPace":null,"payload":{"text":"A","tooltip":"Temporarily unavailable","accessState":"unavailable"}},{"provider":"codex","weeklyPace":4,"payload":{"text":"O","tooltip":"Login required","accessState":"login_required"}},{"provider":"grok","weeklyPace":39,"payload":{"text":"X","tooltip":"Subscription expired","accessState":"subscription_expired"}}]}"#.utf8)
    let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)

    #expect(aggregate.payload(for: .claude)?.isCompactEligible == false)
    #expect(aggregate.payload(for: .codex)?.isCompactEligible == false)
    #expect(aggregate.payload(for: .grok)?.isCompactEligible == false)
    #expect(aggregate.menuBarText == "AIBar")
}

@Test func staleUsageLeavesCountersUntilRecovery() throws {
    for state in ["available", "stale", "unavailable", "available"] {
        let data = Data("""
        {"providers":[{"provider":"claude","weeklyPace":8,"payload":{"text":"A 42%","tooltip":"Week 42%","accessState":"\(state)","usageRows":[{"label":"Weekly","percentage":42,"resetText":"2d","severity":"normal","isCurrent":\(state == "available"),"pacing":{"expectedPercentage":50}}]}}]}
        """.utf8)
        let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)
        #expect(aggregate.compactEntries.count == (state == "available" ? 1 : 0))
        #expect(aggregate.menuBarText == (state == "available" ? "A +8%" : "AIBar"))
    }
}

@Test func delayedMenuBarSelectionCannotRestoreStaleOrOldUsage() throws {
    let data = Data(#"{"providers":[{"provider":"claude","weeklyPace":8,"payload":{"text":"A","tooltip":"cached","accessState":"stale","usageRows":[{"label":"Weekly","percentage":42,"resetText":"2d","severity":"normal","isCurrent":false,"pacing":{"expectedPercentage":50}}]}},{"provider":"codex","weeklyPace":1,"payload":{"text":"O","tooltip":"live","accessState":"available","usageRows":[{"label":"Weekly","percentage":49,"resetText":"2d","severity":"normal","isCurrent":true,"pacing":{"expectedPercentage":50}}]}}]}"#.utf8)
    let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)
    let oldSummary = AIBarMenuBar(text: "A +8%  O +40%", rows: ["claude:Weekly", "codex:Weekly"], segments: [
        AIBarMenuBarSegment(text: "A +8%", severity: .normal),
        AIBarMenuBarSegment(text: "O +40%", severity: .normal),
    ])
    let result = aggregate.replacingMenuBar(oldSummary)
    #expect(result.menuBarText == "O +1%")
    #expect(result.menuBar?.rows == ["codex:Weekly"])
    #expect(result.selectingMenuBarRow(provider: .claude, label: "Weekly").menuBarText == "O +1%")
    #expect(AIBarAggregatePayload(providers: []).replacingMenuBar(oldSummary).menuBarText == "AIBar")
}

@Test func quotaFreshnessIsIndependentOfProviderStatus() throws {
    for state in ["available", "stale", "unavailable"] {
        for sessionCurrent in [true, false] {
            let data = Data("""
            {"providers":[{"provider":"claude","weeklyPace":8,"payload":{"text":"A","tooltip":"","accessState":"\(state)","usageRows":[{"label":"Session","percentage":12,"resetText":"2h","severity":"normal","isCurrent":\(sessionCurrent),"pacing":{"expectedPercentage":50}},{"label":"Weekly","percentage":17,"resetText":"2d","severity":"normal","isCurrent":\(!sessionCurrent),"pacing":{"expectedPercentage":50}}]}}]}
            """.utf8)
            let aggregate = try JSONDecoder().decode(AIBarAggregatePayload.self, from: data)
            let payload = try #require(aggregate.payload(for: .claude)?.payload)
            #expect(payload.currentUsageRows.map(\.label) == [sessionCurrent ? "Session" : "Weekly"])
            #expect(payload.staleUsageLabels == [sessionCurrent ? "Weekly" : "Session"])
            #expect(aggregate.selectingMenuBarRow(provider: .claude, label: "Weekly").menuBarText == (sessionCurrent ? "A +38%" : "A +33%"))
        }
    }
}

@Test func removesDuplicatedHeaderFromMacOSDetailOnly() {
    let payload = AIBarPayload(
        text: "O(1)",
        tooltip: "AIBar\n-----------\nProvider: Codex (oauth)\n\nSession: 1%\n\nFree reset credits: 1\n\nUpdated: 15:10",
        resetCredits: 1
    )

    #expect(payload.macOSDetail == "Provider: Codex (oauth)\n\nSession: 1%")
    #expect(payload.tooltip.hasPrefix("AIBar\n-----------"))
}

@Test func keepsWeeklyUsageInMacOSDetail() {
    let payload = AIBarPayload(
        text: "O(1) ↑ ◉4% ⧖2% 6d21h",
        tooltip: "AIBar\n-----------\nProvider: Codex (oauth)\n\nSession: 26% (52% under)\n  Resets in 2h17m\n\nWeekly: 4% (100% ahead)\n  Resets in 6d21h\n\nFree reset credits: 1\n\nUpdated: 03:45 PM"
    )

    #expect(payload.macOSDetail.contains("Weekly: 4% (100% ahead)"))
    #expect(payload.macOSDetail.contains("Resets in 6d21h"))
}
