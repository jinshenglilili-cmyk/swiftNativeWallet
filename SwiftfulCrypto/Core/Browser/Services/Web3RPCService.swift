//
//  Web3RPCService.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import Foundation
import Combine
import WalletCore

typealias RPCId = Int

/// JSON-RPC service handling requests from DApp.
/// 薄壳：消息签名与交易构造转发给共享的 EthereumSigningService，
/// 只读请求转发给 EthRPCClient（真 POST）。
class Web3RPCService: ObservableObject {
    // MARK: - Published
    @Published var responseToSend: String?

    // MARK: - Dependencies
    weak var profileViewModel: ProfileViewModel?
    /// 兼容保留：优先取 profileViewModel.selectedAccount
    var selectedAccount: AccountModel?
    private let signing: EthereumSigningService

    // MARK: - Pending requests waiting for approval
    private var pendingRequests: [Int: (PendingRequest, (Bool) -> Void)] = [:]

    init(profileViewModel: ProfileViewModel?) {
        self.profileViewModel = profileViewModel
        self.signing = EthereumSigningService(profileViewModel: profileViewModel)
    }

    // MARK: - Public: Handle incoming RPC

    func handleIncomingRPC(
        jsonString: String,
        onNeedsApproval: @escaping (Bool, PendingRequest?) -> Void
    ) throws {
        // 每次请求时同步最新选中账号
        selectedAccount = profileViewModel?.selectedAccount

        // Parse JSON-RPC
        guard let data = jsonString.data(using: .utf8) else {
            print("🌐 [Web3RPC] Invalid JSON encoding")
            return
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let method = json?["method"] as? String else {
            print("🌐 [Web3RPC] Missing method in RPC request")
            return
        }

        let params = json?["params"]
        let id = json?["id"] as? Int ?? 0

        print("🌐 [Web3RPC] Received method: \(method), id: \(id)")

        // Check if this method requires user approval
        if requiresApproval(method: method) {
            print("🌐 [Web3RPC] Method \(method) requires user approval, showing approval dialog...")
            let pending = PendingRequest(
                id: UUID().uuidString,
                method: method,
                parameters: params,
                chainId: String(getCurrentChainId()),
                requestId: id
            )
            pendingRequests[id] = (pending, { [weak self] approved in
                self?.handleRequestResponse(id: id, method: method, params: params, approved: approved)
            })
            onNeedsApproval(true, pending)
            return
        }

        // No approval needed, handle directly
        print("🌐 [Web3RPC] Method \(method) no approval needed, handling directly")
        handleDirectRequest(method: method, params: params, id: id)
    }

    /// Approve a pending request after user confirmation
    func approveRequest(requestId: Int) {
        guard let (request, callback) = pendingRequests[requestId] else { return }
        callback(true)
        pendingRequests.removeValue(forKey: requestId)
    }

    /// Reject a pending request after user rejection
    func rejectRequest(requestId: Int) {
        guard let (request, callback) = pendingRequests[requestId] else { return }
        callback(false)
        pendingRequests.removeValue(forKey: requestId)
        sendErrorResponse(id: requestId, message: "User rejected the request")
    }

    // MARK: - Request classification

    private func requiresApproval(method: String) -> Bool {
        switch method {
        case "eth_requestAccounts",
             "eth_requestPermissions",
             "personal_sign",
             "eth_sign",
             "eth_signTypedData",
             "eth_signTypedData_v4",
             "eth_sendTransaction",
             "eth_signTransaction":
            return true
        default:
            return false
        }
    }

    // MARK: - Handle direct requests (no approval needed)

    private func handleDirectRequest(method: String, params: Any?, id: Int) {
        switch method {
        case "eth_accounts":
            handleEthAccounts(params: params, id: id)
        case "eth_chainId":
            sendSuccessResponse(result: "0x\(String(getCurrentChainId(), radix: 16))", id: id)
        case "net_version":
            sendSuccessResponse(result: getCurrentChainId(), id: id)
        case "eth_coinbase":
            handleCoinbase(params: params, id: id)
        case "eth_blockNumber",
             "eth_call",
             "eth_getBalance",
             "eth_gasPrice",
             "eth_estimateGas",
             "eth_getTransactionByHash",
             "eth_getBlockByNumber",
             "eth_getLogs":
            forwardToRPC(method: method, params: params, id: id)
        default:
            print("Unhandled RPC method: \(method)")
            sendErrorResponse(id: id, message: "Method not supported: \(method)")
        }
    }

    // MARK: - Handle approved requests

    private func handleRequestResponse(id: Int, method: String, params: Any?, approved: Bool) {
        guard approved else {
            sendErrorResponse(id: id, message: "User rejected")
            return
        }

        guard let account = selectedAccount else {
            sendErrorResponse(id: id, message: "No account selected. Please create or import an account first.")
            return
        }

        switch method {
        case "eth_requestAccounts":
            handleEthRequestAccounts(params: params, id: id)
        case "personal_sign", "eth_sign":
            handlePersonalSign(params: params, account: account, id: id)
        case "eth_signTypedData", "eth_signTypedData_v4":
            handleSignTypedData(params: params, account: account, id: id)
        case "eth_sendTransaction":
            handleSendTransaction(params: params, account: account, id: id)
        case "eth_signTransaction":
            // 只签名不广播存在钓鱼风险（可被任意 dApp 重放），主流钱包同样拒绝
            sendErrorResponse(id: id, message: "eth_signTransaction is not supported. Please use eth_sendTransaction.")
        default:
            sendErrorResponse(id: id, message: "Unsupported method after approval: \(method)")
        }
    }

    // MARK: - Specific method implementations

    private func handleEthRequestAccounts(params: Any?, id: Int) {
        if let address = selectedAccount?.address {
            let result = ["\(formatAddressHex(address))"]
            sendSuccessResponse(result: result, id: id)
        } else {
            sendSuccessResponse(result: [], id: id)
        }
    }

    private func handleEthAccounts(params: Any?, id: Int) {
        if let address = selectedAccount?.address {
            let result = ["\(formatAddressHex(address))"]
            sendSuccessResponse(result: result, id: id)
        } else {
            sendSuccessResponse(result: [], id: id)
        }
    }

    private func handleCoinbase(params: Any?, id: Int) {
        if let address = selectedAccount?.address {
            sendSuccessResponse(result: formatAddressHex(address), id: id)
        } else {
            sendSuccessResponse(result: nil, id: id)
        }
    }

    // MARK: - Signing methods（转发共享签名层）

    private func handlePersonalSign(params: Any?, account: AccountModel, id: Int) {
        // personal_sign expects: [message, address]
        guard let paramsArray = params as? [Any],
              paramsArray.count >= 2,
              let messageHex = paramsArray[0] as? String else {
            sendErrorResponse(id: id, message: "Invalid parameters or no selected account")
            return
        }

        signing.personalSign(messageHex: messageHex, account: account) { [weak self] result in
            self?.sendResponse(result: result, id: id)
        }
    }

    private func handleSignTypedData(params: Any?, account: AccountModel, id: Int) {
        // eth_signTypedData(_v4) expects: [address, typedDataJSON]
        guard let paramsArray = params as? [Any],
              paramsArray.count >= 2,
              let typedDataJSON = paramsArray[1] as? String else {
            sendErrorResponse(id: id, message: "Invalid parameters or no selected account")
            return
        }

        signing.signTypedData(typedDataJSON: typedDataJSON, account: account) { [weak self] result in
            self?.sendResponse(result: result, id: id)
        }
    }

    private func handleSendTransaction(params: Any?, account: AccountModel, id: Int) {
        guard let paramsArray = params as? [Any],
              let txJSON = paramsArray.first,
              let tx = WCTransaction(json: txJSON) else {
            sendErrorResponse(id: id, message: "Invalid transaction parameters")
            return
        }

        guard let chainId = account.chain.eip155ChainId else {
            sendErrorResponse(id: id, message: "Current chain does not support Ethereum transactions")
            return
        }

        signing.sendTransaction(tx, account: account, chainId: chainId) { [weak self] result in
            self?.sendResponse(result: result, id: id)
        }
    }

    // MARK: - Forwarding read-only requests to RPC endpoint

    private func forwardToRPC(method: String, params: Any?, id: Int) {
        let chainId = getCurrentChainId()
        let paramsArray = (params as? [Any]) ?? []

        Task {
            do {
                let result = try await EthRPCClient.shared.call(chainId: chainId, method: method, params: paramsArray)
                await MainActor.run {
                    self.sendSuccessResponse(result: result, id: id)
                }
            } catch {
                await MainActor.run {
                    self.sendErrorResponse(id: id, message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Helpers

    private func getCurrentChainId() -> Int {
        // Map ChainType to EIP-155 chain ID
        guard let chain = selectedAccount?.chain else {
            return 1 // Default to Ethereum mainnet
        }
        return chain.eip155ChainId ?? 1
    }

    private func formatAddressHex(_ address: String) -> String {
        // Ensure address has 0x prefix
        if address.lowercased().starts(with: "0x") {
            return address
        }
        return "0x\(address)"
    }

    // MARK: - Response sending

    /// 共享签名层 Result → JSON-RPC 响应
    private func sendResponse(result: Result<String, Error>, id: Int) {
        switch result {
        case .success(let value):
            sendSuccessResponse(result: value, id: id)
        case .failure(let error):
            sendErrorResponse(id: id, message: error.localizedDescription)
        }
    }

    private func sendSuccessResponse(result: Any?, id: Int) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result ?? NSNull()
        ]
        sendResponse(response: response)
    }

    private func sendErrorResponse(id: Int, message: String) {
        let error: [String: Any] = [
            "code": -32000,
            "message": message
        ]
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": error
        ]
        sendResponse(response: response)
    }

    private func sendResponse(response: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: response, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                responseToSend = jsonString
            }
        } catch {
            print("Failed to serialize JSON-RPC response: \(error)")
        }
    }
}

extension String {
    /// Remove 0x prefix from hex string if present
    func stripHexPrefix() -> String {
        if lowercased().hasPrefix("0x") {
            return String(dropFirst(2))
        }
        return self
    }
}
