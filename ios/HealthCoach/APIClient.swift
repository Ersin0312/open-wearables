import Foundation

enum APIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Kein API-Key hinterlegt. Bitte in den Einstellungen eintragen."
        case .http(let code, let body): return "Serverfehler \(code): \(body)"
        case .decoding(let m): return "Antwort nicht lesbar: \(m)"
        case .transport(let m): return "Verbindungsfehler: \(m)"
        }
    }
}

/// Thin REST client for the Open Wearables backend. Reuses the existing API —
/// no shared DB, auth via the personal API key in the Keychain.
struct APIClient {
    static let shared = APIClient()

    private var apiKey: String? { Keychain.get(account: AppConfig.apiKeyKeychainAccount) }

    private func makeRequest(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard let key = apiKey, !key.isEmpty else { throw APIError.missingKey }
        var comps = URLComponents(url: AppConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "X-Open-Wearables-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.transport("Keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, bodyText)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Connectivity / users

    func currentUser() async throws -> UserItem? {
        let req = try makeRequest("/api/v1/users", query: [URLQueryItem(name: "limit", value: "1")])
        let resp = try await send(req, as: UsersResponse.self)
        return resp.items.first
    }

    // MARK: - Supplements

    func supplements() async throws -> [Supplement] {
        let req = try makeRequest("/api/v1/supplements", query: [URLQueryItem(name: "user_id", value: AppConfig.userID)])
        return try await send(req, as: [Supplement].self)
    }

    func stacks() async throws -> [SupplementStack] {
        let req = try makeRequest("/api/v1/users/\(AppConfig.userID)/supplement-stacks")
        return try await send(req, as: [SupplementStack].self)
    }

    func intakes(startDate: String? = nil, endDate: String? = nil) async throws -> [SupplementIntake] {
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: "500")]
        if let s = startDate { q.append(URLQueryItem(name: "start_date", value: s)) }
        if let e = endDate { q.append(URLQueryItem(name: "end_date", value: e)) }
        let req = try makeRequest("/api/v1/users/\(AppConfig.userID)/supplement-intakes", query: q)
        return try await send(req, as: [SupplementIntake].self)
    }

    func logStackNow(stackID: String) async throws -> [SupplementIntake] {
        let req = try makeRequest("/api/v1/users/\(AppConfig.userID)/supplement-stacks/\(stackID)/log-now", method: "POST", body: Data("{}".utf8))
        return try await send(req, as: [SupplementIntake].self)
    }

    // MARK: - Supplement writes

    func addIntake(supplementID: String, dose: Double, unit: String) async throws -> SupplementIntake {
        let payload: [String: Any] = [
            "supplement_id": supplementID,
            "dose": dose,
            "unit": unit,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest("/api/v1/users/\(AppConfig.userID)/supplement-intakes", method: "POST", body: body)
        return try await send(req, as: SupplementIntake.self)
    }

    func deleteIntake(intakeID: String) async throws {
        let req = try makeRequest("/api/v1/users/\(AppConfig.userID)/supplement-intakes/\(intakeID)", method: "DELETE")
        _ = try await sendDiscardingResult(req)
    }

    func createStack(name: String, items: [(supplementID: String, dose: Double?, unit: String?)]) async throws -> SupplementStack {
        let itemPayload: [[String: Any]] = items.enumerated().map { idx, it in
            var d: [String: Any] = ["supplement_id": it.supplementID, "order_index": idx]
            if let dose = it.dose { d["dose"] = dose }
            if let unit = it.unit { d["unit"] = unit }
            return d
        }
        let payload: [String: Any] = ["name": name, "items": itemPayload]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest("/api/v1/users/\(AppConfig.userID)/supplement-stacks", method: "POST", body: body)
        return try await send(req, as: SupplementStack.self)
    }

    func createSupplement(name: String, brand: String?, category: String, defaultDose: Double?, defaultUnit: String, recommendedDailyDose: Double?, notes: String?) async throws -> Supplement {
        var payload: [String: Any] = [
            "name": name,
            "category": category,
            "default_unit": defaultUnit,
            "created_by_user_id": AppConfig.userID,
        ]
        if let brand = brand, !brand.isEmpty { payload["brand"] = brand }
        if let d = defaultDose { payload["default_dose"] = d }
        if let r = recommendedDailyDose { payload["recommended_daily_dose"] = r }
        if let n = notes, !n.isEmpty { payload["notes"] = n }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest("/api/v1/supplements", method: "POST", body: body)
        return try await send(req, as: Supplement.self)
    }

    private func sendDiscardingResult(_ req: URLRequest) async throws -> Data {
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("Keine HTTP-Antwort") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
