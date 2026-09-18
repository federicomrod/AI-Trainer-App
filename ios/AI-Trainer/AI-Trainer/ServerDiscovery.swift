//
//  ServerDiscovery.swift
//  AI-Trainer
//
//  Finds the backend on the local network via Bonjour instead of a
//  hardcoded IP in APIClient.swift -- this Mac's LAN address has gone
//  stale mid-project twice already (it changes silently between
//  networks with no error; requests just hang until timeout). The
//  server advertises itself under "_hybridcoach._tcp" (see
//  server/discovery.py); this browses for exactly that.
//
//  Uses the older NetServiceBrowser/NetService API rather than modern
//  Network.framework's NWBrowser -- tried NWBrowser first, and its
//  NWConnection-based resolve step reliably stalled forever in the
//  Simulator specifically (confirmed via device logs: the browse
//  finds the service fine, but resolving it to a real host/port never
//  reaches .ready or .failed). NetService's resolve(withTimeout:) is
//  the older, more boring API, but it's the one that actually works
//  here, and it still fully supports a hard timeout either way.
//
//  A plain background discovery isn't enough on its own: if the
//  cached/fallback address points at a host that's simply gone (the
//  common case -- the Mac moved networks), connecting to it doesn't
//  fail fast, it hangs until the OS-level connect timeout, which for
//  the app's slower endpoints is up to 60 seconds. AI_TrainerApp.swift
//  calls resolveBaseURL() once at launch, before any screen's own
//  request fires, so a bad cached address gets a couple seconds to
//  prove itself before falling back to a real Bonjour browse -- not a
//  minutes-long hang on the very first screen. APIClient's own
//  retry-on-failure then covers the rarer case of the address going
//  bad *mid-session* (the server restarts at a new IP while the app's
//  already open).

import Foundation

enum ServerDiscovery {
    private static let cacheKey = "backendBaseURL"
    private static let serviceType = "_hybridcoach._tcp."
    private static let serviceDomain = "local."

    /// The last address discovery actually confirmed, if any. Read
    /// once at launch as the fast-path starting point.
    static var cachedURL: URL? {
        UserDefaults.standard.string(forKey: cacheKey).flatMap(URL.init(string:))
    }

    private static func cache(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: cacheKey)
    }

    /// Call once at launch, before any screen makes its own request.
    /// Works down the list of places the backend could be and returns
    /// the first that actually answers, or nil if none do -- nil is
    /// what puts the app into offline/error handling rather than
    /// letting every screen discover the same dead address one slow
    /// timeout at a time.
    ///
    /// Configured address first, deliberately: it's the stated answer
    /// to "where is the backend", and a stale cached address should
    /// never win over it. Each step is individually short, so the
    /// whole chain fails in seconds rather than minutes.
    static func resolveBaseURL() async -> URL? {
        var tried: [URL] = [Config.backendURL, Config.fallbackBackendURL]
        // Last confirmed address, in case the server is somewhere
        // neither hostname covers.
        if let cached = cachedURL, !tried.contains(cached) {
            tried.append(cached)
        }

        for url in tried {
            if await isLiveBackend(url, timeout: Config.reachabilityProbeTimeout) {
                cache(url)
                return url
            }
        }
        return await discover()
    }

    /// Does a *working, current* backend live at this address?
    ///
    /// Deliberately not /health. An older copy of this server left
    /// running on another machine still answers /health with 200 while
    /// failing every request that matters -- and because the probe
    /// passed, the app bound to it and showed "Server error (HTTP 500)"
    /// on every screen instead of moving on to a machine that worked.
    /// So the probe hits a real endpoint and insists on decoding the
    /// real response: a 500, a 404 from a version that predates it, or
    /// anything that isn't this API all correctly fail here and let the
    /// next candidate have a turn.
    ///
    /// Kept independent of APIClient, whose baseURL is the thing being
    /// resolved.
    private static func isLiveBackend(_ url: URL, timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: url.appendingPathComponent("profile"))
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            _ = try JSONDecoder().decode(ProfileResponse.self, from: data)
            return true
        } catch {
            return false
        }
    }

    /// Browses the LAN for the backend and resolves it to a real
    /// http:// URL, caching it on success. Returns nil on timeout or
    /// if nothing answers -- the caller keeps using whatever it had.
    @discardableResult
    static func discover(timeout: TimeInterval = 4.0) async -> URL? {
        let resolver = BonjourResolver()
        guard let url = await resolver.resolve(
            type: serviceType, domain: serviceDomain, timeout: timeout
        ) else {
            return nil
        }
        cache(url)
        return url
    }
}

/// A class, not the enum above, because NetServiceBrowserDelegate/
/// NetServiceDelegate are delegate-callback based (not async-native)
/// and need a real object to receive them. One instance per discover()
/// call -- cheap, and avoids any shared mutable state between calls.
private final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browser: NetServiceBrowser?
    private var resolvingService: NetService?
    private var continuation: CheckedContinuation<URL?, Never>?
    // Keeps self alive for the duration of the async browse/resolve --
    // nothing else holds a strong reference to this resolver once
    // resolve() returns its Task to the caller.
    private var selfRetain: BonjourResolver?

    func resolve(type: String, domain: String, timeout: TimeInterval) async -> URL? {
        selfRetain = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: type, inDomain: domain)

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func finish(_ url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        browser?.stop()
        resolvingService?.stop()
        continuation.resume(returning: url)
        selfRetain = nil
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolvingService = service
        service.delegate = self
        service.resolve(withTimeout: 4.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let data = sender.addresses?.first,
              let host = Self.numericHost(from: data)
        else {
            finish(nil)
            return
        }
        finish(URL(string: "http://\(host):\(sender.port)"))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(nil)
    }

    /// Turns a resolved sockaddr (IPv4 or IPv6, NetService doesn't
    /// distinguish at this layer) into a plain numeric address string
    /// suitable for a URL host.
    private static func numericHost(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer -> String? in
            guard let sockaddrPtr = rawBuffer.bindMemory(to: sockaddr.self).baseAddress else {
                return nil
            }
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddrPtr, socklen_t(data.count),
                &hostBuffer, socklen_t(hostBuffer.count),
                nil, 0, NI_NUMERICHOST
            )
            guard result == 0 else { return nil }
            return String(cString: hostBuffer)
        }
    }
}
