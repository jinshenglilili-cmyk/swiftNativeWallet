//
//  SigningRequestView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/08/14.
//

import SwiftUI

/// 签名/交易审批弹窗：浏览器与 WalletConnect 两端共用
struct SigningRequestView: View {
    let request: PendingRequest
    let accountAddress: String?
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // dApp 信息（WalletConnect 会话来源时显示）
                    if let dAppName = request.dAppName {
                        HStack(spacing: 12) {
                            if let iconURLString = request.dAppIconURL,
                               let iconURL = URL(string: iconURLString) {
                                AsyncImage(url: iconURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "globe")
                                }
                                .frame(width: 40, height: 40)
                                .cornerRadius(8)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dAppName)
                                    .font(.headline)
                                if let chainId = request.chainId {
                                    Text(chainId)
                                        .font(.caption)
                                        .foregroundColor(Color.theme.secondaryText)
                                }
                            }
                        }
                        .padding(.top)
                    }

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.largeTitle)
                            .foregroundColor(Color.theme.accent)
                        Text(request.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(request.description)
                            .font(.subheadline)
                            .foregroundColor(Color.theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    // 待签消息明文
                    if let message = request.messagePreview {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Message")
                                .font(.headline)
                                .foregroundColor(Color.theme.accent)
                            Text(message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.theme.secondaryText)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.theme.background)
                                .cornerRadius(8)
                        }
                    }

                    // 交易详情
                    if let tx = request.transactionSummary {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transaction")
                                .font(.headline)
                                .foregroundColor(Color.theme.accent)
                            if let to = tx["to"] {
                                detailRow(label: "To", value: to)
                            }
                            if let value = tx["value"], let wei = UInt64(value.stripHexPrefix(), radix: 16) {
                                detailRow(label: "Value (wei)", value: String(wei))
                            }
                            if let data = tx["data"] {
                                detailRow(label: "Data", value: String(data.prefix(66)) + (data.count > 66 ? "…" : ""))
                            }
                        }
                    }

                    // Account information
                    if let accountAddress = accountAddress {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("From Account")
                                .font(.headline)
                                .foregroundColor(Color.theme.accent)
                            Text(accountAddress)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.theme.secondaryText)
                                .padding()
                                .background(Color.theme.background)
                                .cornerRadius(8)
                        }
                    }

                    // Request details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Method")
                            .font(.headline)
                            .foregroundColor(Color.theme.accent)
                        Text(request.method)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.theme.secondaryText)
                            .padding()
                            .background(Color.theme.background)
                            .cornerRadius(8)

                        if let chainId = request.chainId, request.dAppName == nil {
                            Text("Chain ID")
                                .font(.headline)
                                .foregroundColor(Color.theme.accent)
                            Text(chainId)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.theme.secondaryText)
                                .padding()
                                .background(Color.theme.background)
                                .cornerRadius(8)
                        }
                    }

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button(action: onReject) {
                            Text("Reject")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(10)
                        }

                        Button(action: onApprove) {
                            Text("Approve")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.theme.accent)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.vertical)
                }
                .padding()
            }
            .background(Color.theme.background)
            .navigationBarTitle("Request Approval", displayMode: .inline)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(Color.theme.secondaryText)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.theme.background)
                .cornerRadius(8)
        }
    }
}

struct SigningRequestView_Previews: PreviewProvider {
    static var previews: some View {
        SigningRequestView(
            request: PendingRequest(
                id: "1",
                method: "eth_sendTransaction",
                parameters: nil,
                chainId: "1",
                requestId: 1
            ),
            accountAddress: "0x742d35Cc6634C0532925a3b8865264350f352fef",
            onApprove: {},
            onReject: {}
        )
    }
}
