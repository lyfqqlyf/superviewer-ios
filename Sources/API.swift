import Foundation

typealias JSONDict = [String: Any]

struct LoginResp: Decodable {
    let ok: Bool
    let device_id: String?
    let hostname: String?
    let error: String?
}

/// HTTP API 封装（会话凭据存于 HTTPCookieStorage.shared, 登录后自动携带）
final class API {
    static let shared = API()
    private(set) var base: URL?

    @discardableResult
    func setBase(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if !t.contains("://") { t = "http://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        guard let u = URL(string: t) else { return nil }
        base = u
        return u
    }

    var wsBase: URL? {
        guard let b = base else { return nil }
        var comps = URLComponents(url: b, resolvingAgainstBaseURL: false)!
        comps.scheme = (b.scheme == "https") ? "wss" : "ws"
        return comps.url
    }

    private func url(_ path: String) -> URL {
        // 手动拼接：appendingPathComponent 会把 "?" 编码成 %3F，带查询参数的接口会 404
        URL(string: base!.absoluteString + "/" + path)!
    }

    private func request(_ path: String, method: String, body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    func login(code: String, done: @escaping (Result<LoginResp, String>) -> Void) {
        URLSession.shared.dataTask(with: request("api/login", method: "POST", body: ["code": code])) {
            data, resp, err in
            if let err = err { done(.failure(err.localizedDescription)); return }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data,
                  let r = try? JSONDecoder().decode(LoginResp.self, from: data) else {
                done(.failure("响应解析失败 (\(status))")); return
            }
            if r.ok { done(.success(r)) }
            else {
                done(.failure(r.error ?? (status == 429 ? "尝试次数过多，请稍后再试" : "验证码错误")))
            }
        }.resume()
    }

    func getJSON(_ path: String, done: @escaping (Result<JSONDict, String>) -> Void) {
        URLSession.shared.dataTask(with: request(path, method: "GET")) { data, resp, err in
            if let err = err { done(.failure(err.localizedDescription)); return }
            guard let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                done(.failure("响应解析失败")); return
            }
            if (resp as? HTTPURLResponse)?.statusCode == 401 {
                done(.failure("unauthorized")); return
            }
            done(.success(obj))
        }.resume()
    }

    func postJSON(_ path: String, body: [String: Any], done: @escaping (Result<JSONDict, String>) -> Void) {
        URLSession.shared.dataTask(with: request(path, method: "POST", body: body)) { data, resp, err in
            if let err = err { done(.failure(err.localizedDescription)); return }
            guard let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                done(.failure("响应解析失败")); return
            }
            if (resp as? HTTPURLResponse)?.statusCode == 401 {
                done(.failure("unauthorized")); return
            }
            done(.success(obj))
        }.resume()
    }

    /// multipart 文件上传
    func upload(path: String, remoteDir: String, fileURL: URL,
                done: @escaping (Result<Bool, String>) -> Void) {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            done(.failure("无法读取文件")); return
        }
        let boundary = "----SVBoundary\(Int(Date().timeIntervalSince1970 * 1000))"
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"path\"\r\n\r\n\(remoteDir)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { done(.failure(err.localizedDescription)); return }
            done(.success((resp as? HTTPURLResponse)?.statusCode == 200))
        }.resume()
    }
}
