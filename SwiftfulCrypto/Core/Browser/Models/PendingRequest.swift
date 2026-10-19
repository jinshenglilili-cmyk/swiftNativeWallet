//
//  PendingRequest.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import Foundation
import WalletCore

/// JSON-RPC request pending user approval
/// 浏览器（DApp Browser）与 WalletConnect 两端共用的审批请求模型
struct PendingRequest: Identifiable {
    let id: String
    let method: String
    let parameters: Any?
    /// 链标识：浏览器端为 EIP-155 数字字符串（"1"），WalletConnect 端为 CAIP-2（"eip155:1"）
    let chainId: String?
    let requestId: Int
    /// 请求来源（WalletConnect 会话中为 dApp 信息，浏览器端为 nil）
    var dAppName: String?
    var dAppIconURL: String?

    init(id: String,
         method: String,
         parameters: Any?,
         chainId: String? = nil,
         requestId: Int,
         dAppName: String? = nil,
         dAppIconURL: String? = nil) {
        self.id = id
        self.method = method
        self.parameters = parameters
        self.chainId = chainId
        self.requestId = requestId
        self.dAppName = dAppName
        self.dAppIconURL = dAppIconURL
    }

    var displayName: String {
        switch method {
        case "eth_requestAccounts":
            return "Connect Wallet"
        case "personal_sign", "eth_sign":
            return "Sign Message"
        case "eth_signTypedData", "eth_signTypedData_v4":
            return "Sign Typed Data"
        case "eth_sendTransaction":
            return "Send Transaction"
        case "eth_signTransaction":
            return "Sign Transaction"
        default:
            return method
        }
    }

    var description: String {
        switch method {
        case "eth_requestAccounts":
            return "Allow this site to connect to your wallet?"
        case "personal_sign":
            return "Allow this site to sign a message?"
        case "eth_sendTransaction":
            return "Approves this transaction for sending?"
        default:
            return "Approve this request?"
        }
    }

    /// eth_sendTransaction 的人类可读摘要（收款地址 + 金额 + data）
    var transactionSummary: [String: String]? {
        guard method == "eth_sendTransaction",
              let params = parameters as? [Any],
              let dict = params.first as? [String: Any] else { return nil }

        var summary: [String: String] = [:]
        if let to = dict["to"] as? String { summary["to"] = to }
        if let value = dict["value"] as? String { summary["value"] = value }
        if let data = dict["data"] as? String, data.stripHexPrefix().count > 0 {
            summary["data"] = data
        }
        return summary.isEmpty ? nil : summary
    }

    /// 待签消息（personal_sign / eth_sign 的 hex 消息，解码为明文展示）
    var messagePreview: String? {
        guard let params = parameters as? [Any],
              let first = params.first as? String else { return nil }

        // wc_sessionAuthenticate（SIWE 登录）：params[0] 即明文消息
        if method == "wc_sessionAuthenticate" {
            return first
        }

        guard method == "personal_sign" || method == "eth_sign" else { return nil }

        if let data = Data(hexString: first.stripHexPrefix()),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return first
    }
}
