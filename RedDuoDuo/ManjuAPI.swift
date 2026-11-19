import Security
import Foundation
import CryptoKit
import CommonCrypto
import Compression

// MARK: - 身份

struct Identity: Codable {
    let deviceID: String
    let iid: String
    let cdid: String
    let openudid: String
    let clientudid: String
    let ttreq: String
    let registeredAt: Double

    var age: Double { Date().timeIntervalSince1970 - registeredAt }

    enum CodingKeys: String, CodingKey {
        case deviceID, iid, cdid, openudid, clientudid, ttreq, registeredAt
    }

    init(deviceID: String, iid: String, cdid: String, openudid: String, clientudid: String, ttreq: String, registeredAt: Double) {
        self.deviceID = deviceID
        self.iid = iid
        self.cdid = cdid
        self.openudid = openudid
        self.clientudid = clientudid
        self.ttreq = ttreq
        self.registeredAt = registeredAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        iid = try c.decode(String.self, forKey: .iid)
        cdid = try c.decode(String.self, forKey: .cdid)
        openudid = try c.decode(String.self, forKey: .openudid)
        clientudid = try c.decode(String.self, forKey: .clientudid)
        ttreq = try c.decodeIfPresent(String.self, forKey: .ttreq) ?? ""
        registeredAt = try c.decode(Double.self, forKey: .registeredAt)
    }
}

enum ManjuError: LocalizedError {
    case registerFailed(String)
    case emptyResponse(String)
    case noMainURL(String)
    case badHTTP(Int, String)
    case decoding(String)
    case passportError(code: Int, message: String, raw: String)
    case sessionExpired(String)

    var errorDescription: String? {
        switch self {
        case .registerFailed(let s): return "设备注册失败：\(s)"
        case .emptyResponse(let s): return "接口返回空包：\(s)"
        case .noMainURL(let s): return "没有解析到 main_url：\(s)"
        // 脱敏：原始响应体可能含凭据/个人信息，只保留状态码（raw 仅存于内存错误对象，不落盘、不展示）。
        case .badHTTP(let code, _): return "HTTP \(code)（响应体已省略）"
        case .decoding(let s): return "解析失败：\(s)"
        case .passportError(let code, let msg, _):
            return code != 0 ? "[\(code)] \(msg)" : msg
        case .sessionExpired(let s): return "登录状态已失效：\(s)"
        }
    }
}

// MARK: - 红果漫剧 API（aid=8704 / com.kylin.read / 7.2.7.32）

actor ManjuAPI {
    static let shared = ManjuAPI()

    private let base = "https://api5-normal-sinfonlinea.fqnovel.com"
    private let lqBase = "https://api5-normal-lq.fqnovel.com"
    private let passportOrigin = "https://security.snssdk.com"
    private let registerURL = "https://ib.snssdk.com/service/2/device_register/"
    private let ua = "Dalvik/2.1.0 (Linux; U; Android 13; Pixel 5 Build/TQ3A.230805.001) Kylin/7.2.7.32"
    private let formContentType = "application/x-www-form-urlencoded; charset=UTF-8"
    private let realUpsmsChannel = "10691859839103"
    private let stubUpsmsChannel = "9515211003"
    private let identityKey = "redduoduo.identity.v1"

    private let coldStartSessionID = UUID().uuidString.lowercased()
    private let normalSessionID = "\(UUID().uuidString.lowercased())#160"

    private var identity: Identity?
    private var authSession: AuthSession?
    private var consecutiveRegistrations = 0

    /// 跨域名显式管理 Cookie，禁用 URLSession 自动 CookieJar，避免 .snssdk.com 与 .fqnovel.com 隔离。
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 40
        cfg.waitsForConnectivity = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
        return URLSession(configuration: cfg)
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: identityKey),
           let saved = try? JSONDecoder().decode(Identity.self, from: data) {
            identity = saved
            AppLog.write("IDENTITY loaded persistent did=\(saved.deviceID.isEmpty ? 0 : 1) iid=\(saved.iid.isEmpty ? 0 : 1) ttreq=\(saved.ttreq.isEmpty ? 0 : 1) age=\(String(format: "%.0f", saved.age))s")
        }
        if let savedSess = SessionKeychain.load(), !savedSess.isExpired, savedSess.hasSessionCookie {
            authSession = savedSess
            AppLog.write("SESSION loaded cookies=\(savedSess.cookies.count)")
        }
    }

    func updateSession(_ newSession: AuthSession?) {
        authSession = newSession
    }

    func currentIdentity() -> Identity? {
        identity
    }

    // MARK: 身份注册（首次注册后长期固定复用；废除 330s 轮换；已登录态绝对锁定）

    func ensureIdentity(forceNew: Bool = false) async throws -> Identity {
        // 已登录状态绝对锁定同一设备身份，禁止任何重注册换号
        if let active = authSession, active.hasSessionCookie, !active.isExpired, let current = identity {
            return current
        }
        if !forceNew, let current = identity {
            return current
        }
        if consecutiveRegistrations >= 3 {
            throw ManjuError.registerFailed("连续 3 次注册均未成功")
        }
        consecutiveRegistrations += 1
        let reason = identity == nil ? "initial" : "guest_recovery"
        AppLog.write("IDENTITY register attempt=\(consecutiveRegistrations) reason=\(reason)")
        let fresh = try await registerDevice()
        identity = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: identityKey)
        }
        consecutiveRegistrations = 0
        Task { @MainActor in
            await AuthStore.shared.refreshDeviceID()
        }
        return fresh
    }

    private func registerDevice() async throws -> Identity {
        let cdid = UUID().uuidString.lowercased()
        let openudid = Self.randomHex(8)
        let clientudid = UUID().uuidString.lowercased()
        let seedDid = Self.randomDigits(19)
        let seedIid = Self.randomDigits(19)

        let header: [String: Any] = [
            "aid": 8704, "app_version": "7.2.7.32", "version_code": 72732,
            "package": "com.kylin.read", "channel": "channel_not_set",
            "os": "Android", "os_api": 33, "device_model": "Pixel 5", "device_brand": "google",
            "device_manufacturer": "Google", "cdid": cdid, "openudid": openudid,
            "clientudid": clientudid, "device_platform": "android", "guest_mode": 0,
            "app_language": "zh", "app_region": "CN", "resolution": "2340x1080", "dpi": 420,
            "language": "zh", "region": "CN", "timezone": 8, "tz_name": "Asia/Shanghai",
            "sdk_version": "3.9.5", "sdk_target_version": 33, "os_version": "13",
            "cpu_abi": "arm64-v8a", "release_build": "TQ3A.230805.001",
            "density_dpi": 420, "display_density": "xxhdpi", "google_aid": "",
            "req_id": UUID().uuidString.lowercased(),
        ]
        let bodyObj: [String: Any] = [
            "magic_tag": "ss_app_log", "header": header,
            "_gen_time": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let body = try JSONSerialization.data(withJSONObject: bodyObj, options: [.sortedKeys])

        let pairs: [(String, String)] = [
            ("aid", "8704"), ("app_name", "kylin_read"), ("version_code", "72732"),
            ("version_name", "7.2.7.32"), ("device_platform", "android"), ("os", "android"),
            ("ssmix", "a"), ("language", "zh"), ("channel", "channel_not_set"),
            ("device_type", "Pixel 5"), ("device_brand", "google"), ("resolution", "1080*2340"),
            ("dpi", "420"), ("host_abi", "arm64-v8a"), ("manifest_version_code", "72732"),
            ("update_version_code", "72732"), ("ac", "wifi"), ("app_type", "normal"),
            ("cpu_support64", "true"), ("device_id", seedDid), ("iid", seedIid),
            ("cdid", cdid), ("openudid", openudid),
        ]
        let url = try makeURL(path: registerURL, absolute: true, pairs: pairs)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        let httpResp = response as? HTTPURLResponse
        let status = httpResp?.statusCode ?? 0
        AppLog.write("IDENTITY register HTTP status=\(status) bytes=\(data.count)")
        guard status == 200, !data.isEmpty else {
            throw ManjuError.registerFailed("HTTP \(status) / \(data.count)B")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManjuError.decoding("device_register 响应不是 JSON")
        }
        let did = JSONValue.string(json["device_id_str"]) ?? JSONValue.string(json["device_id"]) ?? "0"
        let iid = JSONValue.string(json["install_id_str"]) ?? JSONValue.string(json["install_id"]) ?? "0"
        guard did != "0", iid != "0", !did.isEmpty, !iid.isEmpty else {
            throw ManjuError.registerFailed("服务端返回 device_id=0")
        }
        let regCookies = httpResp.map { Self.parseSetCookiePairs(from: $0, url: url) } ?? [:]
        let ttreq = regCookies["ttreq"] ?? ""
        let fresh = Identity(deviceID: did, iid: iid, cdid: cdid, openudid: openudid,
                             clientudid: clientudid, ttreq: ttreq, registeredAt: Date().timeIntervalSince1970)
        AppLog.write("IDENTITY registered persistent did_len=\(did.count) iid_len=\(iid.count) cdid_len=\(cdid.count) ttreq_len=\(ttreq.count)")
        return fresh
    }

    // MARK: - 账号登录（Passport security.snssdk.com + HGCurrentPlayer 签名）

    func sendSMSCode(mobile rawMobile: String) async throws -> SendCodeResult {
        let mobile = Self.normalizeMobile(rawMobile)
        guard !mobile.isEmpty else {
            throw ManjuError.passportError(code: -1, message: "请输入手机号", raw: "")
        }
        let id = try await ensureIdentity()
        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let path = "/passport/mobile/send_code/v1/"
        let formPairs = passportDeviceForm(id, nowMS: nowMS) + [
            ("mobile", Self.xor05Hex("+86" + mobile)),
            ("mix_mode", "1"),
            ("account_sdk_source", "app"),
            ("passport_support_flow", "captcha,verify"),
            ("type", "3731"),
            ("auto_read", "0"),
            ("unbind_exist", "34"),
        ]
        var cookies: [String: String] = [:]
        if !id.ttreq.isEmpty { cookies["ttreq"] = id.ttreq }
        if !id.iid.isEmpty { cookies["install_id"] = id.iid }

        let (request, queryLen) = try buildSignedPassportRequest(
            path: path,
            queryPairs: passportSdkQuery(withRom: true),
            formPairs: formPairs,
            cookies: cookies,
            identity: id,
            nowMS: nowMS
        )

        AppLog.write("PASSPORT send_code REQ path=\(request.url?.path ?? "") did=\(id.deviceID.isEmpty ? 0 : 1) iid=\(id.iid.isEmpty ? 0 : 1) mobile_len=\(mobile.count) query_len=\(queryLen) form_bytes=\(request.httpBody?.count ?? 0) content_type=\(request.value(forHTTPHeaderField: "Content-Type") ?? "-")")

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, let url = request.url else {
            throw ManjuError.emptyResponse("send_code")
        }
        let status = httpResp.statusCode
        let logid = httpResp.value(forHTTPHeaderField: "X-Tt-Logid") ?? "-"
        let rawText = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
        let respCookies = Self.parseSetCookiePairs(from: httpResp, url: url)
        // 脱敏：不记录原始响应体与任何 Cookie 值，只留状态码、logid、Cookie 名与字节数。
        AppLog.write("PASSPORT send_code RESP status=\(status) logid=\(logid) cookie_names=\(respCookies.keys.sorted().joined(separator: ",")) body_bytes=\(data.count)")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManjuError.badHTTP(status, rawText)
        }

        let inner = json["data"] as? [String: Any] ?? [:]
        let errCode = JSONValue.int(inner["error_code"]) ?? JSONValue.int(json["error_code"]) ?? 0
        let msgStr = JSONValue.string(json["message"]) ?? ""
        if errCode != 0 || (msgStr != "success" && !msgStr.isEmpty) {
            let desc = JSONValue.string(inner["description"])
                ?? JSONValue.string(inner["message"])
                ?? (msgStr.isEmpty ? "发送验证码失败" : msgStr)
            throw ManjuError.passportError(code: errCode, message: desc, raw: rawText)
        }

        let csrf = respCookies["passport_csrf_token"] ?? ""
        let ticket = JSONValue.string(inner["mobile_ticket"]) ?? ""
        let retry = JSONValue.int(inner["retry_time"]) ?? 60
        return SendCodeResult(message: msgStr, mobileTicket: ticket, retryTime: max(retry, 15),
                              csrfToken: csrf, rawResponse: rawText)
    }

    func smsLogin(mobile rawMobile: String, code: String, csrfToken: String,
                  mfaToken: String? = nil, mfaRetryTag: String? = nil, smsCodeKey: String? = nil) async throws -> LoginOutcome {
        let mobile = Self.normalizeMobile(rawMobile)
        let id = try await ensureIdentity()
        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let path = "/passport/mobile/sms_login/"

        var formPairs = passportDeviceForm(id, nowMS: nowMS) + [
            ("mobile", Self.xor05Hex("+86" + mobile)),
            ("mix_mode", "1"),
            ("code", Self.xor05Hex(code.trimmingCharacters(in: .whitespacesAndNewlines))),
            ("account_sdk_source", "app"),
            ("passport_support_flow", "captcha,verify"),
        ]
        if let tag = mfaRetryTag, !tag.isEmpty, let key = smsCodeKey, !key.isEmpty {
            formPairs.append(("passport_mfa_retry_tag", tag))
            formPairs.append(("sms_code_key", Self.xor05Hex(key)))
        }

        var cookies: [String: String] = [:]
        if !id.ttreq.isEmpty { cookies["ttreq"] = id.ttreq }
        if !id.iid.isEmpty { cookies["install_id"] = id.iid }
        if !csrfToken.isEmpty { cookies["passport_csrf_token"] = csrfToken }
        if let mfaToken, !mfaToken.isEmpty { cookies["passport_mfa_token"] = mfaToken }

        let (request, _) = try buildSignedPassportRequest(
            path: path,
            queryPairs: passportSdkQuery(withRom: true),
            formPairs: formPairs,
            cookies: cookies,
            identity: id,
            nowMS: nowMS
        )

        AppLog.write("PASSPORT sms_login REQ did=\(id.deviceID.isEmpty ? 0 : 1) has_csrf=\(!csrfToken.isEmpty) has_mfa=\(!(mfaToken ?? "").isEmpty) retry=\(!(mfaRetryTag ?? "").isEmpty)")
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, let url = request.url else {
            throw ManjuError.emptyResponse("sms_login")
        }
        let status = httpResp.statusCode
        let logid = httpResp.value(forHTTPHeaderField: "X-Tt-Logid") ?? "-"
        let rawText = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
        let respCookies = Self.parseSetCookiePairs(from: httpResp, url: url)
        AppLog.write("PASSPORT sms_login RESP status=\(status) logid=\(logid) cookie_names=\(respCookies.keys.sorted().joined(separator: ","))")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManjuError.badHTTP(status, rawText)
        }

        let inner = json["data"] as? [String: Any] ?? [:]
        let bizParams = (inner["biz_params"] as? [String: Any]) ?? json
        let errCode = JSONValue.int(inner["error_code"]) ?? JSONValue.int(json["error_code"]) ?? 0

        if let retryTag = JSONValue.string(bizParams["passport_mfa_retry_tag"]),
           let codeKey = JSONValue.string(bizParams["sms_code_key"]),
           !retryTag.isEmpty, !codeKey.isEmpty {
            let ways = inner["verify_ways"] as? [[String: Any]] ?? []
            let upWay = ways.first { JSONValue.string($0["verify_way"]) == "mobile_up_sms_verify" } ?? ways.first ?? [:]
            let rawCh = JSONValue.string(upWay["channel_mobile"]) ?? ""
            let channel = (rawCh.isEmpty || rawCh == stubUpsmsChannel) ? realUpsmsChannel : rawCh
            let smsContent = JSONValue.string(upWay["sms_content"]) ?? ""
            let eventParams = inner["event_params"] as? [String: Any] ?? [:]
            let commonParams = inner["common_params"] as? [String: Any] ?? [:]
            let tips = JSONValue.string(inner["verify_scene_desc"])
                ?? JSONValue.string(inner["description"])
                ?? JSONValue.string(json["message"])
                ?? "当前设备需要短信上行验证"

            let mfa = MfaContext(
                retryTag: retryTag,
                smsCodeKey: codeKey,
                encryptUid: JSONValue.string(inner["encrypt_uid"]) ?? "",
                logId: JSONValue.string(eventParams["log_id"]) ?? "",
                verifyReason: JSONValue.string(eventParams["verify_reason"]) ?? "ato",
                verifyScene: JSONValue.string(eventParams["verify_scene"]) ?? "sms_login",
                copywritingKey: JSONValue.string(commonParams["copywriting_key"]) ?? "sms_login",
                diversionTag: JSONValue.string(commonParams["ies_safety_diversion_tag"]) ?? "mfa",
                channelMobile: channel,
                smsContent: smsContent,
                tips: tips,
                mfaToken: respCookies["passport_mfa_token"] ?? (mfaToken ?? "")
            )
            // 脱敏：channel/raw_ch 是上行短信接收号码（手机号形态），不落盘。
            AppLog.write("PASSPORT sms_login MFA 2046 has_channel=\(!channel.isEmpty) has_mfa_token=\(!mfa.mfaToken.isEmpty)")
            return .mfa(mfa)
        }

        if errCode != 0 {
            let desc = JSONValue.string(inner["description"])
                ?? JSONValue.string(inner["message"])
                ?? JSONValue.string(json["message"])
                ?? "登录失败"
            throw ManjuError.passportError(code: errCode, message: desc, raw: rawText)
        }

        var mergedCookies = cookies
        for (k, v) in respCookies where !v.isEmpty {
            mergedCookies[k] = v
        }
        // 不把临时 csrf 留作障碍，保留全部服务端下发的正式会话 Cookie
        guard !(mergedCookies["sessionid"] ?? "").isEmpty || !(mergedCookies["sid_tt"] ?? "").isEmpty else {
            let desc = JSONValue.string(inner["description"]) ?? JSONValue.string(json["message"]) ?? "登录成功但未返回 sessionid"
            throw ManjuError.passportError(code: errCode, message: desc, raw: rawText)
        }

        let xTTToken = httpResp.value(forHTTPHeaderField: "x-tt-token") ?? ""
        let user = Self.parsePassportUser(json: json, fallbackMobile: mobile)
        let expiresAt = Self.parseSidGuardExpiry(mergedCookies["sid_guard"])

        let newSession = AuthSession(
            user: user,
            cookies: mergedCookies,
            xTTToken: xTTToken,
            loggedInAt: Date().timeIntervalSince1970,
            expiresAt: expiresAt
        )
        return .success(newSession)
    }

    func upsmsVerify(mfa: MfaContext) async throws -> UpsmsPollResult {
        let id = try await ensureIdentity()
        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let path = "/passport/upsms/verify/"

        let bizObj: [String: String] = [
            "passport_mfa_retry_tag": mfa.retryTag,
            "sms_code_key": mfa.smsCodeKey,
        ]
        let bizData = try JSONSerialization.data(withJSONObject: bizObj, options: [.sortedKeys])
        let bizStr = String(data: bizData, encoding: .utf8) ?? "{}"

        let formPairs: [(String, String)] = [
            // 身份字段：与发码/登录同套。hongguoTV 真号实测的 upsms/verify body 也带这三项。
            ("aid", "8704"),
            ("app_name", "kylin_read"),
            ("device_platform", "android"),
            ("biz_params", bizStr),
            ("copywriting_key", mfa.copywritingKey.isEmpty ? "sms_login" : mfa.copywritingKey),
            ("encrypt_uid", mfa.encryptUid),
            ("ies_safety_diversion_tag", mfa.diversionTag.isEmpty ? "mfa" : mfa.diversionTag),
            ("new_authn_sdk_log_id", mfa.logId),
            ("new_authn_sdk_verify_reason", mfa.verifyReason.isEmpty ? "ato" : mfa.verifyReason),
            ("new_authn_sdk_verify_scene", mfa.verifyScene.isEmpty ? "sms_login" : mfa.verifyScene),
            ("new_authn_sdk_version", "1.1.31"),
            ("request_tag_from", "h5"),
            ("verify_reason", mfa.verifyReason.isEmpty ? "ato" : mfa.verifyReason),
            ("verify_scene", mfa.verifyScene.isEmpty ? "sms_login" : mfa.verifyScene),
            ("new_verify_flow", ""),
            ("verify_ticket", ""),
        ]

        var cookies: [String: String] = [:]
        if !mfa.mfaToken.isEmpty { cookies["passport_mfa_token"] = mfa.mfaToken }

        let (request, _) = try buildSignedPassportRequest(
            path: path,
            queryPairs: passportSdkQuery(withRom: false),
            formPairs: formPairs,
            cookies: cookies,
            identity: id,
            nowMS: nowMS
        )

        AppLog.write("PASSPORT upsms/verify REQ did=\(id.deviceID.isEmpty ? 0 : 1) iid=\(id.iid.isEmpty ? 0 : 1) has_mfa=\(!mfa.mfaToken.isEmpty) query_len=\(request.url?.absoluteString.count ?? 0) form_bytes=\(request.httpBody?.count ?? 0)")
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, let url = request.url else {
            throw ManjuError.emptyResponse("upsms/verify")
        }
        let rawText = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
        let respCookies = Self.parseSetCookiePairs(from: httpResp, url: url)
        // 脱敏：不记录原始响应体与任何 Cookie 值。
        AppLog.write("PASSPORT upsms/verify RESP status=\(httpResp.statusCode) cookie_names=\(respCookies.keys.sorted().joined(separator: ",")) body_bytes=\(data.count)")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManjuError.badHTTP(httpResp.statusCode, rawText)
        }
        let inner = json["data"] as? [String: Any] ?? [:]
        let errCode = JSONValue.int(inner["error_code"]) ?? JSONValue.int(json["error_code"]) ?? 0
        if errCode == 1045 {
            return .waiting
        }
        if errCode != 0 {
            let desc = JSONValue.string(inner["description"])
                ?? JSONValue.string(inner["message"])
                ?? JSONValue.string(json["message"])
                ?? "上行短信校验失败"
            throw ManjuError.passportError(code: errCode, message: desc, raw: rawText)
        }
        let registered = JSONValue.bool(inner["registered"]) ?? false
        if registered {
            let nextToken = respCookies["passport_mfa_token"] ?? mfa.mfaToken
            return .registered(newMfaToken: nextToken)
        }
        return .waiting
    }

    // MARK: - 登录后收益端点（user/info, read_history, bookshelf）

    func fetchUserInfo() async throws -> PassportUser {
        let id = try await ensureIdentity()
        let path = "/reading/user/info/v1/"
        let (data, status) = try await requestReadingGET(path: path, extraQuery: [], identity: id)
        guard status == 200, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if status == 401 { throw ManjuError.sessionExpired("HTTP 401") }
            throw ManjuError.emptyResponse("user/info")
        }
        try checkBusinessSessionValidity(json: json)
        return Self.parsePassportUser(json: json, fallbackMobile: authSession?.user.mobile ?? "")
    }

    func fetchCloudHistory() async throws -> [CloudHistoryItem] {
        let id = try await ensureIdentity()
        let q: [(String, String)] = [
            ("book_type", "2"),
            ("full_field", "false"),
            ("is_first_load", "true"),
            ("last_min_read_timestamp_ms", "0"),
            ("limit", "0"),
            ("offset", "0"),
            ("query_soft_deleted", "false"),
        ]
        let (data, status) = try await requestReadingGET(path: "/reading/bookapi/read_history/list/v", extraQuery: q, identity: id)
        guard status == 200, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if status == 401 { throw ManjuError.sessionExpired("HTTP 401") }
            throw ManjuError.emptyResponse("云端观看记录")
        }
        try checkBusinessSessionValidity(json: json)
        let inner = json["data"] as? [String: Any] ?? [:]
        let list = inner["data_list"] as? [[String: Any]] ?? []
        var items: [CloudHistoryItem] = []
        for raw in list {
            let sid = JSONValue.string(raw["book_id_str"]) ?? JSONValue.string(raw["book_id"]) ?? ""
            guard !sid.isEmpty else { continue }
            let title = JSONValue.string(raw["book_name"]) ?? ""
            let cover = JSONValue.string(raw["thumb_url"]) ?? ""
            // 服务端 0 基 -> UI 1 基
            let epIdx = max(0, JSONValue.int(raw["vid_index"]) ?? 0) + 1
            let vid = JSONValue.string(raw["vid_str"]) ?? JSONValue.string(raw["vid"]) ?? ""
            let posMS = Double(JSONValue.int(raw["current_play_position"]) ?? 0)
            let durMS = Double(JSONValue.int(raw["duration"]) ?? 0)
            let epCnt = JSONValue.int(raw["episode_cnt"]) ?? 0
            let tsMS = Double(JSONValue.int(raw["read_timestamp_ms"]) ?? 0)
            items.append(CloudHistoryItem(
                seriesID: sid,
                title: title,
                cover: cover,
                episodeIndex: epIdx,
                vid: vid,
                positionSeconds: posMS / 1000.0,
                durationSeconds: durMS / 1000.0,
                episodeCount: epCnt,
                updatedAt: tsMS > 1_000_000_000_000 ? tsMS / 1000.0 : tsMS
            ))
        }
        AppLog.write("CLOUD_HISTORY count=\(items.count)")
        return items
    }

    func fetchBookshelf(uid: String) async throws -> [BookshelfItem] {
        guard !uid.isEmpty else { return [] }
        let id = try await ensureIdentity()
        let q: [(String, String)] = [("target_user_id", uid)]
        let (data, status) = try await requestReadingGET(path: "/reading/bookapi/bookshelf/video/list/v", extraQuery: q, identity: id)
        guard status == 200, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if status == 401 { throw ManjuError.sessionExpired("HTTP 401") }
            throw ManjuError.emptyResponse("收藏书架")
        }
        try checkBusinessSessionValidity(json: json)
        let inner = json["data"] as? [String: Any] ?? [:]
        let list = inner["video_shelf_info"] as? [[String: Any]] ?? []
        var items: [BookshelfItem] = []
        for raw in list {
            let sid = JSONValue.string(raw["series_id"])
                ?? JSONValue.string(raw["book_id"])
                ?? JSONValue.string(raw["item_id"])
                ?? ""
            guard !sid.isEmpty else { continue }
            let title = JSONValue.string(raw["series_title"])
                ?? JSONValue.string(raw["book_name"])
                ?? JSONValue.string(raw["title"])
                ?? ""
            let cover = JSONValue.string(raw["series_cover"])
                ?? JSONValue.string(raw["thumb_url"])
                ?? JSONValue.string(raw["cover"])
                ?? ""
            let epCount = JSONValue.int(raw["episode_cnt"]) ?? JSONValue.int(raw["episode_count"]) ?? 0
            let rawTs = Double(JSONValue.int(raw["collect_time_ms"])
                ?? JSONValue.int(raw["collect_time"])
                ?? JSONValue.int(raw["create_time"])
                ?? 0)
            let ts = rawTs > 1_000_000_000_000 ? rawTs / 1000.0 : rawTs
            items.append(BookshelfItem(seriesID: sid, title: title, cover: cover, episodeCount: epCount, collectTime: ts))
        }
        AppLog.write("CLOUD_BOOKSHELF count=\(items.count)")
        return items
    }

    func collectSeries(seriesID: String, collect: Bool) async throws {
        guard let sess = authSession, sess.hasSessionCookie, !sess.isExpired else {
            throw ManjuError.sessionExpired("请先登录账号")
        }
        let id = try await ensureIdentity()
        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let payload: [String: Any] = [
            "is_cancelled": false,
            "shark_extra": [
                "enter_from": "MainFragmentActivity",
                "inactive_type": "0",
                "is_active_behavior": "true",
                "page_list": "MainFragmentActivity",
                "previous_page": "",
            ],
            "update_bookshelf_video_list": [[
                "book_id": seriesID,
                "book_type": 2,
                "modify_time": nowMS,
                "video_shelf_operate_type": collect ? 0 : 1,
            ] as [String: Any]],
        ]
        let rawBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let (data, status) = try await requestReadingGzipPOST(path: "/reading/bookapi/bookshelf/video/update/v", rawJSON: rawBody, identity: id)
        guard status == 200, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManjuError.emptyResponse("收藏操作")
        }
        try checkBusinessSessionValidity(json: json)
        if let code = JSONValue.int(json["code"]), code != 0 {
            let msg = JSONValue.string(json["message"]) ?? "收藏操作失败"
            throw ManjuError.badHTTP(code, msg)
        }
        AppLog.write("CLOUD_BOOKSHELF update series=\(seriesID) collect=\(collect) ok")
    }

    func reportWatchProgress(seriesID: String, vid: String, episodeIndex: Int, positionSeconds: Double) async {
        guard let sess = authSession, sess.hasSessionCookie, !sess.isExpired else { return }
        guard let id = try? await ensureIdentity() else { return }
        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let posMS = Int64(max(0, positionSeconds) * 1000)
        let wireIndex = max(0, episodeIndex - 1)
        let bookIDVal: Any = Int64(seriesID) ?? seriesID as Any
        let vidVal: Any = Int64(vid) ?? vid as Any

        let updateBody: [String: Any] = [
            "update_datas": [[
                "book_id": bookIDVal,
                "book_type": 2,
                "chapter_index": 0,
                "current_play_position": posMS,
                "digged_count": 0,
                "duration": 0,
                "episode_cnt": 0,
                "is_delete": false,
                "is_interactive_game": false,
                "is_listen_mode": false,
                "is_multi_season": 0,
                "meet_guide_comment_tag": false,
                "origin_novel_book_id": 0,
                "player_accumulate_total_time": posMS,
                "read_timestamp_ms": nowMS,
                "recent_reads": 0,
                "retain_video_play_time": 0,
                "season_index": 0,
                "series_play_cnt": 0,
                "tone_id": 0,
                "update_timestamp_ms": nowMS,
                "use_soft_delete": false,
                "user_digg": false,
                "user_playlet_comment_flag": false,
                "vid": vidVal,
                "vid_index": wireIndex,
            ] as [String: Any]]
        ]
        if let raw = try? JSONSerialization.data(withJSONObject: updateBody, options: [.sortedKeys]) {
            _ = try? await requestReadingGzipPOST(path: "/reading/bookapi/read_history/update/v", rawJSON: raw, identity: id)
        }

        let uploadBody: [String: Any] = [
            "books": [[
                "book_id": seriesID,
                "item_id": vid,
                "read_progress": posMS,
                "read_time": posMS,
                "read_timestamp": nowMS,
            ] as [String: Any]]
        ]
        if let raw = try? JSONSerialization.data(withJSONObject: uploadBody, options: [.sortedKeys]) {
            _ = try? await requestReadingGzipPOST(path: "/reading/bookapi/read_progress/upload/v", rawJSON: raw, identity: id)
        }
    }

    // MARK: 首页（游客走持久化身份，登录后自动带 Cookie + x-tt-token 走个性化推荐 + cell/change 无限翻页）

    private static let recommendExtra = "eyJyZWNlbnRfZGlzbGlrZV9naWQiOltdLCJzZXNzaW9uX2FwcF9zdGF5X3RpbWUiOjB9"

    func homeFeed() async throws -> [Series] {
        try await homeFeedFirstPage().items
    }

    func homeFeedFirstPage() async throws -> HomeFeedPage {
        var lastError: Error = ManjuError.emptyResponse("首页")
        for attempt in 0..<2 {
            do {
                let id = try await ensureIdentity(forceNew: attempt > 0)
                var pairs = commonPairs(id)
                pairs += [
                    ("tab_type", "36"), ("tab_index", "1"), ("offset", "0"),
                    ("client_req_type", "7"), ("client_template", "2"), ("bottom_tab_type", "7"),
                    ("last_tab_type", "2"), ("last_tab_index", "0"), ("cold_start_gd", "0"),
                    ("device_level", "3"), ("book_id", "0"),
                ]
                let url = try makeURL(path: "/reading/bookapi/bookmall/tab/v1/", pairs: pairs)
                var request = URLRequest(url: url)
                injectSessionHeaders(&request, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000), includeStoreRegion: true)
                let hasAuth = hasActiveSession
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                AppLog.write("HOME HTTP status=\(status) bytes=\(data.count) auth=\(hasAuth ? 1 : 0) attempt=\(attempt + 1)")
                guard status == 200, !data.isEmpty else { continue }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ManjuError.decoding("首页 JSON")
                }
                if hasAuth, isSessionInvalidJSON(json) {
                    invalidateSessionAndNotify(reason: "首页会话鉴权失效")
                    continue
                }
                var page = SeriesParser.parseHomeTab(json, preferredTabType: "36")
                AppLog.write("HOME tab parsed series=\(page.items.count) cell=\(page.cursor.cellID) plan=\(page.cursor.planID) session=\(page.cursor.sessionID.isEmpty ? 0 : 1) auth=\(hasAuth ? 1 : 0)")
                if !page.cursor.sessionID.isEmpty, page.items.count < 8 {
                    if let more = try? await homeFeedNextPage(cursor: page.cursor), !more.items.isEmpty {
                        let merged = mergeSeries(existing: page.items, incoming: more.items)
                        page = HomeFeedPage(items: merged, cursor: more.cursor)
                    }
                }
                if !page.items.isEmpty {
                    AppLog.write("HOME initial ready count=\(page.items.count) nextOffset=\(page.cursor.offset) hasMore=\(page.cursor.hasMore) titles=\(page.items.prefix(5).map(\.title).joined(separator: " / "))")
                    return page
                }
                lastError = ManjuError.emptyResponse("首页无剧目")
            } catch {
                lastError = error
                AppLog.write("HOME attempt=\(attempt + 1) error=\(error.localizedDescription)")
            }
        }
        throw lastError
    }

    func homeFeedNextPage(cursor: HomeFeedCursor) async throws -> HomeFeedPage {
        guard cursor.hasMore, !cursor.cellID.isEmpty, !cursor.planID.isEmpty else {
            var stopped = cursor
            stopped.hasMore = false
            return HomeFeedPage(items: [], cursor: stopped)
        }
        let id = try await ensureIdentity(forceNew: false)
        var pairs = commonPairs(id)
        pairs += [
            ("cell_id", cursor.cellID),
            ("plan_id", cursor.planID),
            ("tab_type", "36"),
            ("offset", String(cursor.offset)),
            ("client_req_type", "2"),
            ("client_template", "7"),
            ("change_type", "0"),
            ("gender", "2"),
            ("limit", "0"),
            ("recommend_extra", Self.recommendExtra),
        ]
        if !cursor.sessionID.isEmpty {
            pairs.append(("session_id", cursor.sessionID))
        }
        if !cursor.seenIDs.isEmpty {
            let filterIDs = cursor.seenIDs.suffix(200).joined(separator: ",")
            pairs.append(("filter_ids", filterIDs))
        }
        let url = try makeURL(path: "/reading/bookapi/bookmall/cell/change/v", pairs: pairs)
        var request = URLRequest(url: url)
        injectSessionHeaders(&request, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000), includeStoreRegion: true)
        let hasAuth = hasActiveSession
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.write("HOME_PAGE HTTP status=\(status) offset=\(cursor.offset) bytes=\(data.count) auth=\(hasAuth ? 1 : 0)")
        guard status == 200, !data.isEmpty,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            var stopped = cursor
            stopped.hasMore = false
            return HomeFeedPage(items: [], cursor: stopped)
        }
        if hasAuth, isSessionInvalidJSON(json) {
            invalidateSessionAndNotify(reason: "首页分页会话鉴权失效")
            var stopped = cursor
            stopped.hasMore = false
            return HomeFeedPage(items: [], cursor: stopped)
        }
        let next = SeriesParser.parseHomeChange(json, currentCursor: cursor)
        AppLog.write("HOME_PAGE parsed new=\(next.items.count) nextOffset=\(next.cursor.offset) hasMore=\(next.cursor.hasMore)")
        return next
    }

    func homeTopRank() async -> [Series] {
        do {
            let id = try await ensureIdentity(forceNew: false)
            var pairs = commonPairs(id)
            pairs += [
                ("cell_id", "7470092475068071998"),
                ("tab_type", "26"),
                ("selected_items", "comic_series_rank"),
                ("sub_selected_items", "comic_series_hot_rank"),
                ("category_id", "0"),
                ("cell_sub_id", "0"),
                ("client_req_type", "2"),
                ("client_template", "2"),
                ("gender", "2"),
                ("limit", "0"),
                ("offset", "0"),
                ("unlimited_selector_change_type", "2"),
            ]
            let url = try makeURL(path: "/reading/bookapi/bookmall/cell/change/v", pairs: pairs)
            var request = URLRequest(url: url)
            injectSessionHeaders(&request, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000), includeStoreRegion: true)
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, !data.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                AppLog.write("HOME_RANK HTTP status=\(status) bytes=\(data.count)")
                return []
            }
            let ranked = Array(SeriesParser.parseRankList(json).prefix(10))
            AppLog.write("HOME_RANK parsed count=\(ranked.count)")
            return ranked
        } catch {
            AppLog.write("HOME_RANK warn=\(error.localizedDescription)")
            return []
        }
    }

    private func mergeSeries(existing: [Series], incoming: [Series]) -> [Series] {
        var seen = Set(existing.map(\.id))
        var out = existing
        for item in incoming where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }

    // MARK: 详情 / 选集目录

    func album(seriesID: String) async throws -> AlbumDetail {
        let id = try await ensureIdentity()
        var bodyObj: [String: Any] = [
            "album_id": seriesID,
            "need_video_detail_info": true,
            "biz_param": [
                "video_platform": 1024, "device_level": 3,
                "need_all_video_definition": true, "need_mp4_align": false,
                "use_os_player": false,
            ] as [String: Any],
        ]
        if let n = Int64(seriesID) { bodyObj["series_ids"] = [n] } else { bodyObj["series_ids"] = [seriesID] }
        let body = try JSONSerialization.data(withJSONObject: bodyObj, options: [.sortedKeys])

        let path = "/novel/player/album_detail/v1/"
        var request = URLRequest(url: try makeURL(path: path, pairs: commonPairs(id)))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Bytes.hex(HGPlayerSign.md5(Array(body))), forHTTPHeaderField: "x-ss-stub")
        injectSessionHeaders(&request, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000))

        var (data, response) = try await session.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.write("ALBUM unsigned HTTP status=\(status) bytes=\(data.count) series=\(seriesID) auth=\(hasActiveSession ? 1 : 0)")

        if data.isEmpty {
            let signed = try sign(id: id, pairs: commonPairs(id), path: path, body: body)
            var signedReq = URLRequest(url: URL(string: base + path + "?" + signed.query)!)
            signedReq.httpMethod = "POST"
            signedReq.httpBody = body
            for (k, v) in signed.headers { signedReq.setValue(v, forHTTPHeaderField: k) }
            injectSessionHeaders(&signedReq, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000))
            (data, response) = try await session.data(for: signedReq)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AppLog.write("ALBUM signed fallback HTTP status=\(status) bytes=\(data.count) series=\(seriesID)")
        }

        guard status == 200, !data.isEmpty else { throw ManjuError.emptyResponse("选集目录") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = JSONValue.int(json["code"]), code == 0 else {
            throw ManjuError.decoding("album_detail 响应异常")
        }
        let fallback = Series(id: seriesID, title: "", cover: "", intro: "",
                              episodeCount: 0, firstVid: nil, firstIndex: 1,
                              updatedAt: Date().timeIntervalSince1970)
        guard let detail = SeriesParser.parseAlbum(json, fallback: fallback) else {
            throw ManjuError.decoding("选集目录为空")
        }
        AppLog.write("ALBUM parsed title=\(detail.series.title) episodes=\(detail.episodes.count)")
        return detail
    }

    // MARK: 搜索（HGPlayerSign v04.06.04 + tab_type=19 综合；空结果时 cue 联想兜底）

    func search(query: String) async throws -> (series: [Series], suggestions: [SearchSuggestion]) {
        let id = try await ensureIdentity()
        let path = "/reading/bookapi/search/tab/v1/"
        let extra: [(String, String)] = [
            ("query", query), ("offset", "0"), ("count", "20"), ("tab_type", "19"),
            ("tab_name", ""), ("search_source", "1"), ("search_id", ""), ("passback", ""),
            ("corrected_query", ""), ("use_correct", "1"), ("bookstore_tab", "0"), ("source_page", "0"),
        ]
        do {
            let signed = signSearch(id: id, pairs: commonPairs(id) + extra, path: path)
            var req = URLRequest(url: URL(string: base + path + "?" + signed.query)!)
            for (k, v) in signed.headers { req.setValue(v, forHTTPHeaderField: k) }
            injectSessionHeaders(&req, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000))
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AppLog.write("SEARCH tab HTTP status=\(status) bytes=\(data.count) query=\(query)")
            if status == 200, !data.isEmpty,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let list = SeriesParser.parseList(from: json)
                if !list.isEmpty { return (list, []) }
            }
        } catch {
            AppLog.write("SEARCH tab error=\(error.localizedDescription)")
        }

        let cue = try await searchCue(query: query)
        AppLog.write("SEARCH cue suggestions=\(cue.count) query=\(query)")
        return ([], cue)
    }

    private func searchCue(query: String) async throws -> [SearchSuggestion] {
        let id = try await ensureIdentity()
        let path = "/reading/bookapi/search/cue/v1/"
        let url = try makeURL(path: path, pairs: commonPairs(id) + [("query", query)])
        var request = URLRequest(url: url)
        injectSessionHeaders(&request, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000))
        var (data, response) = try await session.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.write("SEARCH cue unsigned HTTP status=\(status) bytes=\(data.count)")
        if data.isEmpty {
            let signed = try sign(id: id, pairs: commonPairs(id) + [("query", query)], path: path, body: Data())
            var req = URLRequest(url: URL(string: base + path + "?" + signed.query)!)
            for (k, v) in signed.headers { req.setValue(v, forHTTPHeaderField: k) }
            injectSessionHeaders(&req, identity: id, nowMS: Int(Date().timeIntervalSince1970 * 1000))
            (data, response) = try await session.data(for: req)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AppLog.write("SEARCH cue signed HTTP status=\(status) bytes=\(data.count)")
        }
        guard status == 200, !data.isEmpty,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManjuError.emptyResponse("搜索联想")
        }
        return SeriesParser.parseSuggestions(json)
    }

    // MARK: 播放取流（本地 HGCurrentPlayer 签名 + 会话注入 + 失效回落）

    /// 返回按「1.2 (2) 真机验证口径」排序的全部可播候选：
    /// 1. 只请求 `device_level=3`；
    /// 2. `bytevc2` 一律跳过（VLCKit 3.6 无法解码字节私有 bvc2）；
    /// 3. 有 H.264 时，H.264 候选取最高档排第一；
    /// 4. 无 H.264 时，取最低档 HEVC/bytevc1 排第一；
    /// 5. 其余可播候选排在其后，供播放页逐档降级重试。
    func playbackCandidates(vid: String, seriesID: String) async throws -> [StreamInfo] {
        let primaryBody = try buildPlaybackBody(vid: vid, deviceLevel: 3)

        struct UnsupportedStreamError: Error { let message: String }

        var lastError: Error = ManjuError.emptyResponse("播放")
        for attempt in 0..<3 {
            do {
                let id = try await ensureIdentity(forceNew: attempt > 0 && !hasActiveSession)
                let resp = try await requestPlaybackModel(vid: vid, identity: id, body: primaryBody, attempt: attempt, tag: "dl3")
                let status = resp.status
                let data = resp.data

                if status == 200, !data.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    if resp.hasAuth, let dict = json as? [String: Any], isSessionInvalidJSON(dict) {
                        invalidateSessionAndNotify(reason: "播放取流返回未登录")
                        continue
                    }

                    if let summary = parseStreamCandidates(json: json, vid: vid, seriesID: seriesID, identity: id) {
                        // 1.2 (2) 口径：只使用 device_level=3 的一次响应，不再补请求 device_level=1。
                        let ranked = Self.rankCandidates(summary.candidates)

                        if let chosen = ranked.first {
                            let h264Count = ranked.filter { $0.isH264 }.count
                            AppLog.write("PLAY streams=\(summary.totalStreams) candidates=\(ranked.count) skip_vc2=\(summary.skippedVC2) skip_key=\(summary.skippedKey) h264=\(h264Count) max_server=\(summary.maxServerHeight)p")
                            AppLog.write("PLAY ranked vid=\(vid) order=\(ranked.map { "\($0.info.definition):\($0.info.codec)" }.joined(separator: ","))")
                            AppLog.write("PLAY chosen vid=\(vid) host=\(chosen.info.domain) codec=\(chosen.info.codec) def=\(chosen.info.definition) size=\(chosen.info.fileSize) encrypted=\(chosen.info.isEncrypted) key=\(chosen.info.keyHex == nil ? "clear" : "present") attempt=\(attempt + 1)")
                            consecutiveRegistrations = 0
                            return ranked.map(\.info)
                        }

                        if summary.skippedVC2 > 0 {
                            AppLog.write("PLAY unsupported vid=\(vid) reason=bytevc2_only skip_vc2=\(summary.skippedVC2) skip_key=\(summary.skippedKey)")
                            throw UnsupportedStreamError(message: "该集仅提供 bytevc2 (bvc2) 编码流，当前播放器暂不支持解码")
                        }
                    } else if let fallback = SeriesParser.firstMainURL(in: json) {
                        AppLog.write("PLAY fallback main_url (stream metadata unavailable) vid=\(vid)")
                        consecutiveRegistrations = 0
                        return [StreamInfo(url: fallback, domain: URL(string: fallback)?.host ?? "unknown",
                                           vid: vid, seriesID: seriesID, identity: id.deviceID,
                                           keyHex: nil, backupURL: nil, codec: "unknown", definition: "?",
                                           fileSize: 0, isEncrypted: false)]
                    }
                }
                lastError = data.isEmpty
                    ? ManjuError.emptyResponse("播放接口 \(status) / 0B")
                    : ManjuError.noMainURL("播放接口 \(status) / \(data.count)B")
                AppLog.write("PLAY retry reason=\(lastError.localizedDescription) attempt=\(attempt + 1)")
            } catch let err as UnsupportedStreamError {
                throw ManjuError.noMainURL(err.message)
            } catch {
                lastError = error
                AppLog.write("PLAY attempt=\(attempt + 1) error=\(error.localizedDescription)")
            }
        }
        throw lastError
    }

    /// 兼容旧调用口径：返回排序后的第一档。
    func playback(vid: String, seriesID: String) async throws -> StreamInfo {
        guard let first = try await playbackCandidates(vid: vid, seriesID: seriesID).first else {
            throw ManjuError.noMainURL("播放取流没有可用候选")
        }
        return first
    }

    private func buildPlaybackBody(vid: String, deviceLevel: Int) throws -> Data {
        let obj: [String: Any] = [
            "biz_param": [
                "detail_page_version": 0, "device_level": deviceLevel, "disable_digg_stat": false,
                "disable_video_relate_book": false, "need_all_video_definition": true,
                "need_mp4_align": false, "use_os_player": false, "use_server_dns": true,
                "use_server_dns_scene": "cold_start_stage", "video_platform": 1024,
            ] as [String: Any],
            "dr_scene": "player",
            "mixed_video_id_map": ["1004": [vid]] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    private func requestPlaybackModel(vid: String, identity: Identity, body: Data, attempt: Int, tag: String) async throws -> (status: Int, data: Data, hasAuth: Bool) {
        let path = "/novel/player/multi_video_model/v1"
        let signed = try sign(id: identity, pairs: commonPairs(identity), path: path, body: body)
        var request = URLRequest(url: URL(string: base + path + "?" + signed.query)!)
        request.httpMethod = "POST"
        request.httpBody = body
        for (k, v) in signed.headers { request.setValue(v, forHTTPHeaderField: k) }
        injectSessionHeaders(&request, identity: identity, nowMS: Int(Date().timeIntervalSince1970 * 1000), includeStoreRegion: true)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let hasAuth = hasActiveSession
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let logid = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Tt-Logid") ?? "-"
        AppLog.write("PLAY[\(tag)] vid=\(vid) auth=\(hasAuth ? 1 : 0) attempt=\(attempt + 1) status=\(status) bytes=\(data.count) logid=\(logid)")
        return (status, data, hasAuth)
    }

    private struct StreamCandidate {
        let info: StreamInfo
        let height: Int
        let bitrate: Int
        let isH264: Bool
    }

    private struct ParsedStreamSummary {
        let candidates: [StreamCandidate]
        let maxServerHeight: Int
        let minServerHeight: Int
        let totalStreams: Int
        let skippedVC2: Int
        let skippedKey: Int
    }

    /// 判定顺序与 1.2 (2) 真机验证口径一致：高度优先、同高度比码率（均为从高到低）。
    /// 编码分组由 `rankCandidates` 在排序前完成，因此 H.264 与 HEVC 不会在这里互相抢占。
    private static func isBetterCandidate(_ a: StreamCandidate, _ b: StreamCandidate) -> Bool {
        if a.height != b.height { return a.height > b.height }
        if a.bitrate != b.bitrate { return a.bitrate > b.bitrate }
        return a.info.fileSize > b.info.fileSize
    }

    /// 1.4.4 修复口径：
    /// - 有 H.264 时取最高档 H.264（按高度＋码率），其余 H.264 与可播编码依次作为降级候选；
    /// - 无 H.264 时按高度＋码率从高到低排（最高档 bytevc1 优先，失败再逐档降级）。
    private static func rankCandidates(_ candidates: [StreamCandidate]) -> [StreamCandidate] {
        let h264 = candidates.filter { $0.isH264 }.sorted(by: isBetterCandidate)
        let others = candidates.filter { !$0.isH264 }.sorted(by: isBetterCandidate)
        return h264 + others
    }

    private static func parseDefinitionHeight(_ definition: String, width: Int, height: Int, qualityType: Int?) -> Int {
        let lower = definition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("4k") || lower.contains("2160") { return 2160 }
        if lower.contains("2k") || lower.contains("1440") { return 1440 }
        let digits = lower.prefix(while: { $0.isNumber })
        if !digits.isEmpty, let parsed = Int(digits), parsed > 0 {
            return parsed
        }
        if width > 0 && height > 0 {
            return min(width, height)
        }
        switch qualityType {
        case 1: return 1080
        case 10: return 720
        case 20: return 540
        case 30: return 480
        case 40: return 360
        default: return 0
        }
    }

    private func parseStreamCandidates(json: Any, vid: String, seriesID: String, identity: Identity) -> ParsedStreamSummary? {
        guard let root = json as? [String: Any],
              let data = root["data"] as? [String: Any] else { return nil }
        var entry = data[vid] as? [String: Any]
        if entry == nil { entry = data.values.compactMap { $0 as? [String: Any] }.first }
        guard let payload = entry else { return nil }

        var model: Any? = payload["video_model"]
        if let text = model as? String, let d = text.data(using: .utf8) {
            model = try? JSONSerialization.jsonObject(with: d)
        }
        guard let vm = model as? [String: Any] else {
            AppLog.write("PLAY parse no video_model vid=\(vid) keys=\(payload.keys.sorted().joined(separator: ","))")
            return nil
        }

        var list: [[String: Any]] = []
        if let arr = vm["video_list"] as? [[String: Any]] {
            list = arr
        } else if let map = vm["video_list"] as? [String: Any] {
            list = map.values.compactMap { $0 as? [String: Any] }
        }
        guard !list.isEmpty else {
            AppLog.write("PLAY parse empty video_list vid=\(vid) keys=\(vm.keys.sorted().joined(separator: ","))")
            return nil
        }

        let keySeed: Data? = {
            guard let s = JSONValue.string(vm["key_seed"]), !s.isEmpty else { return nil }
            return SpadeKey.base64Data(s)
        }()

        var candidates: [StreamCandidate] = []
        var maxServerHeight = 0
        var minServerHeight = Int.max
        var skippedVC2 = 0, skippedKey = 0

        for v in list {
            let meta = v["video_meta"] as? [String: Any] ?? [:]
            let enc = v["encrypt_info"] as? [String: Any] ?? [:]
            let codec = (JSONValue.string(meta["codec_type"]) ?? JSONValue.string(v["codec_type"]) ?? "").lowercased()
            let gear = (JSONValue.string(v["gear_des_key"]) ?? "").lowercased()
            let w = JSONValue.int(meta["vwidth"]) ?? JSONValue.int(v["vwidth"]) ?? 0
            let h = JSONValue.int(meta["vheight"]) ?? JSONValue.int(v["vheight"]) ?? 0
            var definition = JSONValue.string(meta["definition"]) ?? JSONValue.string(v["definition"]) ?? ""
            let qualityType = JSONValue.int(v["quality_type"])
            let height = Self.parseDefinitionHeight(definition, width: w, height: h, qualityType: qualityType)
            if height > maxServerHeight { maxServerHeight = height }
            if height > 0, height < minServerHeight { minServerHeight = height }
            if definition.isEmpty { definition = height > 0 ? "\(height)p" : "?" }

            // VLCKit 3.6.0 (FFmpeg 4.4.4 + VideoToolbox) 与 iOS AVFoundation 均无法解码字节私有 bvc2/bv2C，跳过不播。
            if codec.contains("bytevc2") || codec.contains("bvc2") || gear.contains("bytevc2") || gear.contains("bvc2") {
                skippedVC2 += 1
                continue
            }

            let backupURL = mediaURLString(v["backup_url"], seed: keySeed)
            guard let primary = mediaURLString(v["main_url"], seed: keySeed) ?? backupURL else { continue }

            let spade = JSONValue.string(enc["spade_a"]) ?? JSONValue.string(v["spade_a"]) ?? ""
            let encFlag = JSONValue.bool(enc["encrypt"]) ?? false
            let method = (JSONValue.string(enc["encryption_method"]) ?? "").lowercased()
            let encrypted = !spade.isEmpty || encFlag || method == "cenc-aes-ctr"
            var key: String?
            if encrypted {
                guard let k = SpadeKey.contentKey(envelope: spade), !k.isEmpty else {
                    skippedKey += 1
                    AppLog.write("PLAY skip encrypted stream codec=\(codec) spade_len=\(spade.count) reason=key_unwrap_failed")
                    continue
                }
                key = k
            }

            let size = JSONValue.int(meta["size"]) ?? JSONValue.int(v["size"]) ?? JSONValue.int(v["file_size"]) ?? 0
            let bitrate = JSONValue.int(meta["bitrate"]) ?? JSONValue.int(v["bitrate"]) ?? 0
            let isH264 = codec == "h264" || codec == "avc1" || codec == "avc3" || codec == "avc"
                || gear.contains("h264") || gear.contains("avc")

            let info = StreamInfo(url: primary,
                                  domain: URL(string: primary)?.host ?? "unknown",
                                  vid: vid,
                                  seriesID: seriesID,
                                  identity: identity.deviceID,
                                  keyHex: key,
                                  backupURL: backupURL == primary ? nil : backupURL,
                                  codec: codec.isEmpty ? "unknown" : codec,
                                  definition: definition,
                                  fileSize: size,
                                  isEncrypted: encrypted)
            candidates.append(StreamCandidate(info: info, height: height, bitrate: bitrate, isH264: isH264))
        }

        return ParsedStreamSummary(
            candidates: candidates,
            maxServerHeight: maxServerHeight,
            minServerHeight: minServerHeight == Int.max ? 0 : minServerHeight,
            totalStreams: list.count,
            skippedVC2: skippedVC2,
            skippedKey: skippedKey
        )
    }

    private func mediaURLString(_ value: Any?, seed: Data?) -> String? {
        var address = JSONValue.string(value) ?? ""
        guard !address.isEmpty else { return nil }
        if let seed, let plain = decryptSpadeURL(address, seed: seed) { address = plain }
        if !address.hasPrefix("http"), let d = Data(base64Encoded: address),
           let plain = String(data: d, encoding: .utf8) { address = plain }
        guard address.hasPrefix("http"), let u = URL(string: address), u.host != nil else { return nil }
        return address
    }

    private static let spadeURLConst: [UInt8] = SpadeKey.hexBytes("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58") ?? []

    private func decryptSpadeURL(_ value: String, seed: Data) -> String? {
        guard !value.isEmpty, let raw = SpadeKey.base64Data(value) else { return nil }
        let b = [UInt8](raw)
        guard b.count >= 5, b[0] == 0xa8, b[2] == 0x01, b[3] == 0x00 else { return nil }
        let n = (b.count - 4) / 16 * 16
        guard n > 0 else { return nil }
        let h1 = Array(SHA512.hash(data: seed))
        let h2 = Array(SHA512.hash(data: Data(h1 + Self.spadeURLConst)))
        let key = Array(h2[0..<16]), iv = Array(h2[16..<32])
        let cipher = Array(b[4..<(4 + n)])
        var out = [UInt8](repeating: 0, count: n + 16)
        var moved = 0
        let st = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(0), key, key.count, iv,
                         cipher, cipher.count, &out, out.count, &moved)
        guard st == kCCSuccess else { return nil }
        var plain = Array(out[0..<moved])
        if let pad = plain.last, pad >= 1, pad <= 16, Int(pad) <= plain.count { plain.removeLast(Int(pad)) }
        while plain.last == 0 { plain.removeLast() }
        return String(bytes: plain, encoding: .utf8)
    }

    // MARK: - Reading 端点路由（sinfonlinea 优先，失败回退 lq）

    private func requestReadingGET(path: String, extraQuery: [(String, String)], identity: Identity) async throws -> (Data, Int) {
        for origin in [base, lqBase] {
            let nowMS = Int(Date().timeIntervalSince1970 * 1000)
            let pairs = commonPairs(identity) + extraQuery
            guard var comp = URLComponents(string: origin + path) else { continue }
            comp.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
            guard let url = comp.url else { continue }
            var req = URLRequest(url: url)
            injectSessionHeaders(&req, identity: identity, nowMS: nowMS)
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            AppLog.write("READING GET origin=\(URL(string: origin)?.host ?? "?") path=\(path) status=\(status) bytes=\(data.count)")
            if status == 200, !data.isEmpty {
                return (data, status)
            }
            if status == 401 {
                return (data, status)
            }
        }
        return (Data(), 0)
    }

    private func requestReadingGzipPOST(path: String, rawJSON: Data, identity: Identity) async throws -> (Data, Int) {
        let gz = Self.gzipCompress(rawJSON) ?? rawJSON
        let useGzip = gz.count != rawJSON.count || gz.starts(with: [0x1f, 0x8b])
        for origin in [base, lqBase] {
            let nowMS = Int(Date().timeIntervalSince1970 * 1000)
            let signed = try sign(id: identity, pairs: commonPairs(identity), path: path, body: gz)
            guard let url = URL(string: origin + path + "?" + signed.query) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = gz
            for (k, v) in signed.headers { req.setValue(v, forHTTPHeaderField: k) }
            injectSessionHeaders(&req, identity: identity, nowMS: nowMS)
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            if useGzip {
                req.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            }
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            AppLog.write("READING POST origin=\(URL(string: origin)?.host ?? "?") path=\(path) status=\(status) bytes=\(data.count)")
            if status == 200, !data.isEmpty {
                return (data, status)
            }
        }
        return (Data(), 0)
    }

    // MARK: - 公共参数 / 签名 / Passport 构造 / 会话携带

    private var hasActiveSession: Bool {
        guard let sess = authSession else { return false }
        return sess.hasSessionCookie && !sess.isExpired
    }

    private func isSessionInvalidJSON(_ json: [String: Any]) -> Bool {
        let code = JSONValue.int(json["code"])
            ?? JSONValue.int((json["data"] as? [String: Any])?["error_code"])
            ?? JSONValue.int(json["error_code"])
            ?? 0
        let msg = (JSONValue.string(json["message"]) ?? "").uppercased()
        return code == 101108 || msg.contains("USER_NOT_LOGIN")
    }

    private func checkBusinessSessionValidity(json: [String: Any]) throws {
        if isSessionInvalidJSON(json) {
            invalidateSessionAndNotify(reason: "服务端返回未登录 (101108)")
            throw ManjuError.sessionExpired("服务端返回未登录")
        }
    }

    private func invalidateSessionAndNotify(reason: String) {
        guard authSession != nil else { return }
        authSession = nil
        Task { @MainActor in
            AuthStore.shared.handleRemoteSessionInvalidated(reason: reason)
        }
    }

    private func injectSessionHeaders(_ request: inout URLRequest, identity: Identity, nowMS: Int, includeStoreRegion: Bool = false) {
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("8704", forHTTPHeaderField: "x-ss-dp")
        request.setValue("101", forHTTPHeaderField: "lc")
        request.setValue("\(nowMS)-\(Int.random(in: 100_000_000...999_999_999))", forHTTPHeaderField: "x-reading-request")
        if includeStoreRegion {
            request.setValue("cn-gd", forHTTPHeaderField: "x-tt-store-region")
            request.setValue("did", forHTTPHeaderField: "x-tt-store-region-src")
        }
        if let sess = authSession, sess.hasSessionCookie, !sess.isExpired {
            let cookieHeader = sess.cookieHeader(identity: identity)
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            let shortToken = sess.shortXTTToken
            if !shortToken.isEmpty {
                request.setValue(shortToken, forHTTPHeaderField: "x-tt-token")
            }
        } else {
            var guestCookies: [String] = []
            if !identity.ttreq.isEmpty { guestCookies.append("ttreq=\(identity.ttreq)") }
            if !identity.iid.isEmpty { guestCookies.append("install_id=\(identity.iid)") }
            if !guestCookies.isEmpty {
                request.setValue(guestCookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            }
        }
    }

    private func buildSignedPassportRequest(
        path: String,
        queryPairs: [(String, String)],
        formPairs: [(String, String)],
        cookies: [String: String],
        identity: Identity,
        nowMS: Int64
    ) throws -> (URLRequest, Int) {
        let bodyStr = Self.formURLEncoded(formPairs)
        let bodyData = Data(bodyStr.utf8)
        // passport 公共参数（NetworkParams.putCommonParams 口径）：设备身份必须与发码同套。
        // 只带 SDK 常量、不带 aid/app_name/device_id 时，upsms/verify 会被服务端判 [22] 非法应用。
        let commonQuery = passportCommonQuery(identity)
        let signed = try sign(id: identity, pairs: commonQuery + queryPairs, path: path, body: bodyData, nowMillis: nowMS)

        guard let url = URL(string: passportOrigin + path + "?" + signed.query) else {
            throw ManjuError.decoding("Passport URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        for (k, v) in signed.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        // 关键适配：HGCurrentPlayer 默认写 application/json，必须覆写为 form-urlencoded
        request.setValue(formContentType, forHTTPHeaderField: "Content-Type")
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("5051452", forHTTPHeaderField: "passport-sdk-version")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let cookieStr = cookies.keys.sorted()
            .compactMap { k -> String? in
                guard let v = cookies[k], !v.isEmpty else { return nil }
                return "\(k)=\(v)"
            }
            .joined(separator: "; ")
        if !cookieStr.isEmpty {
            request.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        }
        return (request, signed.query.count)
    }

    private func passportSdkQuery(withRom: Bool) -> [(String, String)] {
        var q: [(String, String)] = [
            ("cronet_version", "8d40f833_2026-03-03"),
            ("passport-sdk-version", "5051452"),
            ("ttnet_version", "4.2.243.17-hongguo"),
            ("use_new_token_expire_rule", "true"),
            ("use_store_region_cookie", "1"),
        ]
        if withRom {
            q.append(("rom_version", "TQ3A.230805.001"))
        }
        return q
    }

    private func passportDeviceForm(_ id: Identity, nowMS: Int64) -> [(String, String)] {
        [
            ("_rticket", String(nowMS)),
            ("ac", "wifi"),
            ("aid", "8704"),
            ("app_name", "kylin_read"),
            ("cdid", id.cdid),
            ("channel", "channel_not_set"),
            ("device_brand", "google"),
            ("device_id", id.deviceID),
            ("device_platform", "android"),
            ("device_type", "Pixel 5"),
            ("dpi", "420"),
            ("host_abi", "arm64-v8a"),
            ("iid", id.iid),
            ("language", "zh"),
            ("manifest_version_code", "72732"),
            ("os", "android"),
            ("os_api", "33"),
            ("os_version", "13"),
            ("resolution", "2340*1080"),
            ("ssmix", "a"),
            ("update_version_code", "72732"),
            ("version_code", "72732"),
            ("version_name", "7.2.7.32"),
            ("app_dark_mode", "0"),
            ("app_mini_window", "0"),
            ("battery_pct", "72"),
            ("charging", "1"),
            ("cold_start_session_cnt_in_day", "100"),
            ("cold_start_session_cnt_in_life", "76"),
            ("cold_start_session_id", coldStartSessionID),
            ("compliance_status", "0"),
            ("current_volume", "1"),
            ("down_speed", "311565"),
            ("dragon_device_type", "phone"),
            ("font_scale", "100"),
            ("gender", "2"),
            ("har_status", "0"),
            ("is_android_pad_screen", "0"),
            ("is_power_save_mode", "0"),
            ("need_personal_recommend", "1"),
            ("network_type", "4"),
            ("normal_session_cnt_in_day", "182"),
            ("normal_session_cnt_in_life", "270"),
            ("normal_session_id", normalSessionID),
            ("player_so_load", "1"),
            ("pv_player", "72732"),
            ("screen_brightness", "963"),
            ("sys_dark_mode", "0"),
            ("sys_mini_window", "1"),
        ]
    }

    private func commonPairs(_ id: Identity) -> [(String, String)] {
        let now = Int(Date().timeIntervalSince1970)
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        return [
            ("iid", id.iid), ("device_id", id.deviceID), ("ac", "wifi"),
            ("channel", "channel_not_set"), ("aid", "8704"), ("app_name", "kylin_read"),
            ("cdid", id.cdid), ("version_code", "72732"), ("version_name", "7.2.7.32"),
            ("device_platform", "android"), ("os", "android"), ("ssmix", "a"),
            ("device_type", "Pixel 5"), ("device_brand", "google"), ("language", "zh"),
            ("os_api", "33"), ("os_version", "13"), ("manifest_version_code", "72732"),
            ("resolution", "2340*1080"), ("dpi", "420"), ("update_version_code", "72732"),
            ("host_abi", "arm64-v8a"), ("dragon_device_type", "phone"), ("pv_player", "72732"),
            ("compliance_status", "0"), ("need_personal_recommend", "1"), ("player_so_load", "1"),
            ("is_android_pad_screen", "0"), ("openudid", id.openudid),
            ("req_time", String(now)), ("_rticket", String(ms)), ("user_agent", ua),
        ]
    }

    /// Passport 公共参数：与发码/登录 body 的 passportDeviceForm 同一套身份，
    /// 只去掉 reading 系请求专用的 req_time/user_agent；_rticket 由签名器统一追加。
    /// 依据：hongguo-desktop `sign_request_with` 把 DeviceProfile 全量拼进 query；
    /// hongguoTV（真号实测）`PhoneLogin.call` 也把 device 全量放进 query。
    private func passportCommonQuery(_ id: Identity) -> [(String, String)] {
        commonPairs(id).filter { key, _ in
            key != "req_time" && key != "user_agent" && key != "_rticket"
        }
    }

    private func signSearch(id: Identity, pairs: [(String, String)], path: String, nowMillis: Int64? = nil) -> (query: String, headers: [String: String]) {
        HGPlayerSign.appID = "8704"
        let ms = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        let filtered = pairs.filter { $0.0 != "ts" && $0.0 != "_rticket" }
        let result = HGPlayerSign.signPOST(path: path, pairs: filtered, nowMillis: ms,
                                           deviceID: id.deviceID, versionName: "7.2.7.32", body: [])
        AppLog.write("SIGN[v04.06.04] path=\(path) body=0B query=\(result.query.count) chars headers=\(result.headers.keys.sorted().joined(separator: ","))")
        return result
    }

    private func sign(id: Identity, pairs: [(String, String)], path: String, body: Data, nowMillis: Int64? = nil) throws -> (query: String, headers: [String: String]) {
        HGCurrentPlayer.appID = "8704"
        HGCurrentPlayer.licenseID = "646637794"
        HGCurrentPlayer.sdkVersion = "v04.10.01-ml-android"
        HGCurrentPlayer.envVersion = "v04.10.01.01-bugfix"
        let ms = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        let filtered = pairs.filter { $0.0 != "ts" && $0.0 != "_rticket" }
        let result = try HGCurrentPlayer.sign(pairs: filtered, nowMillis: ms,
                                              deviceID: id.deviceID,
                                              versionName: "7.2.7.32",
                                              body: Array(body))
        AppLog.write("SIGN path=\(path) body=\(body.count)B query=\(result.query.count) chars headers=\(result.headers.keys.sorted().joined(separator: ","))")
        return result
    }

    private func makeURL(path: String, absolute: Bool = false, pairs: [(String, String)]) throws -> URL {
        let full = absolute ? path : base + path
        guard var components = URLComponents(string: full) else { throw ManjuError.decoding("URL \(full)") }
        components.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw ManjuError.decoding("query \(path)") }
        return url
    }

    // MARK: - 静态工具（XOR05 / Form 编码 / Cookie 解析 / Gzip）

    static func normalizeMobile(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if s.hasPrefix("+86") { s = String(s.dropFirst(3)) }
        else if s.hasPrefix("86"), s.count > 11 { s = String(s.dropFirst(2)) }
        return s
    }

    static func xor05Hex(_ text: String) -> String {
        text.utf8.map { String(format: "%02x", $0 ^ 0x05) }.joined()
    }

    private static let formUnreserved: Set<UInt8> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".utf8)

    static func formEncodeComponent(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            if formUnreserved.contains(b) {
                out.append(Character(UnicodeScalar(b)))
            } else {
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    static func formURLEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(formEncodeComponent($0.0))=\(formEncodeComponent($0.1))" }.joined(separator: "&")
    }

    static func parseSetCookiePairs(from response: HTTPURLResponse, url: URL) -> [String: String] {
        var jar: [String: String] = [:]
        // 1) 结合 Foundation HTTPCookie 解析（处理 Expires 逗号等标准格式）
        var stringHeaders: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                stringHeaders[ks] = vs
            }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: url) {
            jar[cookie.name] = cookie.value
        }
        // 2) 全量直接切分 Set-Cookie 串（兜住跨域 Domain 如 .fqnovel.com / .toutiao.com）
        if let rawSetCookie = response.value(forHTTPHeaderField: "Set-Cookie") {
            let pattern = #",\s*(?=[A-Za-z0-9_.\-]+=)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = rawSetCookie as NSString
                let matches = regex.matches(in: rawSetCookie, range: NSRange(location: 0, length: ns.length))
                var parts: [String] = []
                var start = 0
                for m in matches {
                    let len = m.range.location - start
                    if len > 0 {
                        parts.append(ns.substring(with: NSRange(location: start, length: len)))
                    }
                    start = m.range.location + m.range.length
                }
                if start < ns.length {
                    parts.append(ns.substring(from: start))
                }
                for line in parts {
                    let head = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    let kv = head.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if kv.count == 2 {
                        let k = kv[0].trimmingCharacters(in: .whitespaces)
                        let v = kv[1].trimmingCharacters(in: .whitespaces)
                        if !k.isEmpty {
                            jar[k] = v
                        }
                    }
                }
            }
        }
        return jar
    }

    static func parsePassportUser(json: [String: Any], fallbackMobile: String) -> PassportUser {
        let data = json["data"] as? [String: Any] ?? json
        let inner = data["user_info"] as? [String: Any] ?? data
        let uid = JSONValue.string(inner["user_id_str"])
            ?? JSONValue.string(inner["user_id"])
            ?? JSONValue.string(inner["userId"])
            ?? JSONValue.string(inner["uid"])
            ?? ""
        let name = JSONValue.string(inner["name"])
            ?? JSONValue.string(inner["user_name"])
            ?? JSONValue.string(inner["username"])
            ?? JSONValue.string(inner["nick_name"])
            ?? ""
        let mob = JSONValue.string(inner["mobile"]) ?? fallbackMobile
        let avatar = JSONValue.string(inner["avatar_url"]) ?? JSONValue.string(inner["avatar"]) ?? ""
        return PassportUser(userID: uid, name: name, mobile: mob, avatarURL: avatar)
    }

    static func parseSidGuardExpiry(_ sidGuard: String?) -> Double? {
        guard let sidGuard, !sidGuard.isEmpty else { return nil }
        let parts = sidGuard.split(separator: "|")
        if parts.count >= 3,
           let issued = Double(parts[1]),
           let ttl = Double(parts[2]),
           issued > 1_000_000_000, ttl > 0 {
            return issued + ttl
        }
        return nil
    }

    static func gzipCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let dstCapacity = max(data.count + 64, 1024)
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dstBuffer.deallocate() }
        let compressedSize = data.withUnsafeBytes { srcPtr -> Int in
            guard let base = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dstBuffer, dstCapacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard compressedSize > 0 else { return nil }

        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1)
            }
        }
        crc ^= 0xFFFFFFFF
        let isize = UInt32(truncatingIfNeeded: data.count)

        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        out.append(dstBuffer, count: compressedSize)
        var crcLE = crc.littleEndian
        var sizeLE = isize.littleEndian
        out.append(Data(bytes: &crcLE, count: 4))
        out.append(Data(bytes: &sizeLE, count: 4))
        return out
    }

    private static func randomHex(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomDigits(_ count: Int) -> String {
        var s = String(Int.random(in: 1...9))
        for _ in 1..<count { s.append(String(Int.random(in: 0...9))) }
        return s
    }
}
