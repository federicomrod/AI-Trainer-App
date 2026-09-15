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
}
