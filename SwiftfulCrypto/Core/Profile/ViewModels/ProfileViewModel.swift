//
//  ProfileViewModel.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import Foundation
import Combine
import WalletCore

class ProfileViewModel: ObservableObject {

    @Published var accounts: [AccountModel] = []
    @Published var selectedAccount: AccountModel?
    @Published var showAddAccount: Bool = false
    @Published var showAccountSelector: Bool = false

    private let cancellables = CancelBag()
    // 账号数据（含助记词/私钥）存 Keychain，不再用 UserDefaults（明文 plist）
    private let keychainKey = "savedAccounts"
    private let legacyUserDefaultsKey = "savedAccounts"

    init() {
        loadAccounts()
    }

    func addAccount(name: String, address: String, chain: ChainType, mnemonic: String? = nil, privateKeyHex: String? = nil) {
        let account = AccountModel(name: name, address: address, chain: chain, mnemonic: mnemonic, privateKeyHex: privateKeyHex)
        accounts.append(account)
        // 新添加的账号自动成为默认选中
        selectedAccount = account
        saveAccounts()
    }

    func deleteAccount(account: AccountModel) {
        accounts.removeAll { $0.id == account.id }

        if selectedAccount?.id == account.id {
            selectedAccount = accounts.last
        }

        if accounts.isEmpty {
            selectedAccount = nil
        }

        saveAccounts()
    }

    func selectAccount(account: AccountModel) {
        selectedAccount = account
        showAccountSelector = false
        saveAccounts()
    }

    // MARK: - WalletCore Helpers (WalletCore 4.7.0 API)

    static func generateAddressFromMnemonic(mnemonic: String, chain: ChainType) -> String? {
        let coinType = chain.coinType

        // Validate mnemonic
        if !Mnemonic.isValid(mnemonic: mnemonic) {
            return nil
        }

        // Generate HD wallet from mnemonic
        guard let hdWallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            return nil
        }

        // Create standard BIP-44 derivation path
        let pathString = "m/44'/\(coinType.rawValue)'/0'/0/0"

        // Get private key
        let privateKey = hdWallet.getKey(coin: coinType, derivationPath: pathString)

        // Derive address directly using CoinType
        return coinType.deriveAddress(privateKey: privateKey)
    }

    static func generateAddressFromPrivateKey(privateKeyHex: String, chain: ChainType) -> String? {
        guard let privateKeyData = Data(hexString: privateKeyHex) else {
            return nil
        }
        let coinType = chain.coinType

        if !PrivateKey.isValid(data: privateKeyData, curve: coinType.curve) {
            return nil
        }

        guard let privateKey = PrivateKey(data: privateKeyData) else {
            return nil
        }

        return coinType.deriveAddress(privateKey: privateKey)
    }

    static func generateMnemonic() -> String {
        // Generate a new random HD wallet with 128 bits entropy (12 words)
        let hdWallet = HDWallet(strength: 128, passphrase: "")
        return hdWallet?.mnemonic ?? ""
    }

    // 导出私钥：助记词账号按创建时的 BIP-44 路径派生该链私钥
    static func privateKeyFromMnemonic(mnemonic: String, chain: ChainType) -> String? {
        guard Mnemonic.isValid(mnemonic: mnemonic),
              let hdWallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            return nil
        }
        let pathString = "m/44'/\(chain.coinType.rawValue)'/0'/0/0"
        let privateKey = hdWallet.getKey(coin: chain.coinType, derivationPath: pathString)
        return privateKey.data.hexString
    }

    // 导出私钥统一入口：优先返回导入时保存的私钥，否则从助记词派生
    static func exportPrivateKey(for account: AccountModel) -> String? {
        if let privateKeyHex = account.privateKeyHex, !privateKeyHex.isEmpty {
            return privateKeyHex
        }
        guard let mnemonic = account.mnemonic, !mnemonic.isEmpty else {
            return nil
        }
        return privateKeyFromMnemonic(mnemonic: mnemonic, chain: account.chain)
    }

    // 敏感操作（DApp 签名、导出）读取私钥的唯一入口：
    // 必须先通过生物识别，验证通过才返回私钥；取消/失败返回 nil
    func requestPrivateKey(account: AccountModel, reason: String, completion: @escaping (String?) -> Void) {
        BiometricAuthService.authenticate(reason: reason) { success, _ in
            completion(success ? ProfileViewModel.exportPrivateKey(for: account) : nil)
        }
    }

    private func saveAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            guard KeychainService.save(data, forKey: keychainKey) else {
                print("Error saving accounts to keychain")
                return
            }
            // 迁移完成后清理 UserDefaults 里的旧数据（明文存储不安全）
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
        } catch {
            print("Error saving accounts: \(error)")
        }
    }

    private func loadAccounts() {
        // 优先从 Keychain 读取
        if let data = KeychainService.load(forKey: keychainKey) {
            do {
                accounts = try JSONDecoder().decode([AccountModel].self, from: data)
                selectedAccount = accounts.first
                return
            } catch {
                print("Error loading accounts from keychain: \(error)")
            }
        }

        // 一次性迁移：老版本数据存在 UserDefaults，读到后写入 Keychain 并清理
        if let data = UserDefaults.standard.data(forKey: legacyUserDefaultsKey) {
            do {
                accounts = try JSONDecoder().decode([AccountModel].self, from: data)
                selectedAccount = accounts.first
                saveAccounts() // 写入 Keychain 并清理 UserDefaults
            } catch {
                print("Error migrating legacy accounts: \(error)")
            }
        }
    }
}

// Helper for Combine
class CancelBag {
    var cancellables = Set<AnyCancellable>()
}

extension Set where Element: AnyCancellable {
    mutating func cancelAll() {
        forEach { $0.cancel() }
        removeAll()
    }
}
