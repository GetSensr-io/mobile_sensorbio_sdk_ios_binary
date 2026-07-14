import Foundation

/// Full lineage for a request that discovers the sessions available on one day.
struct SleepSessionsRequestKey: Codable, Hashable, Sendable {
    let accountScope: String
    let localDay: SleepLocalDay
    let requestGeneration: UInt64
}

/// SDK notifications that carry no session identity. They can only prompt a
/// fresh, lineage-keyed reconciliation.
enum SleepVoidPipelineSignal: String, Codable, Equatable, Sendable {
    case stored
    case uploaded
    case sync
}

/// Effects requested by the pure journey reducer.
enum SleepJourneyCommand: Equatable, Sendable {
    case cancelRequests
    case clearPersistedMetadata(accountScope: String)
    case reconcileSessions(SleepSessionsRequestKey)
}

/// Pure state for selecting and reconciling exact sleep-session lineages.
struct SleepJourneyState: Equatable, Sendable {
    private(set) var accountScope: String?
    private(set) var selectedDay: SleepLocalDay?
    private(set) var allSessions: [SleepSessionSummary]
    private(set) var selection: SleepSessionSelection
    private(set) var selectedSnapshot: SleepAtomicSnapshot?
    private(set) var lastCompleted: SleepAtomicSnapshot?
    private(set) var pendingCandidates: [SleepCandidateKey: SleepPendingCandidate]
    private(set) var pipelineState: SleepProcessingState
    private(set) var reconciliationRequested: Bool
    private(set) var analysisOutcome: SleepAnalysisOutcome
    private(set) var transport: SleepTransportState
    private(set) var freshness: SleepFreshness
    private(set) var circadianAvailability: SleepCircadianAvailability
    private(set) var requestGeneration: UInt64

    private var candidateGeneration: UInt64

    var displaySnapshot: SleepAtomicSnapshot? {
        lastCompleted
    }

    init(
        accountScope: String? = nil,
        selectedDay: SleepLocalDay? = nil
    ) {
        self.accountScope = accountScope
        self.selectedDay = selectedDay
        allSessions = []
        selection = Self.emptySelection
        selectedSnapshot = nil
        lastCompleted = nil
        pendingCandidates = [:]
        pipelineState = SleepProcessingState()
        reconciliationRequested = false
        analysisOutcome = .unknown
        transport = .idle
        freshness = .stale
        circadianAvailability = .unknown
        requestGeneration = 0
        candidateGeneration = 0
    }

    /// Changes account scope atomically. Nothing carrying the old account's
    /// identity or presentation state survives the transition.
    mutating func setAccountScope(_ newAccountScope: String?) -> [SleepJourneyCommand] {
        guard newAccountScope != accountScope else {
            return []
        }

        let oldAccountScope = accountScope
        accountScope = newAccountScope
        selectedDay = nil
        allSessions = []
        selection = Self.emptySelection
        selectedSnapshot = nil
        lastCompleted = nil
        pendingCandidates = [:]
        pipelineState = SleepProcessingState()
        reconciliationRequested = false
        analysisOutcome = .unknown
        transport = .idle
        freshness = .stale
        circadianAvailability = .unknown
        requestGeneration &+= 1
        candidateGeneration = 0

        var commands: [SleepJourneyCommand] = [.cancelRequests]
        if let oldAccountScope {
            commands.append(.clearPersistedMetadata(accountScope: oldAccountScope))
        }
        return commands
    }

    /// Selects a new local day, invalidating only the selected request lineage.
    /// Dated completed history and every independent pending candidate remain.
    mutating func selectDay(_ newSelectedDay: SleepLocalDay?) -> [SleepJourneyCommand] {
        guard newSelectedDay != selectedDay else {
            return []
        }

        selectedDay = newSelectedDay
        requestGeneration &+= 1
        allSessions = []
        selection = Self.emptySelection
        selectedSnapshot = nil
        analysisOutcome = .unknown
        transport = .idle
        freshness = .stale
        circadianAvailability = .unknown

        var commands: [SleepJourneyCommand] = [.cancelRequests]
        if let key = currentSessionsRequestKey {
            reconciliationRequested = true
            commands.append(.reconcileSessions(key))
        } else {
            reconciliationRequested = false
        }
        return commands
    }

    /// Selects one of the already-fetched exact session identities. A changed
    /// selection owns a new request generation so an older detail response can
    /// never overwrite it.
    mutating func selectSession(
        _ identity: SleepSessionIdentity
    ) -> [SleepJourneyCommand] {
        guard
            selection.selectedSession?.identity != identity,
            allSessions.contains(where: { $0.identity == identity })
        else {
            return []
        }

        requestGeneration &+= 1
        selection = SleepSessionSelection.select(
            from: allSessions,
            preferredIdentity: identity,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )
        selectedSnapshot = nil
        analysisOutcome = .unknown
        transport = .idle
        freshness = .stale
        circadianAvailability = .unknown
        reconciliationRequested = true

        guard let key = currentSessionsRequestKey else {
            return [.cancelRequests]
        }
        return [.cancelRequests, .reconcileSessions(key)]
    }

    /// Records every detection as its own candidate. The provisional end is
    /// retained exclusively for bounded correlation with subsequently fetched
    /// sessions; it never becomes a session identity.
    mutating func recordDetectedSleep(
        localDay: SleepLocalDay,
        provisionalEndTimestampMilliseconds: Int64
    ) -> [SleepJourneyCommand] {
        guard let accountScope else {
            return []
        }

        let generation = nextCandidateGeneration(
            accountScope: accountScope,
            localDay: localDay
        )
        let key = SleepCandidateKey(
            accountScope: accountScope,
            localDay: localDay,
            candidateGeneration: generation
        )
        pendingCandidates[key] = SleepPendingCandidate(
            key: key,
            correlationProvisionalEndTimestampMilliseconds:
                provisionalEndTimestampMilliseconds,
            boundSessionIdentity: nil,
            retryAttempt: 0,
            isRetryExhausted: false
        )
        pipelineState.transition(.detected)
        reconciliationRequested = true

        guard selectedDay == localDay, let requestKey = currentSessionsRequestKey else {
            return []
        }
        return [.reconcileSessions(requestKey)]
    }

    /// Identity-free SDK signals cannot advance processing or resolve a
    /// candidate. They only request another exact-key sessions fetch.
    mutating func receiveVoidPipelineSignal(
        _ signal: SleepVoidPipelineSignal
    ) -> [SleepJourneyCommand] {
        _ = signal
        guard let key = currentSessionsRequestKey else {
            return []
        }
        reconciliationRequested = true
        return [.reconcileSessions(key)]
    }

    /// Commits a sessions response only when its complete request lineage is
    /// still current. Rejected responses leave every field untouched.
    @discardableResult
    mutating func commitSessions(
        _ sessions: [SleepSessionSummary],
        for key: SleepSessionsRequestKey,
        maxCorrelationDistanceMilliseconds: Int64,
        preferredSessionIdentityOverride: SleepSessionIdentity? = nil
    ) -> Bool {
        guard
            accountScope == key.accountScope,
            selectedDay == key.localDay,
            requestGeneration == key.requestGeneration
        else {
            return false
        }

        let previousIdentity = selection.selectedSession?.identity
        let preferredIdentity = preferredSessionIdentityOverride.flatMap { identity in
            sessions.contains(where: { $0.identity == identity }) ? identity : nil
        } ?? preferredSessionIdentity(
            in: sessions,
            accountScope: key.accountScope,
            localDay: key.localDay
        )
        let provisionalEnd = preferredIdentity == nil
            ? bestProvisionalEnd(
                for: sessions,
                accountScope: key.accountScope,
                localDay: key.localDay,
                maxCorrelationDistanceMilliseconds:
                    maxCorrelationDistanceMilliseconds
            )
            : nil
        let newSelection = SleepSessionSelection.select(
            from: sessions,
            preferredIdentity: preferredIdentity,
            provisionalEndTimestampMilliseconds: provisionalEnd,
            maxCorrelationDistanceMilliseconds: maxCorrelationDistanceMilliseconds
        )

        allSessions = sessions
        selection = newSelection
        reconciliationRequested = false

        if previousIdentity != newSelection.selectedSession?.identity {
            selectedSnapshot = nil
            analysisOutcome = .unknown
            freshness = .stale
            circadianAvailability = .unknown
        }
        return true
    }

    /// Binds current-day candidates to current sessions one-to-one. Existing
    /// exact bindings that still exist and remain in range are reserved before
    /// any new nearest-neighbour assignments are made.
    mutating func reconcilePendingCandidates(
        maxCorrelationDistanceMilliseconds: Int64
    ) {
        guard
            let accountScope,
            let selectedDay
        else {
            return
        }

        let keys = pendingCandidates.keys
            .filter {
                $0.accountScope == accountScope && $0.localDay == selectedDay
            }
            .sorted(by: Self.candidateKeyPrecedes)
        guard !keys.isEmpty else {
            reconciliationRequested = false
            return
        }

        let sessionsByIdentity = allSessions.reduce(
            into: [SleepSessionIdentity: SleepSessionSummary]()
        ) { result, session in
            if result[session.identity] == nil {
                result[session.identity] = session
            }
        }
        var reservedIdentities = Set<SleepSessionIdentity>()

        // First reserve every still-valid exact binding. This prevents a later,
        // closer fetch result from relabelling already-correlated history.
        for key in keys {
            guard var candidate = pendingCandidates[key] else {
                continue
            }
            guard
                let identity = candidate.boundSessionIdentity,
                sessionsByIdentity[identity] != nil,
                reservedIdentities.insert(identity).inserted
            else {
                candidate.boundSessionIdentity = nil
                pendingCandidates[key] = candidate
                continue
            }
        }

        // Then assign unbound candidates in generation order to the nearest
        // unreserved exact session, using the domain fallback for every tie.
        for key in keys {
            guard
                var candidate = pendingCandidates[key],
                candidate.boundSessionIdentity == nil
            else {
                continue
            }

            let availableSessions = allSessions.filter {
                !reservedIdentities.contains($0.identity)
            }
            guard let nearest = Self.nearestSession(
                in: availableSessions,
                to: candidate.correlationProvisionalEndTimestampMilliseconds,
                maxCorrelationDistanceMilliseconds:
                    maxCorrelationDistanceMilliseconds
            ) else {
                continue
            }

            candidate.boundSessionIdentity = nearest.identity
            pendingCandidates[key] = candidate
            reservedIdentities.insert(nearest.identity)
        }

        reconciliationRequested = keys.contains {
            pendingCandidates[$0]?.boundSessionIdentity == nil
        }
    }

    /// Commits one atomic detail snapshot only for the exact account/day/session
    /// and request generation that is still selected.
    @discardableResult
    mutating func commitSnapshot(
        _ snapshot: SleepAtomicSnapshot,
        for key: SleepRequestKey
    ) -> Bool {
        guard
            accountScope == key.accountScope,
            selectedDay == key.localDay,
            selection.selectedSession?.identity == key.sessionIdentity,
            requestGeneration == key.requestGeneration,
            snapshot.accountScope == key.accountScope,
            snapshot.localDay == key.localDay,
            snapshot.sourceDay == key.localDay,
            snapshot.sessionIdentity == key.sessionIdentity,
            snapshot.requestGeneration == key.requestGeneration
        else {
            return false
        }

        selectedSnapshot = snapshot
        analysisOutcome = snapshot.outcome
        circadianAvailability = snapshot.circadianAvailability
        freshness = snapshot.freshness
        pipelineState = SleepProcessingState(
            phase: SleepProcessingPhase(
                detailProcessing: snapshot.detail.processing,
                processState: snapshot.detail.sleepScore.processState
            ),
            generation: pipelineState.generation
        )

        if snapshot.outcome == .processedSuccessfully {
            lastCompleted = snapshot
            pendingCandidates = pendingCandidates.filter { _, candidate in
                !(candidate.key.accountScope == key.accountScope
                    && candidate.key.localDay == key.localDay
                    && candidate.boundSessionIdentity == key.sessionIdentity)
            }
            reconciliationRequested = pendingCandidates.values.contains {
                $0.key.accountScope == key.accountScope
                    && $0.key.localDay == key.localDay
                    && $0.boundSessionIdentity == nil
            }
        }
        return true
    }

    mutating func setTransport(_ newTransport: SleepTransportState) {
        transport = newTransport
    }

    mutating func setFreshness(_ newFreshness: SleepFreshness) {
        freshness = newFreshness
    }

    /// Records the attempt only on candidates that participated in this exact
    /// reconciliation. This prevents one candidate from consuming another
    /// candidate's retry budget.
    mutating func markPendingRetryAttempt(
        candidateKeys: [SleepCandidateKey],
        attempt: Int,
        isExhausted: Bool
    ) {
        guard attempt >= 0 else { return }
        for key in candidateKeys {
            guard var candidate = pendingCandidates[key] else { continue }
            candidate.retryAttempt = max(candidate.retryAttempt, attempt)
            candidate.isRetryExhausted = isExhausted
            pendingCandidates[key] = candidate
        }
    }

    /// Compatibility helper for callers that exhaust every current-day
    /// candidate together.
    mutating func markPendingRetryExhausted(attempt: Int) {
        markPendingRetryAttempt(
            candidateKeys: currentPendingCandidateKeys,
            attempt: attempt,
            isExhausted: true
        )
    }

    /// Compatibility helper used when a surface retries the current pending
    /// reconciliation without naming a candidate.
    mutating func resetPendingRetryExhaustion() {
        for key in currentPendingCandidateKeys {
            guard var candidate = pendingCandidates[key] else { continue }
            candidate.retryAttempt = 0
            candidate.isRetryExhausted = false
            pendingCandidates[key] = candidate
        }
    }

    /// Starts a new exact request generation for one explicit candidate retry.
    mutating func retry(
        candidateKey: SleepCandidateKey
    ) -> [SleepJourneyCommand] {
        guard
            candidateKey.accountScope == accountScope,
            candidateKey.localDay == selectedDay,
            var candidate = pendingCandidates[candidateKey]
        else {
            return []
        }

        candidate.retryAttempt = 0
        candidate.isRetryExhausted = false
        pendingCandidates[candidateKey] = candidate
        requestGeneration &+= 1
        selectedSnapshot = nil
        analysisOutcome = .unknown
        transport = .idle
        freshness = .stale
        reconciliationRequested = true

        guard let key = currentSessionsRequestKey else {
            return [.cancelRequests]
        }
        return [.cancelRequests, .reconcileSessions(key)]
    }

    /// Restores lifecycle metadata only. SDK detail payloads are deliberately
    /// absent from the envelope and therefore cannot be restored here.
    mutating func restorePendingMetadata(
        _ envelope: SleepPendingMetadataEnvelope
    ) {
        guard let accountScope else { return }

        selectedDay = envelope.selectedDay
        allSessions = []
        selection = Self.emptySelection
        selectedSnapshot = nil
        lastCompleted = nil
        analysisOutcome = .unknown
        transport = .idle
        freshness = .stale
        circadianAvailability = .unknown
        requestGeneration &+= 1

        var restored: [SleepCandidateKey: SleepPendingCandidate] = [:]
        var largestGeneration: UInt64 = 0
        for metadata in envelope.pendingCandidates {
            let key = SleepCandidateKey(
                accountScope: accountScope,
                localDay: metadata.localDay,
                candidateGeneration: metadata.candidateGeneration
            )
            restored[key] = SleepPendingCandidate(
                key: key,
                correlationProvisionalEndTimestampMilliseconds:
                    metadata.provisionalEndTimestampMilliseconds,
                boundSessionIdentity: metadata.boundSessionIdentity,
                retryAttempt: metadata.retryAttempt,
                isRetryExhausted: metadata.isRetryExhausted
            )
            largestGeneration = max(largestGeneration, metadata.candidateGeneration)
        }
        pendingCandidates = restored
        candidateGeneration = largestGeneration
        reconciliationRequested = selectedDay != nil
            && (!restored.isEmpty || envelope.selectedSessionIdentity != nil)

        if !restored.isEmpty {
            let hasBoundCandidate = restored.values.contains {
                $0.boundSessionIdentity != nil
            }
            pipelineState = SleepProcessingState(
                phase: hasBoundCandidate ? .processing : .detected,
                generation: pipelineState.generation
            )
        } else {
            pipelineState = SleepProcessingState()
        }
    }

    /// Reinstates only a freshly re-fetched, typed-success payload for dated
    /// history. The protected envelope itself never carries this snapshot.
    @discardableResult
    mutating func restoreLastCompleted(
        _ snapshot: SleepAtomicSnapshot
    ) -> Bool {
        guard
            accountScope == snapshot.accountScope,
            snapshot.outcome == .processedSuccessfully,
            snapshot.outcome.permitsBodyStatus,
            snapshot.detail.processing == false,
            snapshot.localDay == snapshot.sourceDay,
            snapshot.sessionIdentity.endDate == snapshot.sourceDay.rawValue
        else {
            return false
        }
        lastCompleted = snapshot
        return true
    }

    func permitsBodyStatus(
        forAccountScope accountScope: String,
        localDay: SleepLocalDay,
        sessionIdentity: SleepSessionIdentity
    ) -> Bool {
        displaySnapshot?.permitsBodyStatus(
            forAccountScope: accountScope,
            localDay: localDay,
            sessionIdentity: sessionIdentity
        ) ?? false
    }

    private static var emptySelection: SleepSessionSelection {
        SleepSessionSelection.select(
            from: [],
            preferredIdentity: nil,
            provisionalEndTimestampMilliseconds: nil,
            maxCorrelationDistanceMilliseconds: 0
        )
    }

    private var currentSessionsRequestKey: SleepSessionsRequestKey? {
        guard let accountScope, let selectedDay else {
            return nil
        }
        return SleepSessionsRequestKey(
            accountScope: accountScope,
            localDay: selectedDay,
            requestGeneration: requestGeneration
        )
    }

    private var currentPendingCandidateKeys: [SleepCandidateKey] {
        guard let accountScope, let selectedDay else { return [] }
        return pendingCandidates.keys
            .filter {
                $0.accountScope == accountScope && $0.localDay == selectedDay
            }
            .sorted(by: Self.candidateKeyPrecedes)
    }

    private mutating func nextCandidateGeneration(
        accountScope: String,
        localDay: SleepLocalDay
    ) -> UInt64 {
        var next = candidateGeneration &+ 1
        while pendingCandidates[SleepCandidateKey(
            accountScope: accountScope,
            localDay: localDay,
            candidateGeneration: next
        )] != nil {
            next &+= 1
        }
        candidateGeneration = next
        return next
    }

    private func preferredSessionIdentity(
        in sessions: [SleepSessionSummary],
        accountScope: String,
        localDay: SleepLocalDay
    ) -> SleepSessionIdentity? {
        if let selectedIdentity = selection.selectedSession?.identity,
           sessions.contains(where: { $0.identity == selectedIdentity }) {
            return selectedIdentity
        }

        return pendingCandidates.values
            .filter {
                $0.key.accountScope == accountScope
                    && $0.key.localDay == localDay
                    && $0.boundSessionIdentity != nil
            }
            .sorted { Self.candidateKeyPrecedes($0.key, $1.key) }
            .compactMap(\.boundSessionIdentity)
            .first { identity in
                sessions.contains(where: { $0.identity == identity })
            }
    }

    private func bestProvisionalEnd(
        for sessions: [SleepSessionSummary],
        accountScope: String,
        localDay: SleepLocalDay,
        maxCorrelationDistanceMilliseconds: Int64
    ) -> Int64? {
        guard maxCorrelationDistanceMilliseconds >= 0 else {
            return nil
        }

        let candidates = pendingCandidates.values
            .filter {
                $0.key.accountScope == accountScope && $0.key.localDay == localDay
            }
            .sorted { Self.candidateKeyPrecedes($0.key, $1.key) }

        var best: (candidate: SleepPendingCandidate, session: SleepSessionSummary, distance: UInt64)?
        for candidate in candidates {
            guard let session = Self.nearestSession(
                in: sessions,
                to: candidate.correlationProvisionalEndTimestampMilliseconds,
                maxCorrelationDistanceMilliseconds:
                    maxCorrelationDistanceMilliseconds
            ) else {
                continue
            }
            let distance = Self.timestampDistance(
                session.endMilliseconds,
                candidate.correlationProvisionalEndTimestampMilliseconds
            )
            guard let currentBest = best else {
                best = (candidate, session, distance)
                continue
            }
            if distance < currentBest.distance
                || (distance == currentBest.distance
                    && Self.prefersForDefault(session, over: currentBest.session))
                || (distance == currentBest.distance
                    && session == currentBest.session
                    && Self.candidateKeyPrecedes(candidate.key, currentBest.candidate.key)) {
                best = (candidate, session, distance)
            }
        }
        return best?.candidate.correlationProvisionalEndTimestampMilliseconds
    }

    private static func nearestSession(
        in sessions: [SleepSessionSummary],
        to provisionalEnd: Int64,
        maxCorrelationDistanceMilliseconds: Int64
    ) -> SleepSessionSummary? {
        guard maxCorrelationDistanceMilliseconds >= 0 else {
            return nil
        }
        let maximumDistance = UInt64(maxCorrelationDistanceMilliseconds)
        return sessions
            .filter {
                timestampDistance($0.endMilliseconds, provisionalEnd) <= maximumDistance
            }
            .min { lhs, rhs in
                let lhsDistance = timestampDistance(lhs.endMilliseconds, provisionalEnd)
                let rhsDistance = timestampDistance(rhs.endMilliseconds, provisionalEnd)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return prefersForDefault(lhs, over: rhs)
            }
    }

    private static func timestampDistance(_ lhs: Int64, _ rhs: Int64) -> UInt64 {
        let signBit = UInt64(1) << 63
        let orderedLHS = UInt64(bitPattern: lhs) ^ signBit
        let orderedRHS = UInt64(bitPattern: rhs) ^ signBit
        return orderedLHS >= orderedRHS
            ? orderedLHS - orderedRHS
            : orderedRHS - orderedLHS
    }

    private static func candidateKeyPrecedes(
        _ lhs: SleepCandidateKey,
        _ rhs: SleepCandidateKey
    ) -> Bool {
        if lhs.candidateGeneration != rhs.candidateGeneration {
            return lhs.candidateGeneration < rhs.candidateGeneration
        }
        if lhs.localDay.rawValue != rhs.localDay.rawValue {
            return lhs.localDay.rawValue < rhs.localDay.rawValue
        }
        return lhs.accountScope < rhs.accountScope
    }

    private static func prefersForDefault(
        _ lhs: SleepSessionSummary,
        over rhs: SleepSessionSummary
    ) -> Bool {
        if lhs.asleepMinutes != rhs.asleepMinutes {
            return lhs.asleepMinutes > rhs.asleepMinutes
        }
        if lhs.endMilliseconds != rhs.endMilliseconds {
            return lhs.endMilliseconds > rhs.endMilliseconds
        }
        if lhs.identity.endTimestamp != rhs.identity.endTimestamp {
            return lhs.identity.endTimestamp > rhs.identity.endTimestamp
        }
        if lhs.identity.endDate != rhs.identity.endDate {
            return lhs.identity.endDate > rhs.identity.endDate
        }
        return lhs.identity.timezoneMinutes > rhs.identity.timezoneMinutes
    }
}
