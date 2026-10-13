//
//  ImportAccountByPrivateKeyView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI
import UIKit
import WalletCore

// 注意：本页面是通过 NavigationLink push 进入的（宿主已有 NavigationView），
// 这里不能再包一层 NavigationView，否则返回时列表条目会闪动。
struct ImportAccountByPrivateKeyView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ProfileViewModel

    @State private var accountName: String = ""
    @State private var privateKey: String = ""
    @State private var selectedChain: ChainType = .bitcoin
    @State private var generatedAddress: String?
    @State private var showGeneratedAddress = false
    @State private var isGenerating = false

    var body: some View {
        ZStack {
            Color.theme.background
                .ignoresSafeArea()

            Form {
                accountNameSection
                chainSelectionSection
                privateKeySection
                if showGeneratedAddress, let address = generatedAddress {
                    addressSection(address: address)
                }
            }
            .background(Color.theme.background)
        }
        .navigationTitle("私钥导入账号")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !showGeneratedAddress {
                    Button("生成地址") {
                        generateAddress()
                    }
                    .foregroundColor(Color.theme.accent)
                    .disabled(!canGenerate)
                } else {
                    Button("保存") {
                        save()
                    }
                    .foregroundColor(Color.theme.accent)
                    .disabled(!canSave)
                }
            }
        }
    }
}

extension ImportAccountByPrivateKeyView {

    private var canGenerate: Bool {
        !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        generatedAddress != nil &&
        !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accountNameSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("账号名称")
                    .foregroundColor(Color.theme.accent)
                    .font(.headline)
                TextField("例如: 我的ETH钱包", text: $accountName)
                    .foregroundColor(Color.theme.accent)
                    .padding()
                    .background(Color.theme.secondaryText.opacity(0.1))
                    .cornerRadius(8)
            }
            .listRowBackground(Color.theme.background.opacity(0.5))
        }
    }

    private var chainSelectionSection: some View {
        Section {
            Picker("选择链", selection: $selectedChain) {
                ForEach(ChainType.allCases) { chain in
                    Text(chain.name)
                        .foregroundColor(Color.theme.accent)
                        .tag(chain)
                }
            }
            .foregroundColor(Color.theme.accent)
        }
        .listRowBackground(Color.theme.background.opacity(0.5))
    }

    private var privateKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("私钥 (Hex 格式)")
                    .foregroundColor(Color.theme.accent)
                    .font(.headline)

                TextEditor(text: $privateKey)
                    .foregroundColor(Color.theme.accent)
                    .frame(minHeight: 100)
                    .padding()
                    .background(Color.theme.secondaryText.opacity(0.1))
                    .cornerRadius(8)

                HStack {
                    Button {
                        // 异步读取确保拿到剪切板最新内容
                        DispatchQueue.main.async {
                            if let pasteboardString = UIPasteboard.general.string {
                                privateKey = pasteboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    } label: {
                        Text("粘贴剪贴板")
                            .foregroundColor(.blue)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    Spacer()
                }
            }
            .listRowBackground(Color.theme.background.opacity(0.5))
        }
    }

    private func addressSection(address: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("生成的地址")
                    .foregroundColor(Color.theme.accent)
                    .font(.headline)
                Text(address)
                    .font(.caption)
                    .foregroundColor(Color.theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .padding()
                    .background(Color.theme.secondaryText.opacity(0.1))
                    .cornerRadius(8)
            }
            .listRowBackground(Color.theme.background.opacity(0.5))
        }
    }

    private func generateAddress() {
        isGenerating = true
        let trimmedPrivateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        generatedAddress = ProfileViewModel.generateAddressFromPrivateKey(privateKeyHex: trimmedPrivateKey, chain: selectedChain)
        showGeneratedAddress = true
        isGenerating = false
    }

    private func save() {
        guard let address = generatedAddress else { return }
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        vm.addAccount(name: trimmedName, address: address, chain: selectedChain, privateKeyHex: privateKey.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

struct ImportAccountByPrivateKeyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ImportAccountByPrivateKeyView(vm: ProfileViewModel())
        }
    }
}
