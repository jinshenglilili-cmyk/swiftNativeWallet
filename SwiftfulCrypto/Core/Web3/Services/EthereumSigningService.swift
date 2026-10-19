//
//  EthereumSigningService.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation
import WalletCore

/// 以太坊系签名服务：浏览器（Web3RPCService）与 WalletConnect 两端共用的唯一实现。
/// 读取私钥统一走 ProfileViewModel.requestPrivateKey（强制生物识别）。
final class EthereumSigningService {

    // MARK: - Errors

    enum SigningError: LocalizedError {
        case noAccountStorage
        case keyNotAvailable(String)
        case unsupportedChain(ChainType)
        case invalidHex(field: String)
        case signingFailed(String)
        case rpcFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAccountStorage:
                return "账号存储不可用"
            case .keyNotAvailable(let reason):
                return reason
            case .unsupportedChain(let chain):
                return "暂不支持在 \(chain.name) 上执行此操作"
            case .invalidHex(let field):
                return "无效的 hex 数据: \(field)"
            case .signingFailed(let message):
                return "签名失败: \(message)"
            case .rpcFailed(let message):
                return "网络请求失败: \(message)"
            }
        }
    }

    // MARK: - Dependencies

    private weak var profileViewModel: ProfileViewModel?

    init(profileViewModel: ProfileViewModel?) {
        self.profileViewModel = profileViewModel
    }

    // MARK: - 消息签名（personal_sign / eth_sign）

    /// 对 hex 编码消息做 personal_sign 签名（EIP-191，EthereumMessageSigner 内部加前缀）
    func personalSign(messageHex: String, account: AccountModel, completion: @escaping (Result<String, Error>) -> Void) {
        // dApp 传来的是 hex 编码的消息，解码为明文（EIP-191 前缀由 signer 内部添加）
        guard let messageData = Data(hexString: messageHex.stripHexPrefix()),
              let message = String(data: messageData, encoding: .utf8) else {
            completion(.failure(SigningError.invalidHex(field: "message")))
            return
        }

        requestKey(account: account) { key, failure in
            guard let privateKey = key else {
                completion(.failure(SigningError.keyNotAvailable(failure ?? "用户取消验证")))
                return
            }
            let signature = EthereumMessageSigner.signMessage(privateKey: privateKey, message: message)
            completion(.success(Self.ensureHexPrefix(signature)))
        }
    }

    /// EVM 生态的签名结果统一带 0x 前缀（WalletCore 返回的是裸 hex）；
    /// SIWE / dApp 端校验按 ethers 习惯要求 0x 开头
    static func ensureHexPrefix(_ hex: String) -> String {
        hex.hasPrefix("0x") ? hex : "0x" + hex
    }

    /// eth_signTypedData(_v4)：对 EIP-712 结构化数据签名
    func signTypedData(typedDataJSON: String, account: AccountModel, completion: @escaping (Result<String, Error>) -> Void) {
        requestKey(account: account) { key, failure in
            guard let privateKey = key else {
                completion(.failure(SigningError.keyNotAvailable(failure ?? "用户取消验证")))
                return
            }
            let signature = EthereumMessageSigner.signTypedMessage(privateKey: privateKey, messageJson: typedDataJSON)
            completion(.success(Self.ensureHexPrefix(signature)))
        }
    }

    // MARK: - 交易签名与广播（eth_sendTransaction）

    /// 完整交易流程：取链上参数（nonce/gas/fee）→ WalletCore 签名 → eth_sendRawTransaction 广播
    /// - Parameters:
    ///   - tx: dApp 传来的交易参数
    ///   - chainId: EIP-155 链 ID（决定 RPC 端点与 replay 保护）
    func sendTransaction(_ tx: WCTransaction, account: AccountModel, chainId: Int, completion: @escaping (Result<String, Error>) -> Void) {
        guard account.chain.isEVM else {
            completion(.failure(SigningError.unsupportedChain(account.chain)))
            return
        }

        requestKey(account: account) { [weak self] key, failure in
            guard let self = self else { return }
            guard let privateKey = key else {
                completion(.failure(SigningError.keyNotAvailable(failure ?? "用户取消验证")))
                return
            }

            Task {
                do {
                    let hash = try await self.signAndBroadcast(tx: tx, privateKey: privateKey, chainId: chainId, coinType: account.chain.coinType)
                    await MainActor.run { completion(.success(hash)) }
                } catch {
                    await MainActor.run { completion(.failure(error)) }
                }
            }
        }
    }

    /// 签名 + 广播（在后台线程执行网络取参与签名）
    private func signAndBroadcast(tx: WCTransaction, privateKey: PrivateKey, chainId: Int, coinType: CoinType) async throws -> String {
        let client = EthRPCClient.shared

        // 1. nonce：dApp 已提供则用，否则查 pending 交易数
        let nonceData: Data
        if let nonceHex = tx.nonceHex {
            nonceData = EthRPCClient.bigEndianData(hexQuantity: nonceHex)
        } else {
            let nonce = try await client.getTransactionCount(address: coinType.deriveAddress(privateKey: privateKey), chainId: chainId)
            nonceData = EthRPCClient.bigEndianData(nonce)
        }

        // 2. gas limit：dApp 已提供则用，否则估算（失败回退 21000）
        let gasLimitData: Data
        if let gasHex = tx.gasHex {
            gasLimitData = EthRPCClient.bigEndianData(hexQuantity: gasHex)
        } else {
            let gas = (try? await client.estimateGas(tx: tx, chainId: chainId)) ?? 21_000
            gasLimitData = EthRPCClient.bigEndianData(gas)
        }

        // 3. 费用模式：dApp 指定 1559 字段 → enveloped；否则探测 RPC 是否支持 1559，
        //    不支持回退 legacy（BSC 部分节点、旧网关场景）
        let basePrice = (try? await client.gasPrice(chainId: chainId)) ?? 1_000_000_000

        var maxFeePerGasData: Data?
        var maxTipPerGasData: Data?
        var gasPriceData: Data?

        if let maxFeeHex = tx.maxFeePerGasHex {
            maxFeePerGasData = EthRPCClient.bigEndianData(hexQuantity: maxFeeHex)
            maxTipPerGasData = tx.maxPriorityFeePerGasHex.map { EthRPCClient.bigEndianData(hexQuantity: $0) } ?? EthRPCClient.bigEndianData(basePrice / 10)
        } else if tx.gasPriceHex == nil,
                  let rpcTip = try? await client.maxPriorityFeePerGas(chainId: chainId) {
            // RPC 支持 EIP-1559：maxFee = gasPrice * 2，tip = RPC 建议
            maxFeePerGasData = EthRPCClient.bigEndianData(basePrice * 2)
            maxTipPerGasData = EthRPCClient.bigEndianData(rpcTip)
        } else {
            gasPriceData = tx.gasPriceHex.map { EthRPCClient.bigEndianData(hexQuantity: $0) } ?? EthRPCClient.bigEndianData(basePrice)
        }

        // 4. 构造 WalletCore 签名输入
        let valueData = tx.valueHex.map { EthRPCClient.bigEndianData(hexQuantity: $0) } ?? Data()
        let callData = tx.dataHex.flatMap { Data(hexString: $0.stripHexPrefix()) } ?? Data()

        let payload: TW_Ethereum_Proto_Transaction.OneOf_TransactionOneof
        if callData.isEmpty {
            payload = .transfer(TW_Ethereum_Proto_Transaction.Transfer.with {
                $0.amount = valueData
                $0.data = Data()
            })
        } else {
            payload = .contractGeneric(TW_Ethereum_Proto_Transaction.ContractGeneric.with {
                $0.amount = valueData
                $0.data = callData
            })
        }

        let input = TW_Ethereum_Proto_SigningInput.with {
            $0.chainID = EthRPCClient.bigEndianData(UInt64(chainId))
            $0.nonce = nonceData
            $0.gasLimit = gasLimitData
            $0.toAddress = tx.to
            $0.privateKey = privateKey.data
            $0.transaction = TW_Ethereum_Proto_Transaction.with { $0.transactionOneof = payload }
            if let maxFee = maxFeePerGasData, let tip = maxTipPerGasData {
                $0.txMode = .enveloped
                $0.maxFeePerGas = maxFee
                $0.maxInclusionFeePerGas = tip
            } else {
                $0.txMode = .legacy
                $0.gasPrice = gasPriceData ?? EthRPCClient.bigEndianData(basePrice)
            }
        }

        // 5. 签名
        let output: TW_Ethereum_Proto_SigningOutput = AnySigner.sign(input: input, coin: coinType)
        guard output.error == .ok else {
            throw SigningError.signingFailed(output.errorMessage.isEmpty ? "\(output.error)" : output.errorMessage)
        }

        // 6. 广播
        do {
            let hash = try await client.sendRawTransaction(rawTxHex: output.encoded.hexString, chainId: chainId)
            return hash
        } catch {
            throw SigningError.rpcFailed(error.localizedDescription)
        }
    }

    // MARK: - 私钥读取（统一生物识别入口）

    /// 通过生物识别读取私钥；失败/取消时返回 nil 并携带具体原因
    private func requestKey(account: AccountModel, completion: @escaping (PrivateKey?, String?) -> Void) {
        guard let profileViewModel = profileViewModel else {
            completion(nil, "签名服务未关联账号数据")
            return
        }

        profileViewModel.requestPrivateKey(account: account, reason: "验证身份后对请求进行签名") { keyHex, failure in
            guard let keyHex = keyHex,
                  let keyData = Data(hexString: keyHex.stripHexPrefix()),
                  let privateKey = PrivateKey(data: keyData) else {
                completion(nil, failure ?? "私钥数据无效")
                return
            }
            completion(privateKey, nil)
        }
    }
}
