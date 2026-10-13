//
//  TransactionModel.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/23.
//

import Foundation

enum TransactionStatus: String, Codable, Identifiable {
    case pending
    case success
    case failed

    var id: String {
        return rawValue
    }

    var displayName: String {
        switch self {
        case .pending: return "处理中"
        case .success: return "成功"
        case .failed: return "失败"
        }
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .success: return "green"
        case .failed: return "red"
        }
    }
}

struct TransactionModel: Identifiable, Codable, Equatable {
    let id: UUID
    let fromAccountId: UUID
    let fromAddress: String
    let toAddress: String
    let amount: Double
    let chain: ChainType
    var status: TransactionStatus
    let createdAt: Date
    var txHash: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fromAccountId
        case fromAddress
        case toAddress
        case amount
        case chain
        case status
        case createdAt
        case txHash
    }

    init(
        id: UUID = UUID(),
        fromAccountId: UUID,
        fromAddress: String,
        toAddress: String,
        amount: Double,
        chain: ChainType,
        status: TransactionStatus = .pending,
        txHash: String? = nil
    ) {
        self.id = id
        self.fromAccountId = fromAccountId
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.amount = amount
        self.chain = chain
        self.status = status
        self.createdAt = Date()
        self.txHash = txHash
    }

    mutating func updateStatus(_ status: TransactionStatus, txHash: String? = nil) {
        self.status = status
        if let txHash = txHash {
            self.txHash = txHash
        }
    }
}
