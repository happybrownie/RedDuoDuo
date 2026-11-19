import Foundation

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var session: AuthSession?
    @Published private(set) var sessionVersion: Int = 0
    @Published var sessionExpiredNotice: String?
    @Published var showLoginSheet = false
    @Published private(set) var currentDeviceID: String = ""

    var isLoggedIn: Bool {
        guard let session else { return false }
        return session.hasSessionCookie && !session.isExpired
    }

    var currentUser: PassportUser? {
        isLoggedIn ? session?.user : nil
    }

    private init() {
        if let loaded = Self.loadPersistedSession() {
            if loaded.isExpired {
                Self.savePersistedSession(nil)
                session = nil
                sessionExpiredNotice = "登录凭据已过期（60天有效期），已切回游客模式，请重新登录"
                AppLog.write("AUTH init expired sid_guard -> cleared to guest")
            } else {
                session = loaded
                AppLog.write("AUTH init loaded cookies=\(loaded.cookies.count) tokenLen=\(loaded.xTTToken.count)")
            }
        }
        Task {
            await ManjuAPI.shared.updateSession(session)
            if let id = await ManjuAPI.shared.currentIdentity() {
                self.currentDeviceID = id.deviceID
            }
            if isLoggedIn {
                await refreshUserInfo()
            }
        }
    }

    /// 会话凭据（Cookie / x-tt-token / 手机号）只存 Keychain，见 SessionKeychain。
    static func loadPersistedSession() -> AuthSession? {
        SessionKeychain.load()
    }

    static func savePersistedSession(_ session: AuthSession?) {
        SessionKeychain.save(session)
    }

    func sendCode(mobile: String) async throws -> SendCodeResult {
        let res = try await ManjuAPI.shared.sendSMSCode(mobile: mobile)
        if let id = await ManjuAPI.shared.currentIdentity() {
            currentDeviceID = id.deviceID
        }
        return res
    }

    func smsLogin(mobile: String, code: String, csrfToken: String) async throws -> LoginOutcome {
        let outcome = try await ManjuAPI.shared.smsLogin(mobile: mobile, code: code, csrfToken: csrfToken)
        if case .success(let newSession) = outcome {
            applyNewSession(newSession)
        }
        return outcome
    }

    func upsmsVerifyOnce(mfa: MfaContext) async throws -> UpsmsPollResult {
        try await ManjuAPI.shared.upsmsVerify(mfa: mfa)
    }

    func completeMfaRelogin(mobile: String, code: String, csrfToken: String, mfa: MfaContext) async throws -> AuthSession {
        let outcome = try await ManjuAPI.shared.smsLogin(
            mobile: mobile,
            code: code,
            csrfToken: csrfToken,
            mfaToken: mfa.mfaToken,
            mfaRetryTag: mfa.retryTag,
            smsCodeKey: mfa.smsCodeKey
        )
        switch outcome {
        case .success(let newSession):
            applyNewSession(newSession)
            return newSession
        case .mfa:
            throw ManjuError.passportError(code: 2046, message: "仍需完成上行短信验证，请确认短信已发送后再试", raw: "")
        }
    }

    func refreshUserInfo() async {
        guard isLoggedIn else { return }
        do {
            let user = try await ManjuAPI.shared.fetchUserInfo()
            if var s = session {
                s.user = PassportUser(
                    userID: user.userID.isEmpty ? s.user.userID : user.userID,
                    name: user.name.isEmpty ? s.user.name : user.name,
                    mobile: user.mobile.isEmpty ? s.user.mobile : user.mobile,
                    avatarURL: user.avatarURL.isEmpty ? s.user.avatarURL : user.avatarURL
                )
                session = s
                Self.savePersistedSession(s)
                await ManjuAPI.shared.updateSession(s)
            }
            AppLog.write("AUTH user/info refreshed ok")
        } catch let err as ManjuError {
            if case .sessionExpired(let reason) = err {
                handleRemoteSessionInvalidated(reason: reason)
            } else {
                AppLog.write("AUTH user/info warn=\(err.localizedDescription)")
            }
        } catch {
            AppLog.write("AUTH user/info warn=\(error.localizedDescription)")
        }
    }

    func logout() {
        session = nil
        sessionExpiredNotice = nil
        Self.savePersistedSession(nil)
        sessionVersion += 1
        Task { await ManjuAPI.shared.updateSession(nil) }
        AppLog.write("AUTH logout -> guest")
    }

    func handleRemoteSessionInvalidated(reason: String) {
        guard session != nil else { return }
        session = nil
        Self.savePersistedSession(nil)
        sessionExpiredNotice = "登录状态已失效（\(reason)），已自动切回游客模式，请重新登录"
        sessionVersion += 1
        Task { await ManjuAPI.shared.updateSession(nil) }
        AppLog.write("AUTH session invalidated -> guest reason=\(reason)")
    }

    func clearExpiredNotice() {
        sessionExpiredNotice = nil
    }

    func refreshDeviceID() async {
        if let id = await ManjuAPI.shared.currentIdentity() {
            currentDeviceID = id.deviceID
        }
    }

    private func applyNewSession(_ newSession: AuthSession) {
        session = newSession
        sessionExpiredNotice = nil
        Self.savePersistedSession(newSession)
        sessionVersion += 1
        Task {
            await ManjuAPI.shared.updateSession(newSession)
            await refreshUserInfo()
        }
        AppLog.write("AUTH login success cookies=\(newSession.cookies.count) tokenLen=\(newSession.xTTToken.count)")
    }
}
