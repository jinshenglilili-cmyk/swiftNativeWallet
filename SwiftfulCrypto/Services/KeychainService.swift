//
//  KeychainService.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/12.
//

import Foundation
import Security
import LocalAuthentication

// Keychain 封装：用于存储账号数据（含助记词/私钥等敏感信息）。
// 相比 UserDefaults（明文 plist），Keychain 由系统加密、硬件绑定，
// 并使用 ThisDeviceOnly 策略——数据不随备份迁移到其他设备。
enum KeychainService {

    private static let service = "com.yournamehere.SwiftfulCrypto"

    // MARK: - Public

    static func save(_ data: Data, forKey key: String) -> Bool {
        // 先尝试删除旧值，避免 duplicate item 错误
        delete(forKey: key)

        var query: [String: Any] = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        // 解锁即可读，但不随备份迁移（钱包场景：防止密钥随备份被复制到他人设备）
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
        return status == errSecSuccess
    }

    static func load(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        }
        if status != errSecItemNotFound {
            print("Keychain load error: \(status)")
        }
        return nil
    }

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private static func baseQuery(forKey key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

// 生物识别验证服务：所有读取 Keychain 中私钥的敏感操作
// （DApp 签名、导出私钥）都必须先通过这里验证
enum BiometricAuthService {

    static var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// 发起生物识别验证。
    /// - Parameters:
    ///   - success: 验证是否通过
    ///   - errorMessage: 失败原因；用户主动取消时为 nil（调用方应静默处理）
    static func authenticate(reason: String, completion: @escaping (_ success: Bool, _ errorMessage: String?) -> Void) {
        let context = LAContext()
        var authError: NSError?

        // 设备不支持或未录入生物识别时提前失败，不弹系统窗
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            completion(false, "设备未开启生物识别（Face ID / Touch ID），无法执行此操作。请在系统设置中先录入。")
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(true, nil)
                } else if let error = error {
                    switch (error as? LAError)?.code {
                    case .userCancel, .userFallback, .systemCancel, .appCancel:
                        completion(false, nil) // 用户主动取消，不提示
                    case .biometryLockout:
                        completion(false, "生物识别已锁定，请用锁屏密码解锁后再试。")
                    default:
                        completion(false, "验证失败：\(error.localizedDescription)")
                    }
                } else {
                    completion(false, "验证失败")
                }
            }
        }
    }
}
