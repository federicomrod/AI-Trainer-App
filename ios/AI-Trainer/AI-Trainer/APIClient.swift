//
//  APIClient.swift
//  AI-Trainer
//
//  Talks to the local Hybrid Coach backend (server/api.py). The phone
//  can't hold API keys, so per CLAUDE.md's tech decisions there has to
//  be a server between it and OpenAI/Anthropic -- this is the client
//  side of that. No auth: single-user local dev server on the same
//  LAN, nothing more yet.

import Foundation

enum APIError: Error, LocalizedError {
    case badResponse
    case http(Int)
    case decoding(Error)
    /// Nothing answered at any address we know about.
    case unreachable(host: String)
    /// Something answered, but not before the deadline. Distinct from
    /// unreachable on purpose: the backend is there, it was just slow,
    /// and retrying is genuinely worth a try.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The server sent back something unexpected."
        case .http(let code):
            return "The coach's server had a problem (error \(code)). Try again."
        case .decoding:
            return "The coach's server replied in a form the app didn't expect."
        case .unreachable(let host):
            return "Can't reach the coach at \(host). It may be asleep, "
                + "or on a different network than this phone."
        case .timedOut:
            return "The coach took too long to answer."
        }
    }
}

struct APIClient {
    /// Where requests actually go. Starts at the configured address
    /// (Config.backendURL -- the one place it's written down) and is
    /// replaced at launch by whichever address ServerDiscovery
    /// confirms is live.
    static var baseURL = Config.backendURL

    /// Own session rather than URLSession.shared so the timeout is a
    /// property of the client itself -- a request that somehow skips
    /// the builders below is still bounded rather than inheriting the
    /// system default of 60 seconds.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Config.requestTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Every request is built through here or `withBody` below, so the
    /// timeout is applied in one place instead of being remembered at
    /// each call site.
    private static func request(
        _ path: String,
        query: [URLQueryItem]? = nil,
        timeout: TimeInterval = Config.requestTimeout
    ) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if let query, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let token = BackendAuth.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// `imageBase64` is an optional screenshot (CLAUDE.md: "send the
    /// image to the model directly" -- no separate vision step or
    /// upload endpoint).
    func turn(message: String, imageBase64: String? = nil) async throws -> TurnResponse {
        // The one request that waits on a real model call, so it gets
        // Config.coachTurnTimeout rather than the ordinary ceiling --
        // still bounded, so the thinking indicator always resolves.
        var request = Self.request("turn", timeout: Config.coachTurnTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TurnRequestBody(message: message, imageBase64: imageBase64)
        )
        return try await send(request, decoding: TurnResponse.self)
    }

    /// The full conversation so far, for Coach chat. Each row's `text`
    /// is already final display text -- see ChatMessage's doc comment.
    func fetchHistory() async throws -> [ChatMessage] {
        let request = Self.request("messages")
        return try await send(request, decoding: [ChatMessage].self)
    }

    /// The current calendar week, for Week view.
    func fetchWeek() async throws -> [WeekDay] {
        let request = Self.request("week")
        return try await send(request, decoding: [WeekDay].self)
    }

    /// Whether this athlete has been set up yet. A nil profile is what
    /// sends the app to onboarding instead of the tabs.
    func fetchProfile() async throws -> ProfileResponse {
        let request = Self.request("profile")
        return try await send(request, decoding: ProfileResponse.self)
    }

    /// First-run setup: profile, plus optionally the usual week.
    func submitOnboarding(_ body: OnboardingRequest) async throws -> OnboardingResponse {
        try await post("onboarding", body: body, decoding: OnboardingResponse.self)
    }

    /// The raw briefing text, with no message and no model call --
    /// developer/debug use only (Settings > Developer). Never shown on
    /// a user-facing screen; see TodayView's whyDetail() for what the
    /// athlete actually sees when they tap "why".
    func fetchBriefingDebug() async throws -> BriefingDebugResponse {
        let request = Self.request("briefing")
        return try await send(request, decoding: BriefingDebugResponse.self)
    }

    /// Everything on record for one calendar day, for Week view's
    /// tap-to-open detail.
    func fetchDay(date: String) async throws -> DayDetailResponse {
        let request = Self.request("day", query: [URLQueryItem(name: "date", value: date)])
        return try await send(request, decoding: DayDetailResponse.self)
    }

    /// Save (or update) today's check-in.
    func submitCheckIn(_ body: CheckInRequest) async throws -> CheckInResponse {
        try await post("checkin", body: body, decoding: CheckInResponse.self)
    }

    /// What the logging screen needs for `date` (nil = today).
    func fetchLogContext(date: String? = nil) async throws -> LogContextResponse {
        let request = Self.request(
            "log_context",
            query: date.map { [URLQueryItem(name: "date", value: $0)] }
        )
        return try await send(request, decoding: LogContextResponse.self)
    }

    /// Record what actually happened for a session.
    func submitLog(_ body: LogSessionRequest) async throws -> LogSessionResponse {
        try await post("log_session", body: body, decoding: LogSessionResponse.self)
    }

    /// Goals, in priority order (list order = priority).
    func fetchGoals() async throws -> GoalsPayload {
        let request = Self.request("goals")
        return try await send(request, decoding: GoalsPayload.self)
    }

    /// Replace the goals list wholesale, in the given order.
    func saveGoals(_ goals: [String]) async throws -> GoalsPayload {
        try await put("goals", body: GoalsPayload(goals: goals), decoding: GoalsPayload.self)
    }

    /// Real trend data for Progress view: lift weight-over-time series
    /// and weekly completed-session counts.
    func fetchProgress() async throws -> ProgressResponse {
        let request = Self.request("progress")
        return try await send(request, decoding: ProgressResponse.self)
    }

    /// Hand recent HealthKit workouts to the server. Only fills days
    /// with no session at all -- see server/healthkit_import.py.
    func importHealthKitWorkouts(_ workouts: [HealthKitWorkout]) async throws -> HealthKitImportResponse {
        try await post(
            "healthkit_import",
            body: HealthKitImportRequest(workouts: workouts),
            decoding: HealthKitImportResponse.self
        )
    }

    /// On a connection failure, tries one fresh Bonjour discovery and
    /// retries once against whatever it finds -- this is what makes a
    /// mid-session address change (the Mac moved networks, the server
    /// restarted at a new IP) self-heal instead of hanging until
    /// someone notices and edits baseURL by hand.
    private func send<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
        do {
            let value = try await perform(request, decoding: type)
            await ConnectionState.shared.markOnline(Self.baseURL)
            return value
        } catch let error as URLError where error.code == .timedOut {
            // Reached something, it just didn't answer in time. Not an
            // offline condition -- don't send the whole app into the
            // offline path over one slow reply.
            throw APIError.timedOut
        } catch let error as URLError where Self.isConnectivityError(error) {
            if let rediscovered = await ServerDiscovery.discover(),
               rediscovered != Self.baseURL {
                Self.baseURL = rediscovered
                do {
                    let value = try await perform(
                        Self.rebase(request, to: rediscovered), decoding: type
                    )
                    await ConnectionState.shared.markOnline(rediscovered)
                    return value
                } catch {
                    await ConnectionState.shared.markOffline()
                    throw APIError.unreachable(host: Self.hostLabel)
                }
            }
            await ConnectionState.shared.markOffline()
            throw APIError.unreachable(host: Self.hostLabel)
        }
    }

    /// The address to name in an error, without the scheme/port noise.
    private static var hostLabel: String {
        baseURL.host ?? baseURL.absoluteString
    }

    private func perform<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private static func isConnectivityError(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .timedOut, .networkConnectionLost,
             .cannotFindHost, .notConnectedToInternet,
             // A .local hostname that mDNS can't resolve surfaces here
             // -- the mini being asleep looks exactly like this.
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// Re-points a request at a new base URL, keeping its path, query,
    /// method, headers, and body exactly as they were.
    private static func rebase(_ request: URLRequest, to newBase: URL) -> URLRequest {
        guard let oldURL = request.url,
              var components = URLComponents(url: oldURL, resolvingAgainstBaseURL: false),
              let baseComponents = URLComponents(url: newBase, resolvingAgainstBaseURL: false)
        else { return request }
        components.scheme = baseComponents.scheme
        components.host = baseComponents.host
        components.port = baseComponents.port
        var rebased = request
        rebased.url = components.url
        return rebased
    }

    /// Shared helper for the POST-with-JSON-body endpoints (check-in,
    /// post-workout logging).
    func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, decoding: Response.Type
    ) async throws -> Response {
        try await withBody("POST", path, body: body, decoding: decoding)
    }

    /// Shared helper for PUT-with-JSON-body endpoints (goals: replace
    /// the whole list, not a partial update).
    func put<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, decoding: Response.Type
    ) async throws -> Response {
        try await withBody("PUT", path, body: body, decoding: decoding)
    }

    private func withBody<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, body: Body, decoding: Response.Type
    ) async throws -> Response {
        var request = Self.request(path)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, decoding: decoding)
    }
}
