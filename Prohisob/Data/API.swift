// Tarmoq: https://cabinet.prohisob.com/api/* — sayt bilan bir xil API. Kirish tokeni «Authorization: Bearer» sarlavhasida
// (cookie ishlatilmaydi), egasi tanlagan kabinet — «X-Kabinet». Javob kalitlari snake_case → convertFromSnakeCase.
// Xato bo'lsa server {"error": "..."} qaytaradi — shu matn foydalanuvchiga ko'rsatiladi (APIError.server).
import Foundation
import UIKit

enum APIError: LocalizedError, Equatable {
    case server(String, Int)       // serverning o'zbekcha xabari va HTTP kodi
    case unauthorized              // sessiya tugagan — qayta kirish kerak
    case offline                   // internet yo'q
    case badResponse(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .server(let m, _): return m
        case .unauthorized: return "Sessiya tugadi. Qaytadan kiring."
        case .offline: return "Internet aloqasi yo‘q. Ulanishni tekshirib, qayta urinib ko‘ring."
        case .badResponse(let c): return "Server javob bermadi (\(c)). Birozdan keyin urinib ko‘ring."
        case .decoding: return "Server javobini o‘qib bo‘lmadi. Ilovani yangilang."
        }
    }

    var status: Int {
        switch self {
        case .server(_, let c), .badResponse(let c): return c
        case .unauthorized: return 401
        default: return 0
        }
    }
}

/// Yuklanadigan fayl (chek rasmi yoki PDF)
struct UploadFile: Sendable {
    let data: Data
    let filename: String
    let mime: String
}

final class API: @unchecked Sendable {
    static let shared = API()
    static let base = URL(string: "https://cabinet.prohisob.com")!

    private let lock = NSLock()
    private var _token: String?
    private var _kabinet: Int?
    /// 401 kelganda (token bilan so'ralgan bo'lsa) — Session chiqaradi
    var onUnauthorized: (@Sendable () -> Void)?

    let session: URLSession
    let userAgent: String
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    /// Chek rasmlari xotirada (bir ekran ichida qayta yuklanmasin)
    private let images = NSCache<NSString, NSData>()

    private init() {
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        userAgent = "Prohisob-iOS/\(ver) (\(build); iOS \(UIDevice.current.systemVersion))"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
        session = URLSession(configuration: cfg)
        images.totalCostLimit = 60 << 20
    }

    var token: String? {
        get { lock.lock(); defer { lock.unlock() }; return _token }
        set { lock.lock(); _token = newValue; lock.unlock(); if newValue == nil { images.removeAllObjects() } }
    }

    /// Faqat platforma egasi uchun: qaysi prorab kabineti bilan ishlayapti
    var kabinet: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _kabinet }
        set { lock.lock(); _kabinet = newValue; lock.unlock(); images.removeAllObjects() }
    }

    /// Qurilma nomi serverdagi sessiyalar ro'yxati uchun: «iPhone · iOS 26.0»
    static var deviceName: String {
        "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }

    // MARK: - So'rovlar

    /// "/api/entries" + ["limit": "50", "object_id": nil] → URL (nil va bo'sh qiymatlar tashlanadi)
    static func url(_ path: String, _ query: [String: String?] = [:]) -> URL {
        var c = URLComponents(string: base.absoluteString + path)!
        let items = query.compactMap { k, v -> URLQueryItem? in
            guard let v, !v.isEmpty else { return nil }
            return URLQueryItem(name: k, value: v)
        }.sorted { $0.name < $1.name }
        if !items.isEmpty { c.queryItems = items }
        return c.url!
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try decode(try await send("GET", API.url(path, query)))
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try decode(try await send("POST", API.url(path), json: try encoder.encode(body)))
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try decode(try await send("PUT", API.url(path), json: try encoder.encode(body)))
    }

    /// Javobi kerak bo'lmagan POST (masalan logout)
    func post(_ path: String) async throws {
        _ = try await send("POST", API.url(path), json: Data("{}".utf8))
    }

    func delete(_ path: String) async throws {
        _ = try await send("DELETE", API.url(path))
    }

    /// Chek rasmlari / PDF: POST /api/entries/:id/files (multipart, «files» maydoni, 10 tagacha, 20 MB gacha).
    /// nginx bitta so'rovga 32 MB gacha qabul qiladi — fayllar ~28 MB lik bo'laklarga bo'lib yuboriladi.
    func upload(entryId: Int, files: [UploadFile]) async throws -> UploadResponse {
        var batches: [[UploadFile]] = []
        var cur: [UploadFile] = []
        var size = 0
        for f in files {
            if !cur.isEmpty, size + f.data.count > 28 << 20 || cur.count >= 10 {
                batches.append(cur); cur = []; size = 0
            }
            cur.append(f); size += f.data.count
        }
        if !cur.isEmpty { batches.append(cur) }
        var all: [FileInfo] = []
        for b in batches { all += try await uploadBatch(entryId: entryId, files: b).cheklar ?? [] }
        return UploadResponse(ok: true, cheklar: all)
    }

    private func uploadBatch(entryId: Int, files: [UploadFile]) async throws -> UploadResponse {
        let boundary = "prohisob-" + UUID().uuidString
        var body = Data()
        for f in files {
            let name = f.filename.replacingOccurrences(of: "\"", with: "")
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(name)\"\r\nContent-Type: \(f.mime)\r\n\r\n".utf8))
            body.append(f.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        let data = try await send("POST", API.url("/api/entries/\(entryId)/files"), body: body,
                                  contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
        return try decode(data)
    }

    /// Fayl (chek rasmi) baytlari — xotirada keshlanadi. path: "/api/files/12" yoki "/api/mijoz/files/12"
    func data(_ path: String) async throws -> Data {
        let key = "\(kabinet ?? 0)|\(path)" as NSString
        if let hit = images.object(forKey: key) { return hit as Data }
        let d = try await send("GET", API.url(path), accept: "*/*")
        images.setObject(d as NSData, forKey: key, cost: d.count)
        return d
    }

    /// Excel kabi faylni vaqtinchalik papkaga yuklab olish (ulashish oynasi uchun)
    func download(_ path: String, query: [String: String?] = [:], filename: String) async throws -> URL {
        let d = try await send("GET", API.url(path, query), accept: "*/*", timeout: 120)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("eksport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        try d.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Ichki

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) } catch {
            #if DEBUG
            print("[API] decode \(T.self):", error)
            #endif
            throw APIError.decoding(String(describing: error))
        }
    }

    private func send(_ method: String, _ url: URL, json: Data? = nil, body: Data? = nil, contentType: String? = nil,
                      accept: String = "application/json", timeout: TimeInterval = 30) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(accept, forHTTPHeaderField: "Accept")
        let tok = token
        if let tok { req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization") }
        if let k = kabinet { req.setValue(String(k), forHTTPHeaderField: "X-Kabinet") }
        if let json {
            req.httpBody = json
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                                            .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff]
            if offline.contains(e.code) { throw APIError.offline }
            throw APIError.server(e.localizedDescription, 0)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code) { return data }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        if code == 401, let tok {
            // token eskirgan yoki parol almashgan — sessiya yopiladi (faqat hali joriy token bo'lsa: chiqib, boshqa hisobga
            // kirilgandan keyin kelgan eski so'rov javobi yangi sessiyani yopmasin)
            if tok == token { onUnauthorized?() }
            throw APIError.unauthorized
        }
        if let msg, !msg.isEmpty { throw APIError.server(msg, code) }
        throw APIError.badResponse(code)
    }
}
