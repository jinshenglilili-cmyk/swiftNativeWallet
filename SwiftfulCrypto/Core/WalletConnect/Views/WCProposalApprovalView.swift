//
//  WCProposalApprovalView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import SwiftUI

/// WalletConnect 会话提案审批：展示 dApp 信息与请求权限
struct WCProposalApprovalView: View {
    let proposal: WCProposalDisplay
    let walletAddress: String?
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // dApp 信息
            VStack(spacing: 12) {
                if let iconURLString = proposal.dAppIconURL, let iconURL = URL(string: iconURLString) {
                    AsyncImage(url: iconURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "globe")
                            .foregroundColor(Color.theme.secondaryText)
                    }
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)
                }

                Text(proposal.dAppName)
                    .font(.title2)
                    .fontWeight(.bold)

                if let url = proposal.dAppURL {
                    Text(url)
                        .font(.caption)
                        .foregroundColor(Color.theme.secondaryText)
                }
            }
            .padding(.top, 24)

            Divider()

            // 请求的链与方法
            VStack(alignment: .leading, spacing: 12) {
                Text("请求的链")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                ForEach(proposal.requestedChains, id: \.self) { chain in
                    HStack {
                        Image(systemName: supportedChains.contains(chain) ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(supportedChains.contains(chain) ? .green : .red)
                        Text(chain)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                }

                Text("请求的权限")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                    .padding(.top, 4)
                Text(proposal.requestedMethods.joined(separator: ", "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color.theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            // 签名账号
            if let address = walletAddress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接账号")
                        .font(.headline)
                        .foregroundColor(Color.theme.accent)
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            // 不支持链的警告
            if proposal.hasUnsupportedChain {
                Label("该 dApp 请求了暂不支持的链，无法连接", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
            }

            Spacer()

            // 按钮
            HStack(spacing: 16) {
                Button(action: onReject) {
                    Text("拒绝")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                }

                Button(action: onApprove) {
                    Text("批准")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(proposal.hasUnsupportedChain ? Color.gray.opacity(0.4) : Color.theme.accent)
                        .cornerRadius(10)
                }
                .disabled(proposal.hasUnsupportedChain)
            }
            .padding()
        }
        .background(Color.theme.background.ignoresSafeArea())
    }

    private var supportedChains: [String] {
        WalletConnectConfig.eip155References.map { "eip155:\($0)" }
    }
}

struct WCProposalApprovalView_Previews: PreviewProvider {
    static var previews: some View {
        WCProposalApprovalView(
            proposal: WCProposalDisplay(
                id: "1",
                dAppName: "Reown Demo",
                dAppDescription: "Demo dApp",
                dAppURL: "https://lab.reown.com",
                dAppIconURL: nil,
                requestedChains: ["eip155:1", "eip155:137"],
                requestedMethods: ["personal_sign", "eth_sendTransaction"]
            ),
            walletAddress: "0x742d35Cc6634C0532925a3b8865264350f352fef",
            onApprove: {},
            onReject: {}
        )
    }
}
