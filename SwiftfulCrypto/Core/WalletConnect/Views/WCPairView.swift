//
//  WCPairView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/13.
//

import SwiftUI

/// 连接 dApp 入口：粘贴 Pair URI 或扫码
struct WCPairView: View {
    @ObservedObject var service: WalletConnectService
    @EnvironmentObject private var profileVM: ProfileViewModel
    @State private var uriText: String = ""
    @State private var showScanner: Bool = false
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("配对链接")
                        .font(.headline)
                        .foregroundColor(Color.theme.accent)
                    Text("在 dApp 网站上选择「WalletConnect」并复制配对链接（wc: 开头），粘贴到此处")
                        .font(.caption)
                        .foregroundColor(Color.theme.secondaryText)

                    HStack(spacing: 8) {
                        TextField("wc:...", text: $uriText)
                            .font(.system(.footnote, design: .monospaced))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        // 模拟器长按粘贴菜单经常失灵，提供显式粘贴按钮
                        Button {
                            if let clipboard = UIPasteboard.general.string {
                                uriText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.body)
                                .foregroundColor(Color.theme.accent)
                                .frame(width: 36, height: 36)
                                .background(Color.theme.accent.opacity(0.12))
                                .cornerRadius(8)
                        }
                    }
                }

                if case .pairing = service.flowState {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在等待 dApp 响应…")
                            .font(.subheadline)
                            .foregroundColor(Color.theme.secondaryText)
                    }
                    .padding()
                }

                if case .error(let message) = service.flowState {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding()
                }

                VStack(spacing: 12) {
                    Button {
                        service.pair(uriString: uriText.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Label("连接", systemImage: "link")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canPair ? Color.theme.accent : Color.gray.opacity(0.4))
                            .cornerRadius(10)
                    }
                    .disabled(!canPair)

                    Button {
                        showScanner = true
                    } label: {
                        Label("扫描二维码", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .foregroundColor(Color.theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.theme.accent.opacity(0.12))
                            .cornerRadius(10)
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.theme.background.ignoresSafeArea())
            .navigationTitle("连接 dApp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    showScanner = false
                    uriText = code
                    service.pair(uriString: code)
                }
                .ignoresSafeArea()
            }
            // 审批弹窗挂在配对页内：配对 sheet 打开时到达的 SIWE 登录请求，
            // 需要盖在本 sheet 之上展示（根部挂载点此时休眠，见 pairSheetVisible）
            .modifier(WCApprovalSheets(service: service, accountAddress: { profileVM.selectedAccount?.address }))
            .onAppear { service.pairSheetVisible = true }
            .onDisappear { service.pairSheetVisible = false }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var canPair: Bool {
        switch service.flowState {
        case .pairing, .awaitingProposal, .connecting:
            return false
        default:
            // idle 和 error 状态都允许重新发起（错误后可直接改链接重试）
            return uriText.lowercased().hasPrefix("wc:")
        }
    }
}

struct WCPairView_Previews: PreviewProvider {
    static var previews: some View {
        WCPairView(service: WalletConnectService(profileViewModel: nil))
            .environmentObject(ProfileViewModel())
    }
}
