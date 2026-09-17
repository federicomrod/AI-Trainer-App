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

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The server sent back something unexpected."
        case .http(let code):
            return "Server error (HTTP \(code))."
        case .decoding(let error):
            return "Couldn't read the server's response: \(error.localizedDescription)"
        }
    }
}

struct APIClient {
    /// Wherever the backend is actually running. The Simulator shares
    /// this Mac's own network, so a LAN IP here reaches any machine on
    /// the same Wi-Fi -- including this one, or the Mac mini, or
    /// wherever the backend gets deployed next. Update this when that
    /// address changes; it isn't discovered automatically.
    static var baseURL = URL(string: "http://192.168.0.129:8000")!

    private let session = URLSession.shared

    func turn(message: String) async throws -> TurnResponse {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("turn"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["message": message])
        // The model call itself can take a while (gpt-5 does real
        // reasoning before answering) -- give it real room before
        // URLSession times the request out from under it.
        request.timeoutInterval = 60
        return try await send(request, decoding: TurnResponse.self)
    }

    /// The full conversation so far, for Coach chat. Each row's `text`
    /// is already final display text -- see ChatMessage's doc comment.
    func fetchHistory() async throws -> [ChatMessage] {
        let request = URLRequest(url: Self.baseURL.appendingPathComponent("messages"))
        return try await send(request, decoding: [ChatMessage].self)
    }

    /// The current calendar week, for Week view.
    func fetchWeek() async throws -> [WeekDay] {
        let request = URLRequest(url: Self.baseURL.appendingPathComponent("week"))
        return try await send(request, decoding: [WeekDay].self)
    }

    /// Save (or update) today's check-in.
    func submitCheckIn(_ body: CheckInRequest) async throws -> CheckInResponse {
        try await post("checkin", body: body, decoding: CheckInResponse.self)
    }

    /// What the logging screen needs for `date` (nil = today).
    func fetchLogContext(date: String? = nil) async throws -> LogContextResponse {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("log_context"),
            resolvingAgainstBaseURL: false
        )!
        if let date {
            components.queryItems = [URLQueryItem(name: "date", value: date)]
        }
        let request = URLRequest(url: components.url!)
        return try await send(request, decoding: LogContextResponse.self)
    }

    /// Record what actually happened for a session.
    func submitLog(_ body: LogSessionRequest) async throws -> LogSessionResponse {
        try await post("log_session", body: body, decoding: LogSessionResponse.self)
    }

    /// Goals, in priority order (list order = priority).
    func fetchGoals() async throws -> GoalsPayload {
        let request = URLRequest(url: Self.baseURL.appendingPathComponent("goals"))
        return try await send(request, decoding: GoalsPayload.self)
    }

    /// Replace the goals list wholesale, in the given order.
    func saveGoals(_ goals: [String]) async throws -> GoalsPayload {
        try await put("goals", body: GoalsPayload(goals: goals), decoding: GoalsPayload.self)
    }

    /// Real trend data for Progress view: lift weight-over-time series
    /// and weekly completed-session counts.
    func fetchProgress() async throws -> ProgressResponse {
        let request = URLRequest(url: Self.baseURL.appendingPathComponent("progress"))
        return try await send(request, decoding: ProgressResponse.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
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
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, decoding: decoding)
    }
}
