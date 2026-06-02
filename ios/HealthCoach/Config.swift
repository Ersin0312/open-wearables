import Foundation

/// App configuration. The base URL points at the FastAPI backend; on a real
/// iPhone this must be reachable (Tailscale IP), in the Simulator localhost works.
enum AppConfig {
    /// Backend base URL.
    /// - Simulator: http://localhost:8000 reaches the Mac's backend directly.
    /// - Real iPhone: use the Mac's Tailscale IP so it works anywhere.
    #if targetEnvironment(simulator)
    static let baseURL = URL(string: "http://localhost:8000")!
    /// Exercise images are served by the frontend container (port 3000).
    static let imageBaseURL = URL(string: "http://localhost:3000")!
    #else
    static let baseURL = URL(string: "http://100.81.255.74:8000")!
    static let imageBaseURL = URL(string: "http://100.81.255.74:3000")!
    #endif

    /// The single user this personal app tracks.
    static let userID = "a81842c6-f72f-4496-9617-00e862d5661d"

    /// Key under which the API key is stored in the Keychain.
    static let apiKeyKeychainAccount = "open-wearables-api-key"
}
