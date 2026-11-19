import Foundation
import Security

/// 登录会话（会话 Cookie / x-tt-token / 手机号等）的 Keychain 存储。
///
/// 旧版本曾把 `AuthSession` 明文 JSON 写在 UserDefaults
/// （键 `redduoduo.auth.session.v1`）。现采用 Keychain 通用密码项：
/// - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：首次解锁后可读、仅本机、不随 iCloud 钥匙串同步；
/// - 不使用 access group，凭据只属于本 App 沙盒；
/// - 首次读取时自动把旧版 UserDefaults 明文会话迁入 Keychain，并立即删除明文残留。
enum SessionKeychain {
    private static let service = "redduoduo.auth.session"
    private static let account = "v1"

    /// 旧版 UserDefaults 明文键：仅用于一次性迁移，迁移后不再写入。
    static let legacyDefaultsKey = "redduoduo.auth.session.v1"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
            return session
        }
        // 旧版明文迁移：读出后立即清除 UserDefaults 残留，再写入 Keychain。
        if let legacy = UserDefaults.standard.data(forKey: legacyDefaultsKey) {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            if let session = try? JSONDecoder().decode(AuthSession.self, from: legacy) {
                save(session)
                return session
            }
        }
        return nil
    }

    static func save(_ session: AuthSession?) {
        // 无论写入还是登出，都确保旧版明文键不残留。
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        guard let session, let data = try? JSONEncoder().encode(session) else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}