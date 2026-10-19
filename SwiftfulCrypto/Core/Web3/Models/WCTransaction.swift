//
//  WCTransaction.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation

/// dApp 传来的交易参数（eth_sendTransaction params[0]）
/// 所有数值字段均为 hex quantity 字符串（如 "0x2386f26fc10000"）
struct WCTransaction {
    let from: String?
    let to: String
    /// 转账金额（wei，hex）
    let valueHex: String?
    /// 合约调用 data（hex）
    let dataHex: String?
    /// gas 上限（hex）
    let gasHex: String?
    /// legacy gasPrice（hex）
    let gasPriceHex: String?
    /// EIP-1559 最大费用（hex）
    let maxFeePerGasHex: String?
    /// EIP-1559 小费（hex）
    let maxPriorityFeePerGasHex: String?
    /// nonce（hex），dApp 已提供则不再查询
    let nonceHex: String?

    /// 从 JSON-RPC params 解析；缺少 to 地址视为非法请求
    init?(json: Any) {
        guard let dict = json as? [String: Any] else { return nil }

        // to 可能是 "to" 键；大小写不敏感处理由调用方保证
        guard let to = dict["to"] as? String, !to.isEmpty else { return nil }

        self.from = dict["from"] as? String
        self.to = to
        self.valueHex = dict["value"] as? String
        self.dataHex = dict["data"] as? String
        self.gasHex = dict["gas"] as? String ?? dict["gasLimit"] as? String
        self.gasPriceHex = dict["gasPrice"] as? String
        self.maxFeePerGasHex = dict["maxFeePerGas"] as? String
        self.maxPriorityFeePerGasHex = dict["maxPriorityFeePerGas"] as? String
        self.nonceHex = dict["nonce"] as? String
    }

    /// 是否为合约调用（带 data）还是普通转账
    var isContractCall: Bool {
        guard let dataHex = dataHex else { return false }
        return dataHex.stripHexPrefix().count > 0
    }
}
