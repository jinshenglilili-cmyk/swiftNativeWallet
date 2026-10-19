//
//  WCDefaultCryptoProvider.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation
import WalletCore
import ReownWalletKit

/// reown-swift 要求的 CryptoProvider，基于 WalletCore 实现（不引入 web3/HDWalletKit）
struct WCDefaultCryptoProvider: CryptoProvider {

    func keccak256(_ data: Data) -> Data {
        Hash.keccak256(data: data)
    }

    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        // WalletCore recover 要求 65 字节紧凑签名：[recid(0/1), r(32), s(32)]
        var compact = Data([signature.v & 0x01])
        compact.append(Data(signature.r))
        compact.append(Data(signature.s))

        guard let publicKey = PublicKey.recover(signature: compact, message: message) else {
            throw CryptoProviderError.recoveryFailed
        }

        // SDK 侧验证用 keccak256(pubKey).suffix(20) 还原地址，要求 64 字节裸公钥
        // （去掉 uncompressed 格式的 0x04 前缀）
        var keyData = publicKey.data
        if keyData.count == 65, keyData.first == 0x04 {
            keyData = keyData.dropFirst()
        }
        return keyData
    }

    enum CryptoProviderError: Error {
        case recoveryFailed
    }
}
