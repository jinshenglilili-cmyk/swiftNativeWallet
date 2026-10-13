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

/// JSON-RPC service handling requests from DApp
class Web3RPCService: ObservableObject {
    // MARK: - Published
    @Published var responseToSend: String?

    // MARK: - Dependencies
    weak var profileViewModel: ProfileViewModel?
    var selectedAccount: AccountModel?

    // MARK: - Pending requests waiting for approval
    private var pendingRequests: [Int: (PendingRequest, (Bool) -> Void)] = [:]
    private var requestCounter = 0

    // MARK: - Public RPC endpoints
    private let defaultRPCEndpoints: [Int: String] = [
        1: "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161", // Ethereum
        56: "https://bsc-dataseed.binance.org/", // BSC
        43114: "https://api.avax.network/ext/bc/C/rpc", // Avalanche
        137: "https://polygon-rpc.com/", // Polygon
    ]

    init(profileViewModel: ProfileViewModel?) {
        self.profileViewModel = profileViewModel
    }

    // MARK: - Public: Handle incoming RPC

    func handleIncomingRPC(
        jsonString: String,
        onNeedsApproval: @escaping (Bool, PendingRequest?) -> Void
    ) throws {
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
                chainId: getCurrentChainId(),
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
        case "eth_chainId", "net_version":
            handleChainId(params: params, id: id)
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

        switch method {
        case "eth_requestAccounts":
            handleEthRequestAccounts(params: params, id: id)
        case "personal_sign":
            handlePersonalSign(params: params, id: id)
        case "eth_sendTransaction":
            handleSendTransaction(params: params, id: id)
        case "eth_signTransaction":
            handleSignTransaction(params: params, id: id)
        case "eth_signTypedData", "eth_signTypedData_v4":
            handleSignTypedData(params: params, id: id)
        case "eth_sign":
            handleEthSign(params: params, id: id)
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

    private func handleChainId(params: Any?, id: Int) {
        let chainId = getCurrentChainId()
        // Return as hex string for eth_chainId, decimal for net_version
        if let method = getCallingMethodForId(id), method == "eth_chainId" {
            sendSuccessResponse(result: "0x\(String(chainId, radix: 16))", id: id)
        } else {
            sendSuccessResponse(result: chainId, id: id)
        }
    }

    // MARK: - Signing methods

    private func handlePersonalSign(params: Any?, id: Int) {
        // personal_sign expects: [message, address]
        guard let paramsArray = params as? [Any],
              paramsArray.count >= 2,
              let messageHex = paramsArray[0] as? String,
              let _ = paramsArray[1] as? String,
              let account = selectedAccount else {
            sendErrorResponse(id: id, message: "Invalid parameters or no selected account")
            return
        }

        // dApp 传来的是 hex 编码的消息，先解码为明文（EIP-191 前缀由 signer 内部添加）
        guard let messageData = Data(hexString: messageHex.stripHexPrefix()),
              let message = String(data: messageData, encoding: .utf8) else {
            sendErrorResponse(id: id, message: "Invalid message hex")
            return
        }

        signWithBiometric(account: account, id: id) { privateKey in
            let signature = EthereumMessageSigner.signMessage(privateKey: privateKey, message: message)
            self.sendSuccessResponse(result: signature, id: id)
        }
    }

    // 读取 Keychain 中的私钥进行签名前，必须通过生物识别验证；
    // 验证取消/失败时向 dApp 返回错误响应（而不是挂起）
    private func signWithBiometric(account: AccountModel, id: Int, sign: @escaping (PrivateKey) -> Void) {
        guard let profileViewModel = profileViewModel else {
            sendErrorResponse(id: id, message: "Account storage unavailable")
            return
        }

        profileViewModel.requestPrivateKey(account: account, reason: "验证身份后对 DApp 请求进行签名") { keyHex in
            guard let keyHex = keyHex,
                  let keyData = Data(hexString: keyHex.stripHexPrefix()),
                  let privateKey = PrivateKey(data: keyData) else {
                self.sendErrorResponse(id: id, message: "User canceled authentication or private key unavailable")
                return
            }
            sign(privateKey)
        }
    }

    private func handleEthSign(params: Any?, id: Int) {
        // Similar to personal_sign
        handlePersonalSign(params: params, id: id)
    }

    private func handleSignTypedData(params: Any?, id: Int) {
        // eth_signTypedData(_v4) expects: [address, typedDataJSON]
        guard let paramsArray = params as? [Any],
              paramsArray.count >= 2,
              let typedDataJSON = paramsArray[1] as? String,
              let account = selectedAccount else {
            sendErrorResponse(id: id, message: "Invalid parameters or no selected account")
            return
        }

        signWithBiometric(account: account, id: id) { privateKey in
            let signature = EthereumMessageSigner.signTypedMessage(privateKey: privateKey, messageJson: typedDataJSON)
            self.sendSuccessResponse(result: signature, id: id)
        }
    }

    private func handleSendTransaction(params: Any?, id: Int) {
        // TODO: 交易签名需要在读取私钥前同样接入 BiometricAuthService（复用 signWithBiometric），
        // 并构造 EthereumSigningInput 广播；当前仍是占位实现，未读取私钥
        let txHash = "0x\(String(repeating: "a", count: 64))"
        sendSuccessResponse(result: txHash, id: id)
    }

    private func handleSignTransaction(params: Any?, id: Int) {
        // Similar to sendTransaction but returns the signed payload
        let signedTx = "0x\(String(repeating: "b", count: 128))"
        sendSuccessResponse(result: signedTx, id: id)
    }

    // MARK: - Forwarding read-only requests to RPC endpoint

    private func forwardToRPC(method: String, params: Any?, id: Int) {
        guard let rpcURL = getRPCEndpoint() else {
            sendErrorResponse(id: id, message: "No RPC endpoint configured for current chain")
            return
        }

        // Create JSON-RPC request to forward
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params ?? []
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            var urlRequest = URLRequest(url: rpcURL)
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = data
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Use existing NetworkingManager
            NetworkingManager.download(url: rpcURL)
                .sink(
                    receiveCompletion: { completion in
                        NetworkingManager.handleCompletion(completion: completion)
                        if case .failure(let error) = completion {
                            print("RPC forward error: \(error)")
                            self.sendErrorResponse(id: id, message: error.localizedDescription)
                        }
                    },
                    receiveValue: { data in
                        // Just forward the response back to JS
                        if let jsonString = String(data: data, encoding: .utf8) {
                            // Parse to get the result/error and resend
                            self.forwardRPCResponse(data: data, originalId: id)
                        } else {
                            self.sendErrorResponse(id: id, message: "Invalid response from RPC")
                        }
                    }
                )
                .store(in: &cancellables)
        } catch {
            sendErrorResponse(id: id, message: "Failed to serialize request: \(error.localizedDescription)")
        }
    }

    private func forwardRPCResponse(data: Data, originalId: Int) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                sendErrorResponse(id: originalId, message: "Invalid JSON response from RPC")
                return
            }

            if let error = json["error"] {
                sendErrorResponse(id: originalId, message: "\(error)")
                return
            }

            let result = json["result"]
            sendSuccessResponse(result: result as Any, id: originalId)
        } catch {
            sendErrorResponse(id: originalId, message: "Failed to parse RPC response: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func getCurrentChainId() -> Int {
        // Map ChainType to EIP-155 chain ID
        guard let chain = selectedAccount?.chain else {
            return 1 // Default to Ethereum mainnet
        }

        switch chain {
        case .ethereum: return 1
        case .bsc: return 56
        case .avalanche: return 43114
        case .polygon: return 137
        case .bitcoin: return 0
        case .solana: return 101 // Solana mainnet
        case .tron: return 195
        }
    }

    private func getRPCEndpoint() -> URL? {
        let chainId = getCurrentChainId()
        if let endpointString = defaultRPCEndpoints[chainId] {
            return URL(string: endpointString)
        }
        // Fallback to Ethereum
        return URL(string: defaultRPCEndpoints[1]!)
    }

    private func formatAddressHex(_ address: String) -> String {
        // Ensure address has 0x prefix
        if address.lowercased().starts(with: "0x") {
            return address
        }
        return "0x\(address)"
    }

    private func getCallingMethodForId(_ id: Int) -> String? {
        // This is simplified - in a full implementation you'd track method by id
        return nil
    }

    // MARK: - Response sending

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

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()
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
