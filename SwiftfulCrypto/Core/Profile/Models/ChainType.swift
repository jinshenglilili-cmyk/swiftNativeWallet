//
//  ChainType.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import Foundation
import WalletCore

enum ChainType: CaseIterable, Identifiable, Codable {
    case bitcoin
    case ethereum
    case solana
    case tron
    case bsc
    case avalanche
    case polygon

    var id: String {
        return name
    }

    var name: String {
        switch self {
        case .bitcoin: return "Bitcoin (BTC)"
        case .ethereum: return "Ethereum (ETH)"
        case .solana: return "Solana (SOL)"
        case .tron: return "Tron (TRX)"
        case .bsc: return "BNB Smart Chain (BSC)"
        case .avalanche: return "Avalanche (AVAX)"
        case .polygon: return "Polygon (MATIC)"
        }
    }

    var coinType: CoinType {
        switch self {
        case .bitcoin: return .bitcoin
        case .ethereum: return .ethereum
        case .solana: return .solana
        case .tron: return .tron
        case .bsc: return .smartChain
        case .avalanche: return .avalancheCChain
        case .polygon: return .polygon
        }
    }

    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .solana: return "SOL"
        case .tron: return "TRX"
        case .bsc: return "BNB"
        case .avalanche: return "AVAX"
        case .polygon: return "MATIC"
        }
    }
}
