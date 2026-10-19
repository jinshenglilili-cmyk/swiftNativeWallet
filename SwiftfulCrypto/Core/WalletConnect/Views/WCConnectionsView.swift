//
//  WCConnectionsView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import SwiftUI

/// 已连接的 dApp 会话列表，支持断开
/// 样式对齐 ProfileView：InsetGrouped 分组列表 + 主题色行背景
struct WCConnectionsView: View {
    @ObservedObject var service: WalletConnectService
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        List {
            if service.sessions.isEmpty {
                emptyState
            } else {
                Section(header: Text("已连接的 dApp")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                ) {
                    ForEach(service.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .background(Color.theme.background.ignoresSafeArea())
        .navigationTitle("已连接的 dApp")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.refreshSessions() }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(Color.theme.secondaryText.opacity(0.6))
            Text("暂无已连接的 dApp")
                .font(.subheadline)
                .foregroundColor(Color.theme.secondaryText)
            Text("在 dApp 网站选择 WalletConnect，扫码或粘贴配对链接即可连接")
                .font(.caption)
                .foregroundColor(Color.theme.secondaryText.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .listRowBackground(Color.theme.background.opacity(0.5))
        .listRowSeparator(.hidden)
    }

    // MARK: - 会话行

    private func sessionRow(_ session: WCSessionDisplay) -> some View {
        HStack(spacing: 12) {
            dAppIcon(session)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.dAppName)
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                if let first = session.accounts.first {
                    Text(shortAddress(first))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.theme.secondaryText)
                }
                if let expiry = session.expiryText {
                    Text("有效期至 \(expiry)")
                        .font(.caption2)
                        .foregroundColor(Color.theme.secondaryText)
                }
            }

            Spacer()

            Button {
                service.disconnect(session)
            } label: {
                Text("断开")
                    .font(.subheadline)
                    .foregroundColor(Color.theme.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.theme.background.opacity(0.5))
    }

    @ViewBuilder private func dAppIcon(_ session: WCSessionDisplay) -> some View {
        if let iconURLString = session.dAppIconURL, let iconURL = URL(string: iconURLString) {
            AsyncImage(url: iconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe")
                    .foregroundColor(Color.theme.secondaryText)
            }
            .frame(width: 44, height: 44)
            .background(Color.theme.secondaryText.opacity(0.1))
            .cornerRadius(10)
        } else {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundColor(Color.theme.secondaryText)
                .frame(width: 44, height: 44)
                .background(Color.theme.secondaryText.opacity(0.1))
                .cornerRadius(10)
        }
    }

    /// CAIP-10（eip155:1:0xAb…）→ 0xAb…1234
    private func shortAddress(_ caip10: String) -> String {
        let parts = caip10.split(separator: ":")
        guard let address = parts.last.map(String.init) else { return caip10 }
        guard address.count > 12 else { return address }
        let prefix = address.prefix(8)
        let suffix = address.suffix(6)
        return "\(prefix)…\(suffix)"
    }
}

struct WCConnectionsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WCConnectionsView(service: WalletConnectService(profileViewModel: nil))
        }
    }
}
