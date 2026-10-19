//
//  WCUIState.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation

/// WalletConnect 配对/审批流的 UI 状态机
enum WCFlowState: Equatable {
    case idle
    /// URI 已提交，等待 dApp 发起 proposal
    case pairing
    /// proposal 已到达，等待用户在 UI 上批准/拒绝
    case awaitingProposal
    /// 用户已批准，SDK 正在建立会话
    case connecting
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}

/// 会话列表展示模型（从 SDK Session 提取，方便 Preview 与解耦）
struct WCSessionDisplay: Identifiable {
    let id: String            // topic
    let dAppName: String
    let dAppURL: String?
    let dAppIconURL: String?
    let accounts: [String]    // CAIP-10
    let expiryDate: Date?

    var expiryText: String? {
        guard let expiryDate = expiryDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: expiryDate)
    }
}

/// 会话提案展示模型（从 SDK Session.Proposal 提取）
struct WCProposalDisplay: Identifiable {
    let id: String
    let dAppName: String
    let dAppDescription: String?
    let dAppURL: String?
    let dAppIconURL: String?
    /// dApp 提议的链（CAIP-2，如 "eip155:1"）
    let requestedChains: [String]
    /// dApp 声明的方法
    let requestedMethods: [String]

    /// 是否包含本 App 不支持的链（决定是否可批准）
    var hasUnsupportedChain: Bool {
        requestedChains.contains { chain in
            guard let reference = chain.split(separator: ":").last else { return true }
            return !WalletConnectConfig.eip155References.contains(String(reference))
        }
    }
}
