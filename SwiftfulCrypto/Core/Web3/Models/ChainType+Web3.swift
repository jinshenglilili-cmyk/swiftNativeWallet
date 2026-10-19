//
//  ChainType+Web3.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation

extension ChainType {

    /// 是否为 EVM 系链（可参与 WalletConnect eip155 会话与以太坊签名流程）
    var isEVM: Bool {
        switch self {
        case .ethereum, .bsc, .avalanche, .polygon:
            return true
        case .bitcoin, .solana, .tron:
            return false
        }
    }

    /// EIP-155 链 ID；非 EVM 链返回 nil
    var eip155ChainId: Int? {
        switch self {
        case .ethereum: return 1
        case .bsc: return 56
        case .polygon: return 137
        case .avalanche: return 43114
        case .bitcoin, .solana, .tron: return nil
        }
    }
}
