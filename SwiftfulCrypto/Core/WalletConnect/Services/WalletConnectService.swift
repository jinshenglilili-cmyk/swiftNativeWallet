//
//  WalletConnectService.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation
import Combine
import ReownWalletKit

/// WalletConnect 钱包端核心服务：
/// 配对 → 会话提案审批 → 会话请求（签名/交易）→ 响应/断开。
/// 签名与交易全部走共享的 EthereumSigningService（生物识别 + WalletCore）。
@MainActor
final class WalletConnectService: ObservableObject {

    // MARK: - Published

    @Published var flowState: WCFlowState = .idle
    @Published var sessions: [WCSessionDisplay] = []
    /// 非 nil 时弹出会话审批 sheet
    @Published var proposal: WCProposalDisplay?
    /// 非 nil 时弹出签名请求 sheet（复用 SigningRequestView）
    @Published var pendingRequest: PendingRequest?
    /// 非 nil 时弹全局错误提示（审批失败等原因需要立即可见）
    @Published var alertMessage: String?
    /// 「连接 dApp」配对 sheet 是否正在展示：
    /// 配对页内也挂了审批弹窗，根部挂载点在配对页打开期间必须休眠，
    /// 否则两处抢同一绑定会导致审批弹窗闪现后消失
    @Published var pairSheetVisible = false

    // MARK: - Dependencies

    private weak var profileViewModel: ProfileViewModel?
    private let signing: EthereumSigningService

    // MARK: - Private

    private var configured = false
    private var cancellables = Set<AnyCancellable>()
    /// 审批中的 WC 请求：PendingRequest.id → SDK Request（respond 时用）
    private var wcRequests: [String: Request] = [:]
    /// 审批中的 SIWE 认证请求（wc_sessionAuthenticate）：PendingRequest.id → 上下文
    private var authRequests: [String: (request: AuthenticationRequest, payload: AuthPayload, message: String)] = [:]

    init(profileViewModel: ProfileViewModel?) {
        self.profileViewModel = profileViewModel
        self.signing = EthereumSigningService(profileViewModel: profileViewModel)
    }

    // MARK: - 配置与启动

    /// 必须在主线程、App 启动后调用一次；订阅必须在 configure 之后注册才能收到事件
    func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        guard WalletConnectConfig.projectId != "YOUR_PROJECT_ID" else {
            flowState = .error("尚未配置 WalletConnect Project ID（见 WalletConnectConfig.swift 的注册步骤）")
            return
        }

        do {
            let metadata = try WalletConnectConfig.makeMetadata()
            WCBootstrap.configureNetworkingIfNeeded()
            WalletKit.configure(metadata: metadata, crypto: WCDefaultCryptoProvider())
        } catch {
            flowState = .error("WalletConnect 初始化失败: \(error.localizedDescription)")
            return
        }

        WalletKit.instance.sessionProposalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handleProposal(payload.proposal)
            }
            .store(in: &cancellables)

        WalletKit.instance.sessionRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handleSessionRequest(payload.request)
            }
            .store(in: &cancellables)
        // wise 签名请求
        WalletKit.instance.authenticateRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handleAuthRequest(payload.request)
            }
            .store(in: &cancellables)

        WalletKit.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSessions()
            }
            .store(in: &cancellables)

        WalletKit.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSessions()
            }
            .store(in: &cancellables)

        // 账号删除 → 断开包含该地址的会话（权限不应残留）
        NotificationCenter.default.publisher(for: .wcAccountDeleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let address = note.userInfo?["address"] as? String else { return }
                self?.disconnectSessions(containing: address)
            }
            .store(in: &cancellables)

        refreshSessions()
    }

    // MARK: - 配对

    func pair(uriString: String) {
        NSLog("[WC] pair() 调用，uri 前缀: \(uriString.prefix(60))")
        // WalletConnectURI(string:) 是可失败初始化器（非 throws）；
        // 失败的常见原因是链接里 expiryTimestamp 已过期（有效期 5 分钟）
        guard let uri = WalletConnectURI(string: uriString) else {
            NSLog("[WC] URI 解析失败")
            flowState = .error(Self.pairFailureMessage(uriString: uriString))
            return
        }
        flowState = .pairing
        Task {
            do {
                try await WalletKit.instance.pair(uri: uri)
                NSLog("[WC] pair() 成功，等待 dApp 请求")
            } catch {
                NSLog("[WC] pair() 失败: \(error)")
                await MainActor.run {
                    self.flowState = .error("配对失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 区分「链接过期」和「格式错误」，给出可操作的提示
    private static func pairFailureMessage(uriString: String) -> String {
        if let query = uriString.split(separator: "?", maxSplits: 1).last.map(String.init),
           let components = URLComponents(string: "wc://pair?\(query)"),
           let expiryString = components.queryItems?.first(where: { $0.name == "expiryTimestamp" })?.value,
           let expiry = TimeInterval(expiryString) {
            if Date().timeIntervalSince1970 > expiry {
                return "配对链接已过期（有效期 5 分钟），请在 dApp 上重新生成并立即粘贴"
            }
        }
        return "无效的配对链接（需以 wc: 开头）"
    }

    // MARK: - 会话提案

    private func handleProposal(_ sdkProposal: Session.Proposal) {
        let required = sdkProposal.requiredNamespaces
        let chains = required.values.flatMap { $0.chains ?? [] }.map { $0.absoluteString }
        let methods = required.values.flatMap { $0.methods }

        let display = WCProposalDisplay(
            id: sdkProposal.id,
            dAppName: sdkProposal.proposer.name,
            dAppDescription: sdkProposal.proposer.description.isEmpty ? nil : sdkProposal.proposer.description,
            dAppURL: sdkProposal.proposer.url.isEmpty ? nil : sdkProposal.proposer.url,
            dAppIconURL: sdkProposal.proposer.icons.first,
            requestedChains: chains,
            requestedMethods: methods
        )

        // 提议了不支持的链（如 optimism）→ 直接拒绝，避免 approve 时 namespaces 校验失败
        if display.hasUnsupportedChain {
            Task { try? await WalletKit.instance.rejectSession(proposalId: display.id, reason: .unsupportedChains) }
            return
        }

        proposal = display
        flowState = .awaitingProposal
    }

    /// 当前选中账号是否可用于 EVM dApp（含错误提示）
    private func evmAccountForApproval() -> AccountModel? {
        guard let account = profileViewModel?.selectedAccount else {
            alertMessage = "请先创建或选择一个账号"
            flowState = .error(alertMessage!)
            return nil
        }
        guard account.chain.isEVM else {
            alertMessage = "当前选中的是 \(account.chain.symbol) 账号，无法操作 EVM dApp，请先创建并选择以太坊系账号"
            flowState = .error(alertMessage!)
            return nil
        }
        return account
    }

    func approveProposal() {
        guard let display = proposal else { return }
        guard let account = evmAccountForApproval() else { return }
        flowState = .connecting

        Task {
            do {
                var blockchains: [Blockchain] = []
                var accounts: [Account] = []
                for reference in WalletConnectConfig.eip155References {
                    guard let chain = Blockchain("eip155:\(reference)"),
                          let wcAccount = Account(blockchain: chain, address: account.address) else { continue }
                    blockchains.append(chain)
                    accounts.append(wcAccount)
                }

                let namespace = SessionNamespace(
                    chains: blockchains,
                    accounts: accounts,
                    methods: [
                        "personal_sign", "eth_sign",
                        "eth_signTypedData", "eth_signTypedData_v4",
                        "eth_sendTransaction", "eth_signTransaction",
                        "wallet_switchEthereumChain",
                    ],
                    events: ["chainChanged", "accountsChanged"]
                )

                _ = try await WalletKit.instance.approve(
                    proposalId: display.id,
                    namespaces: ["eip155": namespace]
                )
                await MainActor.run {
                    self.proposal = nil
                    self.flowState = .idle
                    self.refreshSessions()
                }
            } catch {
                await MainActor.run {
                    self.proposal = nil
                    self.flowState = .error("连接失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func rejectProposal() {
        guard let display = proposal else { return }
        Task { try? await WalletKit.instance.rejectSession(proposalId: display.id, reason: .userRejected) }
        proposal = nil
        flowState = .idle
    }

    // MARK: - 会话请求（签名 / 交易 / 切链）

    private func handleSessionRequest(_ request: Request) {
        guard let session = WalletKit.instance.getSessions().first(where: { $0.topic == request.topic }) else { return }

        let paramsValue = request.params.value
        let pending = PendingRequest(
            id: UUID().uuidString,
            method: request.method,
            parameters: paramsValue,
            chainId: request.chainId.absoluteString,
            requestId: Int(numericId(of: request)),
            dAppName: session.peer.name,
            dAppIconURL: session.peer.icons.first
        )
        wcRequests[pending.id] = request
        pendingRequest = pending
    }

    /// wc_sessionAuthenticate（SIWE 以太坊登录）：dApp 请求钱包签发 CAIP-122 消息签名
    private func handleAuthRequest(_ request: AuthenticationRequest) {
        NSLog("[WC] 收到 SIWE 认证请求，dApp: \(request.requester.name)")
        guard let account = evmAccountForApproval() else { return }

        do {
            // 按本钱包支持的链/方法收敛 payload（会合并 recap 权限到 statement）
            let chains = WalletConnectConfig.eip155References.compactMap { Blockchain("eip155:\($0)") }
            let payload = try WalletKit.instance.buildAuthPayload(
                payload: request.payload,
                supportedEVMChains: chains,
                supportedMethods: ["personal_sign"]
            )
            guard let blockchain = Blockchain("eip155:\(account.chain.eip155ChainId ?? 1)"),
                  let wcAccount = Account(blockchain: blockchain, address: account.address) else {
                flowState = .error("账号构造失败")
                return
            }
            let message = try WalletKit.instance.formatAuthMessage(payload: payload, account: wcAccount)

            let pending = PendingRequest(
                id: UUID().uuidString,
                method: "wc_sessionAuthenticate",
                parameters: [message],
                chainId: nil,
                requestId: Int(numericId(of: request.id)),
                dAppName: request.requester.name,
                dAppIconURL: request.requester.icons.first
            )
            authRequests[pending.id] = (request, payload, message)
            pendingRequest = pending
        } catch {
            flowState = .error("登录请求解析失败: \(error.localizedDescription)")
        }
    }

    /// 从 RPCID（Either<String, Int64>）取整数表示
    private func numericId(of rpcId: RPCID) -> Int64 {
        switch rpcId {
        case .right(let int64):
            return int64
        case .left(let string):
            return Int64(string) ?? Int64(abs(string.hashValue % 1_000_000_000))
        }
    }

    /// 用户批准 SIWE 登录：签名 CAIP-122 消息 → 构建 Cacao → approve
    private func approveAuthRequest(_ pending: PendingRequest) {
        guard let account = evmAccountForApproval(),
              let auth = authRequests[pending.id] else { return }
        authRequests.removeValue(forKey: pending.id)

        let messageHex = Data(auth.message.utf8).map { String(format: "%02x", $0) }.joined()
        NSLog("[WC] 开始 SIWE 签名，账号: \(account.address)")
        signing.personalSign(messageHex: messageHex, account: account) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let signature):
                    NSLog("[WC] SIWE 消息签名成功: \(signature)")
                    do {
                        guard let blockchain = Blockchain("eip155:\(account.chain.eip155ChainId ?? 1)"),
                              let wcAccount = Account(blockchain: blockchain, address: account.address) else {
                            self?.flowState = .error("账号构造失败")
                            return
                        }
                        let cacao = try WalletKit.instance.buildSignedAuthObject(
                            authPayload: auth.payload,
                            signature: CacaoSignature(t: .eip191, s: signature),
                            account: wcAccount
                        )
                        _ = try await WalletKit.instance.approveSessionAuthenticate(
                            requestId: auth.request.id,
                            auths: [cacao]
                        )
                        NSLog("[WC] SIWE approveSessionAuthenticate 成功 requestId=\(auth.request.id)")
                        self?.refreshSessions()
                        // 认证流程已结束，复位配对页状态（否则永远停在「等待 dApp 响应」且无法重试）
                        self?.flowState = .idle
                        self?.alertMessage = "登录已批准，请返回浏览器查看结果"
                    } catch {
                        NSLog("[WC] SIWE approveSessionAuthenticate 失败: \(error)")
                        self?.flowState = .error("登录批准失败: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    // 签名失败（取消/报错）：丢弃请求，dApp 端会超时
                    NSLog("[WC] SIWE 签名失败: \(error.localizedDescription)")
                    self?.alertMessage = "登录签名失败: \(error.localizedDescription)"
                    self?.flowState = .error(self?.alertMessage ?? "")
                }
            }
        }
    }

    /// 用户批准签名请求
    func approvePendingRequest() {
        guard let pending = pendingRequest else { return }

        // SIWE 认证请求存放在 authRequests 而非 wcRequests，先分流处理
        if pending.method == "wc_sessionAuthenticate" {
            pendingRequest = nil
            approveAuthRequest(pending)
            return
        }

        guard let request = wcRequests[pending.id] else { return }
        pendingRequest = nil

        // 响应完成后清理
        deferComplete(requestId: pending.id)

        guard let account = evmAccountForApproval() else {
            respondError(request, code: -32000, message: "Selected account is not an EVM account")
            return
        }

        let params = pending.parameters as? [Any] ?? []

        switch request.method {
        case "wc_sessionAuthenticate":
            approveAuthRequest(pending)

        case "personal_sign", "eth_sign":
            // personal_sign: [messageHex, address]；eth_sign 同样按消息处理
            guard let messageHex = params.first as? String else {
                respondError(request, code: -32602, message: "Invalid message parameters")
                return
            }
            signing.personalSign(messageHex: messageHex, account: account) { [weak self] result in
                self?.respondResult(request, result: result)
            }

        case "eth_signTypedData", "eth_signTypedData_v4":
            // eth_signTypedData(_v4): [address, typedDataJSON]
            guard let typedDataJSON = params.count >= 2 ? params[1] as? String : nil else {
                respondError(request, code: -32602, message: "Invalid typed data parameters")
                return
            }
            signing.signTypedData(typedDataJSON: typedDataJSON, account: account) { [weak self] result in
                self?.respondResult(request, result: result)
            }

        case "eth_sendTransaction":
            guard let txJSON = params.first, let tx = WCTransaction(json: txJSON) else {
                respondError(request, code: -32602, message: "Invalid transaction parameters")
                return
            }
            // 请求的链优先，回退当前账号所在链
            let chainId = chainReferenceInt(from: request.chainId) ?? account.chain.eip155ChainId ?? 1
            signing.sendTransaction(tx, account: account, chainId: chainId) { [weak self] result in
                self?.respondResult(request, result: result)
            }

        case "eth_signTransaction":
            // 只签名不广播可被 dApp 重放，主流钱包同样拒绝
            respondError(request, code: 4001, message: "eth_signTransaction is not supported. Use eth_sendTransaction instead.")

        case "wallet_switchEthereumChain":
            handleSwitchChain(request, params: params)

        default:
            respondError(request, code: -32601, message: "Method not supported: \(request.method)")
        }
    }

    /// 用户拒绝签名请求（EIP-1474 用户拒绝码 4001）
    func rejectPendingRequest() {
        guard let pending = pendingRequest else { return }
        pendingRequest = nil
        // SIWE 认证请求无 reject 接口：静默丢弃，dApp 端会超时
        guard let request = wcRequests[pending.id] else {
            authRequests.removeValue(forKey: pending.id)
            flowState = .idle
            return
        }
        deferComplete(requestId: pending.id)
        respondError(request, code: 4001, message: "User rejected the request")
    }

    /// wallet_switchEthereumChain: params[0]["chainId"] 为 hex quantity（如 "0x38"）
    private func handleSwitchChain(_ request: Request, params: [Any]) {
        guard let dict = params.first as? [String: Any],
              let chainIdHex = dict["chainId"] as? String,
              let chainId = EthRPCClient.parseHexQuantity(chainIdHex) else {
            respondError(request, code: -32602, message: "Invalid chainId parameter")
            return
        }

        let reference = String(chainId)
        guard WalletConnectConfig.eip155References.contains(reference) else {
            // EIP-3085 unrecognized chain id
            respondError(request, code: 4902, message: "Unrecognized chain ID \(chainId)")
            return
        }

        // 支持的链：响应成功并通知 dApp 链已切换
        respondSuccess(request, result: NSNull())
        emitChainChanged(reference: reference, topic: request.topic)
    }

    /// 切链成功后 emit chainChanged 事件
    private func emitChainChanged(reference: String, topic: String) {
        guard let blockchain = Blockchain("eip155:\(reference)") else { return }
        Task {
            try? await WalletKit.instance.emit(
                topic: topic,
                event: Session.Event(name: "chainChanged", data: AnyCodable(reference)),
                chainId: blockchain
            )
        }
    }

    // MARK: - 会话管理

    func refreshSessions() {
        sessions = WalletKit.instance.getSessions().map { session in
            WCSessionDisplay(
                id: session.topic,
                dAppName: session.peer.name,
                dAppURL: session.peer.url.isEmpty ? nil : session.peer.url,
                dAppIconURL: session.peer.icons.first,
                accounts: session.namespaces.values.flatMap { $0.accounts.map { $0.absoluteString } },
                expiryDate: session.expiryDate
            )
        }
    }

    /// 断开会话；删除账号时也应调用（账号删除后 session 不应保留权限）
    func disconnect(_ display: WCSessionDisplay) {
        Task { try? await WalletKit.instance.disconnect(topic: display.id) }
        sessions.removeAll { $0.id == display.id }
    }

    /// 断开所有会话（账号删除时调用）
    func disconnectAll() {
        for session in sessions {
            disconnect(session)
        }
    }

    /// 断开 accounts 中包含指定地址（CAIP-10 尾段匹配）的所有会话
    private func disconnectSessions(containing address: String) {
        let matches = sessions.filter { session in
            session.accounts.contains { $0.lowercased().hasSuffix(address.lowercased()) }
        }
        for session in matches {
            disconnect(session)
        }
    }

    // MARK: - Respond helpers

    private func respondResult(_ request: Request, result: Result<String, Error>) {
        switch result {
        case .success(let value):
            respondSuccess(request, result: value)
        case .failure(let error):
            respondError(request, code: -32000, message: error.localizedDescription)
        }
    }

    private func respondSuccess(_ request: Request, result: Any) {
        Task {
            try? await WalletKit.instance.respond(
                topic: request.topic,
                requestId: request.id,
                response: .response(AnyCodable(any: result))
            )
        }
    }

    private func respondError(_ request: Request, code: Int, message: String) {
        Task {
            try? await WalletKit.instance.respond(
                topic: request.topic,
                requestId: request.id,
                response: .error(JSONRPCError(code: code, message: message))
            )
        }
    }

    // MARK: - Helpers

    private func numericId(of request: Request) -> Int64 {
        switch request.id {
        case .right(let int64):
            return int64
        case .left(let string):
            return Int64(string) ?? Int64(abs(string.hashValue % 1_000_000_000))
        }
    }

    /// 从 CAIP-2（"eip155:1"）提取链 reference 的整数
    private func chainReferenceInt(from blockchain: Blockchain) -> Int? {
        Int(blockchain.reference)
    }

    private func deferComplete(requestId: String) {
        wcRequests.removeValue(forKey: requestId)
    }
}

extension Notification.Name {
    /// userInfo["address"]: 被删除账号的链上地址
    static let wcAccountDeleted = Notification.Name("wcAccountDeleted")
}
