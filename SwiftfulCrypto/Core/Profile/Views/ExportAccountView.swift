//
//  ExportAccountView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/12.
//

import SwiftUI

// 注意：本页面是通过 NavigationLink push 进入的（宿主已有导航栈），
// 这里不能再包一层 NavigationView。
// 导出私钥前必须通过生物识别验证（Face ID / Touch ID）。
struct ExportAccountView: View {

    @EnvironmentObject private var vm: ProfileViewModel
    @State private var isAuthenticating: Bool = false
    @State private var exportedPrivateKey: String?
    @State private var errorMessage: String?
    @State private var showCopied: Bool = false

    var body: some View {
        ZStack {
            Color.theme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if let account = vm.selectedAccount {
                        accountSection(account: account)
                        warningSection
                        exportSection(account: account)
                    } else {
                        placeholderSection
                    }
                }
                .padding()
            }
        }
        .navigationTitle("导出账号")
        .onAppear(perform: resetState)
    }
}

extension ExportAccountView {

    private func accountSection(account: AccountModel) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(account.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.theme.accent)
                Spacer()
                Text(account.chain.name)
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)
            }
            HStack {
                Text(account.address)
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .padding()
        .background(Color.theme.secondaryText.opacity(0.1))
        .cornerRadius(12)
    }

    private var warningSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("私钥是资产的唯一凭证，请勿泄露给任何人。导出后请妥善保存在安全的地方，任何人拿到私钥即可转走你的资产。")
                .font(.callout)
                .foregroundColor(Color.theme.secondaryText)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func exportSection(account: AccountModel) -> some View {
        VStack(spacing: 15) {
            if let privateKey = exportedPrivateKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("私钥")
                        .font(.headline)
                        .foregroundColor(Color.theme.accent)
                    Text(privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.theme.accent)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.theme.secondaryText.opacity(0.1))
                        .cornerRadius(8)

                    Button {
                        UIPasteboard.general.string = privateKey
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopied = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            Text(showCopied ? "已复制" : "复制私钥")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            } else {
                Button {
                    authenticateAndExport(account: account)
                } label: {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text(isAuthenticating ? "验证中..." : "生物识别验证并导出私钥")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isAuthenticating)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(Color.theme.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var placeholderSection: some View {
        Text("暂无账号，请先创建或导入账号")
            .font(.callout)
            .foregroundColor(Color.theme.secondaryText)
            .padding(50)
    }

    // MARK: - 生物识别

    private func authenticateAndExport(account: AccountModel) {
        errorMessage = nil
        isAuthenticating = true

        BiometricAuthService.authenticate(reason: "验证身份后查看账号私钥") { success, message in
            isAuthenticating = false
            if success {
                // 验证通过才从 Keychain 数据中派生/读取私钥
                exportedPrivateKey = ProfileViewModel.exportPrivateKey(for: account)
                if exportedPrivateKey == nil {
                    errorMessage = "无法获取私钥（账号缺少助记词/私钥数据）"
                }
            } else if let message = message {
                errorMessage = message
            }
        }
    }

    private func resetState() {
        // 每次进入页面都重新验证，不保留上次导出结果
        exportedPrivateKey = nil
        errorMessage = nil
        isAuthenticating = false
        showCopied = false
    }
}

struct ExportAccountView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExportAccountView()
        }
        .environmentObject(ProfileViewModel())
    }
}
