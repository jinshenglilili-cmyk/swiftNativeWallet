//
//  ExternalWalletService.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation
import Combine
import SwiftUI
import ReownAppKit
import ReownWalletKit

/// dApp 端：通过 AppKit 连接外部钱包（MetaMask / Trust 等）
@MainActor
final class ExternalWalletService: ObservableObject {

    // MARK: - Published

    @Published var isConnected = false
    @Published var walletName: String?
    @Published var address: String?
    @Published var lastSignResult: String?
    @Published var errorMessage: String?

    // MARK: - Private

    private var configured = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 配置

    /// App 启动后主线程调用一次
    func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        guard WalletConnectConfig.projectId != "YOUR_PROJECT_ID" else {
            errorMessage = "尚未配置 WalletConnect Project ID"
            return
        }

        WCBootstrap.configureNetworkingIfNeeded()
        guard WCBootstrap.networkingConfigured else { return }

        guard let metadata = try? WalletConnectConfig.makeMetadata() else {
            errorMessage = "App 元数据构造失败"
            return
        }

        AppKit.configure(
            projectId: WalletConnectConfig.projectId,
            metadata: metadata,
            crypto: WCDefaultCryptoProvider(),
            authRequestParams: nil
        )

        AppKit.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSession() }
            .store(in: &cancellables)

        AppKit.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSession() }
            .store(in: &cancellables)

        // 签名等请求的响应
        AppKit.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                switch response.result {
                case .response(let value):
                    self?.lastSignResult = String(describing: value.value)
                case .error(let rpcError):
                    self?.errorMessage = "签名被拒绝: \(rpcError.message)"
                }
            }
            .store(in: &cancellables)

        refreshSession()
    }

    // MARK: - 连接 / 断开

    /// 弹出 SDK 自带的钱包选择模态
    func presentWalletModal() {
        errorMessage = nil
        AppKit.present(from: Self.topViewController())
    }

    func refreshSession() {
        guard let session = AppKit.instance.getSessions().first else {
            isConnected = false
            walletName = nil
            address = nil
            return
        }
        isConnected = true
        walletName = session.peer.name
        address = session.namespaces.values
            .flatMap { $0.accounts }
            .first
            .map { $0.address }
    }

    func disconnect() {
        guard let session = AppKit.instance.getSessions().first else { return }
        Task { try? await AppKit.instance.disconnect(topic: session.topic) }
    }

    // MARK: - 通过外部钱包签名（连通性验证用）

    /// 发起 personal_sign；结果通过 sessionResponsePublisher 回来后更新 lastSignResult
    func personalSign(message: String) {
        guard let address = address else {
            errorMessage = "尚未连接外部钱包"
            return
        }
        errorMessage = nil
        Task {
            do {
                try await AppKit.instance.request(.personal_sign(address: address, message: message))
            } catch {
                self.errorMessage = "请求失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    /// SwiftUI 环境下找到最顶层 ViewController（AppKit 的模态由 UIKit present）
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
            return nil
        }

        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
