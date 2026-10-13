//
//  CreateAccountByMnemonicView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/21.
//

import SwiftUI
import WalletCore

// 注意：本页面是通过 NavigationLink push 进入的（宿主已有 NavigationView），
// 这里不能再包一层 NavigationView，否则返回时列表条目会闪动。
struct CreateAccountByMnemonicView: View {

    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var vm: ProfileViewModel

    @State private var accountName: String = ""
    @State private var mnemonic: String = ""
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
                mnemonicSection
                if showGeneratedAddress, let address = generatedAddress {
                    addressSection(address: address)
                }
            }
            .background(Color.theme.background)
        }
        .navigationTitle("助记词创建账号")
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

extension CreateAccountByMnemonicView {

    private var canGenerate: Bool {
        !mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                TextField("例如: 我的BTC钱包", text: $accountName)
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

    private var mnemonicSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("助记词")
                    .foregroundColor(Color.theme.accent)
                    .font(.headline)

                TextEditor(text: $mnemonic)
                    .foregroundColor(Color.theme.accent)
                    .frame(minHeight: 100)
                    .padding()
                    .background(Color.theme.secondaryText.opacity(0.1))
                    .cornerRadius(8)

                HStack {
                    Button("生成随机助记词") {
                        mnemonic = ProfileViewModel.generateMnemonic()
                    }
                    .foregroundColor(.blue)
                    .contentShape(Rectangle())
                    Spacer()
                    Button("粘贴剪贴板") {
                        if let pasteboardString = UIPasteboard.general.string {
                            mnemonic = pasteboardString
                        }
                    }
                    .foregroundColor(.blue)
                    .contentShape(Rectangle())
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
        let trimmedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        generatedAddress = ProfileViewModel.generateAddressFromMnemonic(mnemonic: trimmedMnemonic, chain: selectedChain)
        showGeneratedAddress = true
        isGenerating = false
    }

    private func save() {
        guard let address = generatedAddress else { return }
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        vm.addAccount(name: trimmedName, address: address, chain: selectedChain, mnemonic: mnemonic.trimmingCharacters(in: .whitespacesAndNewlines))
        presentationMode.wrappedValue.dismiss()
    }
}

struct CreateAccountByMnemonicView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CreateAccountByMnemonicView(vm: ProfileViewModel())
        }
    }
}
