//
//  PendingRequest.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import Foundation

/// JSON-RPC request pending user approval
struct PendingRequest: Identifiable {
    let id: String
    let method: String
    let parameters: Any?
    let chainId: Int?
    let requestId: Int

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
}
