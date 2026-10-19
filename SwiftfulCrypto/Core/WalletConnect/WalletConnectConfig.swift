//
//  WalletConnectConfig.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import Foundation
import ReownWalletKit

/// WalletConnect 集中配置
enum WalletConnectConfig {

    /// TODO: 前往 https://cloud.reown.com 注册（免费）并创建 Project，替换此占位符。
    ///
    /// 注册步骤：
    /// 1. 打开 https://cloud.reown.com → 用邮箱/GitHub 登录
    /// 2. 「Create Project」→ 输入名称（如 SwiftfulCrypto）→ 创建
    /// 3. 复制 Project ID，填到下方常量
    /// 4. 无需额外配置即可用于 Relay 连接
    ///
    /// 注意：占位符无效时 `WalletKit.configure` 不报错，但 Relay 连接会失败
    /// （pair 后 dApp 侧收不到响应，配对超时）。
    static let projectId = "3dd0dbdbf77259b5ad93bbc9895cbbe5"

    static let projectName = "SwiftfulCrypto"
    static let projectDescription = "Native multi-chain crypto wallet"
    static let appURL = "https://swiftfulcrypto.example.com"
    static let appIconURL = "https://swiftfulcrypto.example.com/icon.png"

    /// 深链返回 scheme（已在 Info.plist CFBundleURLTypes 注册）
    static let redirectScheme = "swiftfulcrypto"

    /// 支持 WalletConnect 会话的链（仅 EVM 系；CAIP-2 reference）
    static let eip155References = ["1", "56", "137", "43114"]

    /// 本 App 在 WalletConnect 协议中的元数据（展示给 dApp）
    static func makeMetadata() throws -> AppMetadata {
        AppMetadata(
            name: projectName,
            description: projectDescription,
            url: appURL,
            icons: [appIconURL],
            redirect: try AppMetadata.Redirect(native: redirectScheme, universal: nil)
        )
    }
}

/// Networking / Relay 全局只配置一次（钱包端 WalletKit 与 dApp 端 AppKit 共用）
enum WCBootstrap {

    static var networkingConfigured = false

    static func configureNetworkingIfNeeded() {
        guard !networkingConfigured else { return }
        guard WalletConnectConfig.projectId != "YOUR_PROJECT_ID" else { return }
        networkingConfigured = true

        Networking.configure(
            relayHost: "relay.walletconnect.com",
            groupIdentifier: "group.com.yournamehere.SwiftfulCrypto",
            projectId: WalletConnectConfig.projectId,
            socketFactory: WCWalletSocketFactory()
        )
    }
}
