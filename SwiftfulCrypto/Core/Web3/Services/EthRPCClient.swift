//
//  EthRPCClient.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation

/// JSON-RPC 客户端：真正以 POST 发送请求体。
/// 取代 Web3RPCService 里复用 GET 语义 NetworkingManager.download 的旧转发逻辑；
/// 浏览器与 WalletConnect 两端共用。
final class EthRPCClient {

    static let shared = EthRPCClient()

    // MARK: - Public RPC endpoints（单一来源，从 Web3RPCService 迁出）
    let endpoints: [Int: String] = [
        1: "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161", // Ethereum
        56: "https://bsc-dataseed.binance.org/", // BSC
        43114: "https://api.avax.network/ext/bc/C/rpc", // Avalanche
        137: "https://polygon-rpc.com/", // Polygon
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Errors

    enum RPCError: LocalizedError {
        case noEndpoint(chainId: Int)
        case invalidResponse
        case rpcError(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .noEndpoint(let chainId):
                return "未配置链 ID \(chainId) 的 RPC 端点"
            case .invalidResponse:
                return "RPC 返回了无法解析的响应"
            case .rpcError(let code, let message):
                return "RPC 错误(\(code)): \(message)"
            }
        }
    }

    // MARK: - Core call

    /// 发送一次 JSON-RPC POST 请求，返回 result 或抛出 error
    func call(chainId: Int, method: String, params: [Any]) async throws -> Any {
        guard let endpointString = endpoints[chainId], let url = URL(string: endpointString) else {
            throw RPCError.noEndpoint(chainId: chainId)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...1_000_000),
            "method": method,
            "params": params,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw RPCError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError.invalidResponse
        }

        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? Int,
           let message = error["message"] as? String {
            throw RPCError.rpcError(code: code, message: message)
        }

        guard json["error"] == nil else {
            throw RPCError.invalidResponse
        }

        // result 为 NSNull 时原样返回（如 wallet_switchEthereumChain 成功响应）
        return json["result"] ?? NSNull()
    }

    // MARK: - 高层封装

    /// eth_getTransactionCount（pending，包含待确认交易占用的 nonce）
    func getTransactionCount(address: String, chainId: Int) async throws -> UInt64 {
        let result = try await call(
            chainId: chainId,
            method: "eth_getTransactionCount",
            params: [address.lowercased(), "pending"]
        )
        return Self.parseHexQuantity(result) ?? 0
    }

    /// eth_gasPrice
    func gasPrice(chainId: Int) async throws -> UInt64 {
        let result = try await call(chainId: chainId, method: "eth_gasPrice", params: [])
        guard let price = Self.parseHexQuantity(result), price > 0 else {
            throw RPCError.invalidResponse
        }
        return price
    }

    /// eth_maxPriorityFeePerGas：部分公共 RPC 不支持（返回错误）→ 抛错，调用方回退 legacy 模式
    func maxPriorityFeePerGas(chainId: Int) async throws -> UInt64 {
        let result = try await call(chainId: chainId, method: "eth_maxPriorityFeePerGas", params: [])
        guard let tip = Self.parseHexQuantity(result) else {
            throw RPCError.invalidResponse
        }
        return tip
    }

    /// eth_estimateGas；失败回退 21000（标准转账所需 gas）
    func estimateGas(tx: WCTransaction, chainId: Int) async throws -> UInt64 {
        var callObject: [String: Any] = ["to": tx.to.lowercased()]
        if let from = tx.from { callObject["from"] = from.lowercased() }
        if let valueHex = tx.valueHex { callObject["value"] = valueHex }
        if let dataHex = tx.dataHex { callObject["data"] = dataHex }

        let result = try await call(
            chainId: chainId,
            method: "eth_estimateGas",
            params: [callObject, "latest"]
        )
        guard let gas = Self.parseHexQuantity(result), gas > 0 else {
            return 21_000
        }
        return gas
    }

    /// eth_sendRawTransaction，返回交易 hash
    func sendRawTransaction(rawTxHex: String, chainId: Int) async throws -> String {
        let result = try await call(
            chainId: chainId,
            method: "eth_sendRawTransaction",
            params: [rawTxHex.hasPrefix("0x") ? rawTxHex : "0x" + rawTxHex]
        )
        guard let hash = result as? String, !hash.isEmpty else {
            throw RPCError.invalidResponse
        }
        return hash
    }

    // MARK: - Hex helpers

    /// 解析 hex quantity（"0x1a" / "0x0" / 纯十进制数字符串）
    static func parseHexQuantity(_ value: Any?) -> UInt64? {
        guard let string = value as? String else { return nil }
        if string.lowercased().hasPrefix("0x") {
            let hex = String(string.dropFirst(2))
            return UInt64(hex, radix: 16)
        }
        return UInt64(string)
    }

    /// hex quantity → 最小大端字节（uint256 序列化；0 编码为空 Data，符合 RLP 语义）
    static func bigEndianData(hexQuantity: String) -> Data {
        guard let value = parseHexQuantity(hexQuantity), value > 0 else {
            return Data()
        }
        return bigEndianData(value)
    }

    /// UInt64 → 最小大端字节
    static func bigEndianData(_ value: UInt64) -> Data {
        guard value > 0 else { return Data() }
        var bytes: [UInt8] = []
        var v = value
        while v > 0 {
            bytes.insert(UInt8(truncatingIfNeeded: v), at: 0)
            v >>= 8
        }
        return Data(bytes)
    }
}
