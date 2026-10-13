//
//  CreateTransactionView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/07/23.
//

import SwiftUI

struct CreateTransactionView: View {

    @State private var toAddress: String = ""
    @State private var amountString: String = ""
    @State private var selectedChain: ChainType
    @State private var isSubmitting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    @Binding var isPresented: Bool

    let selectedAccount: AccountModel
    let onTransactionCreated: () -> Void
    @ObservedObject var vm: TransactionListViewModel

    init(
        selectedAccount: AccountModel,
        isPresented: Binding<Bool>,
        onTransactionCreated: @escaping () -> Void,
        vm: TransactionListViewModel
    ) {
        self.selectedAccount = selectedAccount
        self._isPresented = isPresented
        self._selectedChain = State(initialValue: selectedAccount.chain)
        self.onTransactionCreated = onTransactionCreated
        self.vm = vm
    }

    var body: some View {
        ZStack {
            Color.theme.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                formSection

                if showError {
                    errorBanner
                }

                Spacer()

                submitButton
            }
            .padding()
        }
        .navigationTitle("新建转账")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(leading: Button(action: {
            isPresented = false
            onTransactionCreated()
        }) {
            Image(systemName: "xmark")
                .foregroundColor(.white)
                .font(.title2)
                .padding(12)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        })
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .disabled(isSubmitting)
    }
}

extension CreateTransactionView {

    private var formSection: some View {
        VStack(spacing: 20) {
            // 发起账户信息
            fromAccountSection

            // 接收地址
            toAddressSection

            // 转账金额
            amountSection

            // 选择链
            chainSelectionSection
        }
    }

    private var fromAccountSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("发起账户")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                Spacer()
            }

            VStack(spacing: 8) {
                HStack {
                    Text(selectedAccount.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.theme.accent)
                    Spacer()
                }

                HStack {
                    Text("[\(selectedAccount.chain.symbol)] \(formatAddress(selectedAccount.address))")
                        .font(.caption)
                        .foregroundColor(Color.theme.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }
            .padding()
            .background(Color.theme.secondaryText.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var toAddressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("接收地址")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                Spacer()
            }

            TextField("请输入接收地址", text: $toAddress)
                .padding()
                .background(Color.theme.secondaryText.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(Color.theme.accent)
                .autocorrectionDisabled()
                .autocapitalization(.none)
        }
    }

    private var amountSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("转账金额 (\(selectedChain.symbol))")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                Spacer()
            }

            HStack {
                TextField("请输入金额", text: $amountString)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(Color.theme.secondaryText.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(Color.theme.accent)

                Button(action: {
                    // 这里可以添加"全部"按钮，发送全部余额，由于我们没有余额查询，先保留此功能
                    amountString = "0.01"
                }) {
                    Text("全部")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.theme.accent)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var chainSelectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("区块链")
                    .font(.headline)
                    .foregroundColor(Color.theme.accent)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ChainType.allCases) { chain in
                        ChainSelectionItem(
                            chain: chain,
                            isSelected: selectedChain.id == chain.id
                        ) {
                            selectedChain = chain
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 8)
        }
    }

    private var errorBanner: some View {
        Text(errorMessage)
            .font(.caption)
            .foregroundColor(.white)
            .padding()
            .background(Color.red)
            .cornerRadius(8)
    }

    private var submitButton: some View {
        Button(action: {
            submitTransaction()
        }) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("发起转账")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.theme.accent)
            .foregroundColor(Color.white.opacity(0.8))
            .cornerRadius(12)
        }
        .disabled(isSubmitting || !isFormValid)
        .opacity(isFormValid && !isSubmitting ? 1 : 0.5)
    }

    private var isFormValid: Bool {
        guard !toAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let amount = Double(amountString), amount > 0 else {
            return false
        }
        return true
    }

    private func formatAddress(_ address: String) -> String {
        if address.count <= 16 {
            return address
        }
        let prefix = String(address.prefix(8))
        let suffix = String(address.suffix(8))
        return "\(prefix)...\(suffix)"
    }

    private func submitTransaction() {
        let trimmedAddress = toAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            showError(message: "请输入接收地址")
            return
        }

        guard let amount = Double(amountString), amount > 0 else {
            showError(message: "请输入有效的金额")
            return
        }

        isSubmitting = true

        // 添加交易到列表，ViewModel会自动模拟确认过程
        _ = vm.addTransaction(
            fromAccountId: selectedAccount.id,
            fromAddress: selectedAccount.address,
            toAddress: trimmedAddress,
            amount: amount,
            chain: selectedChain
        )

        // 延迟一下返回，让用户看到提交状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSubmitting = false
            isPresented = false
            onTransactionCreated()
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

struct ChainSelectionItem: View {
    let chain: ChainType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(chain.symbol)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : Color.theme.accent)
                Text(chain.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : Color.theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.theme.accent : Color.theme.secondaryText.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct CreateTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CreateTransactionView(
                selectedAccount: AccountModel(
                    name: "我的以太坊账户",
                    address: "0x1234567890abcdef1234567890abcdef12345678",
                    chain: .ethereum
                ),
                isPresented: .constant(true),
                onTransactionCreated: {},
                vm: TransactionListViewModel()
            )
        }
    }
}
