//
//  ContractCallView.swift
//  SwiftfulCrypto
//
//  Created by liwei on 2026/10/19.
//

import SwiftUI
import WalletCore
import web3swift
import Web3Core

/// 合约调用页（web3swift 实现）：
/// - ERC20 预设：转账（encodeParameters 编码 → 签名 → 广播）
/// - ABI 函数调用：任意函数签名（如 `approve(address,uint256) returns (bool)`）或粘贴完整 ABI JSON
///   → 自动生成参数输入框 → 「查询」走 eth_call + decodeReturnData 解码返回值（含 revert 原因解析）
///   →「发送交易」走现有签名广播链路
struct ContractCallView: View {

    private let signing: EthereumSigningService

    enum CallMode: String, CaseIterable {
        case erc20 = "ERC20 转账"
        case abi = "ABI 函数调用"
    }

    /// 从签名/ABI JSON 解析出的函数描述
    struct AbiFunction: Identifiable, Hashable {
        let name: String
        let signature: String        // 如 "transfer(address,uint256)"
        let inputTypes: [String]
        let inputNames: [String]
        let outputTypes: [String]
        let mutability: String       // view / pure / nonpayable / payable

        var id: String { signature }
        var isRead: Bool { mutability == "view" || mutability == "pure" }
    }

    @State private var mode: CallMode = .erc20

    // 公共参数
    @State private var contractAddress = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var txHash: String?
    @State private var queryResult: [String]?

    // ERC20 模式参数
    @State private var recipient = ""
    @State private var amount = ""
    @State private var decimalsText = "18"

    // ABI 模式参数
    @State private var abiText = ""            // 函数签名或 ABI JSON
    @State private var parsedFunctions: [AbiFunction] = []
    @State private var selectedFunctionIdx = 0
    @State private var paramTexts: [String] = []
    @State private var valueText = "0"

    @EnvironmentObject private var vm: ProfileViewModel

    init(profileVM: ProfileViewModel) {
        self.signing = EthereumSigningService(profileViewModel: profileVM)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Form {
                accountSection
                modeSection
                paramSection
                actionSection
                queryResultSection
                sendResultSection
            }
        }
        .navigationTitle("合约调用")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ContractCallView {

    // MARK: - 账号与链

    private var selectedAccount: AccountModel? { vm.selectedAccount }

    private var accountSection: some View {
        Section(header: Text("当前账号")) {
            if let account = selectedAccount {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.headline)
                    Text("[\(account.chain.symbol)] \(account.address)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } else {
                Text("请先在「我的」中选择账号")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var modeSection: some View {
        Section(header: Text("调用类型")) {
            Picker("类型", selection: $mode) {
                ForEach(CallMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: mode) { _ in
                errorMessage = nil
                queryResult = nil
            }
        }
    }

    // MARK: - 参数

    private var selectedFunction: AbiFunction? {
        parsedFunctions.indices.contains(selectedFunctionIdx) ? parsedFunctions[selectedFunctionIdx] : nil
    }

    private var paramSection: some View {
        Section(header: Text(mode == .erc20 ? "ERC20 参数" : "函数与参数")) {
            TextField("合约地址 (0x...)", text: $contractAddress)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            switch mode {
            case .erc20:
                TextField("收款地址 (0x...)", text: $recipient)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    TextField("金额", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("小数位", text: $decimalsText)
                        .keyboardType(.numberPad)
                        .frame(width: 70)
                }

            case .abi:
                abiInputSection
            }
        }
    }

    private var abiInputSection: some View {
        Group {
            TextField("函数签名 如 approve(address,uint256) returns (bool)，或粘贴 ABI JSON",
                      text: $abiText)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(refreshParsedFunctions)
            Button("解析签名 / ABI") {
                refreshParsedFunctions()
            }
            .font(.footnote)

            if let f = selectedFunction {
                // 重载/多函数时选择；单个函数也展示签名让用户确认
                if parsedFunctions.count > 1 {
                    Picker("函数", selection: $selectedFunctionIdx) {
                        ForEach(Array(parsedFunctions.enumerated()), id: \.offset) { idx, f in
                            Text(f.signature).tag(idx)
                        }
                    }
                    .onChange(of: selectedFunctionIdx) { _ in resetParams() }
                } else {
                    Text(f.signature)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if !f.inputTypes.isEmpty {
                    ForEach(f.inputTypes.indices, id: \.self) { i in
                        let name = f.inputNames.indices.contains(i) && !f.inputNames[i].isEmpty ? f.inputNames[i] : "参数\(i)"
                        TextField("\(name) : \(f.inputTypes[i])", text: bindingForParam(i))
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                if !f.isRead {
                    HStack {
                        TextField("附带主币数量（可选，如 0）", text: $valueText)
                            .keyboardType(.decimalPad)
                        Text("主币")
                            .foregroundColor(.secondary)
                    }
                }

                Text(f.isRead ? "该函数为只读（\(f.mutability)），可使用「查询」" : "该函数会改变链上状态，需发送交易")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func bindingForParam(_ i: Int) -> Binding<String> {
        Binding(
            get: { paramTexts.indices.contains(i) ? paramTexts[i] : "" },
            set: { newValue in
                if paramTexts.indices.contains(i) {
                    paramTexts[i] = newValue
                } else {
                    while paramTexts.count <= i { paramTexts.append("") }
                    paramTexts[i] = newValue
                }
            }
        )
    }

    // MARK: - 动作按钮

    private var actionSection: some View {
        Section {
            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("处理中…")
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    if mode == .abi {
                        Button {
                            query()
                        } label: {
                            Text("查询")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!canQuery)
                    }

                    Button {
                        send()
                    } label: {
                        Text("发送交易")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSend)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - 结果

    private var queryResultSection: some View {
        Group {
            if let lines = queryResult, !lines.isEmpty {
                Section(header: Text("查询结果")) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var sendResultSection: some View {
        Group {
            if let hash = txHash {
                Section(header: Text("广播成功 ✅")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("交易 Hash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(hash)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)

                        if let url = explorerURL(for: hash) {
                            Link("在浏览器查看", destination: url)
                                .font(.footnote)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 解析

    private func refreshParsedFunctions() {
        errorMessage = nil
        queryResult = nil
        let text = abiText.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("[") {
            let functions = Self.parseAbiJSONFunctions(text)
            if functions.isEmpty {
                errorMessage = "ABI JSON 解析失败或其中没有函数"
            }
            parsedFunctions = functions
        } else if text.contains("(") {
            if let f = Self.parseSignature(text) {
                parsedFunctions = [f]
            } else {
                parsedFunctions = []
                errorMessage = "函数签名格式无效，示例：approve(address,uint256) returns (bool)"
            }
        } else {
            parsedFunctions = []
            errorMessage = "请输入函数签名或以 [ 开头的 ABI JSON"
            return
        }
        selectedFunctionIdx = 0
        resetParams()
    }

    private func resetParams() {
        paramTexts = Array(repeating: "", count: selectedFunction?.inputTypes.count ?? 0)
        queryResult = nil
    }

    // MARK: - 构造 calldata

    /// 用 web3swift 编码 calldata；返回 "0x..."
    private func buildCalldata() -> (calldata: String?, error: String?) {
        guard isValidAddress(contractAddress) else { return (nil, "合约地址无效") }

        switch mode {
        case .erc20:
            return buildErc20Calldata()
        case .abi:
            return buildAbiCalldata()
        }
    }

    private func buildErc20Calldata() -> (calldata: String?, error: String?) {
        guard isValidAddress(recipient) else { return (nil, "收款地址无效") }
        guard let decimals = Int(decimalsText), decimals >= 0, decimals <= 36 else {
            return (nil, "小数位无效（0-36）")
        }
        guard let amountHex = Self.decimalToWeiHex(amount, decimals: decimals) else {
            return (nil, "金额无效")
        }
        // web3swift 编码：convertToBigUInt 原生接受十进制 / 0x hex 字符串
        return Self.encodeFunction(
            signature: "transfer(address,uint256)",
            inputTypes: ["address", "uint256"],
            values: [recipient, amountHex]
        )
    }

    private func buildAbiCalldata() -> (calldata: String?, error: String?) {
        guard let f = selectedFunction else {
            return (nil, "请先解析函数签名或 ABI JSON")
        }
        var values: [Any] = []
        for (i, type) in f.inputTypes.enumerated() {
            let text = paramTexts.indices.contains(i) ? paramTexts[i] : ""
            let converted = Self.convertParamValue(type: type, text: text, index: i)
            if let msg = converted.error { return (nil, msg) }
            values.append(converted.value!)
        }
        return Self.encodeFunction(
            signature: f.signature,
            inputTypes: f.inputTypes,
            values: values
        )
    }

    /// web3swift EthereumContract.method() 编码
    static func encodeFunction(signature: String, inputTypes: [String], values: [Any]) -> (calldata: String?, error: String?) {
        do {
            let contract = try EthereumContract(Self.abiJSON(for: signature, inputTypes: inputTypes))
            guard let data = contract.method(signature, parameters: values, extraData: nil), data.count >= 4 else {
                return (nil, "参数与类型不匹配，编码失败")
            }
            return ("0x" + data.hexString, nil)
        } catch {
            return (nil, "ABI 构造失败: \(error.localizedDescription)")
        }
    }

    /// 由签名合成最小 ABI JSON（EthereumContract 只接受 JSON）
    static func abiJSON(for signature: String, inputTypes: [String]) -> String {
        let name = signature.prefix(while: { $0 != "(" })
        let inputs = inputTypes.map { ["name": "", "type": $0] }
        let entry: [String: Any] = [
            "type": "function",
            "name": String(name),
            "inputs": inputs,
            "outputs": [],
            "stateMutability": "nonpayable",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: [entry]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    // MARK: - 查询（eth_call + 解码）

    private var canQuery: Bool {
        guard mode == .abi else { return false }
        guard let account = selectedAccount, account.chain.isEVM,
              !isBusy, isValidAddress(contractAddress) else { return false }
        return selectedFunction != nil
    }

    private func query() {
        guard let account = selectedAccount, let chainId = account.chain.eip155ChainId else {
            errorMessage = "当前账号不支持 EVM 调用"
            return
        }
        guard canQuery else { return }

        errorMessage = nil
        queryResult = nil
        txHash = nil
        isBusy = true

        let built = buildCalldata()
        if let message = built.error {
            isBusy = false
            errorMessage = message
            return
        }
        guard let calldata = built.calldata else {
            isBusy = false
            errorMessage = "calldata 构造失败"
            return
        }

        let callObject: [String: Any] = [
            "to": contractAddress.lowercased(),
            "data": calldata,
        ]

        Task { @MainActor in
            do {
                let result = try await EthRPCClient.shared.call(
                    chainId: chainId,
                    method: "eth_call",
                    params: [callObject, "latest"]
                )
                guard let hex = result as? String else {
                    throw EthRPCClient.RPCError.invalidResponse
                }
                if let f = selectedFunction {
                    queryResult = Self.decodeOutput(hex: hex, function: f)
                } else {
                    queryResult = [hex]
                }
                isBusy = false
            } catch {
                isBusy = false
                errorMessage = Self.describe(error: error)
            }
        }
    }

    /// web3swift decodeReturnData 解码返回值 → 可读行
    static func decodeOutput(hex: String, function: AbiFunction) -> [String] {
        guard hex.lowercased() != "0x", !hex.isEmpty else {
            return ["(返回为空：调用可能被 revert 或函数无返回值)"]
        }
        guard !function.outputTypes.isEmpty else {
            return ["(该函数未声明返回值类型，无法解码) 原始数据: \(hex)"]
        }
        do {
            let contract = try EthereumContract(Self.abiJSONWithOutputs(for: function))
            guard let data = Data(hexString: hex.stripHexPrefix()) else {
                return ["返回数据不是合法 hex: \(hex)"]
            }
            let decoded = try contract.decodeReturnData(function.signature, data: data)
            return formatDecoded(decoded, labels: function.outputTypes)
        } catch {
            return [describe(error: error)]
        }
    }

    static func formatDecoded(_ decoded: [String: Any], labels: [String]) -> [String] {
        var lines: [String] = []
        for i in labels.indices {
            let key = "\(i)"
            guard let v = decoded[key] else { continue }
            let label = "返回值\(i)"
            lines.append("\(label) = \(formatValue(v))")
        }
        if lines.isEmpty {
            lines = decoded.keys.sorted().map { "\($0) = \(formatValue(decoded[$0] ?? ""))" }
        }
        return lines
    }

    static func formatValue(_ v: Any) -> String {
        switch v {
        case let arr as [Any]:
            return "[" + arr.map { formatValue($0) }.joined(separator: ", ") + "]"
        case let b as Bool:
            return b ? "true" : "false"
        case let d as Data:
            return "0x" + d.hexString
        default:
            // BigUInt / BigInt / EthereumAddress / String 都有可读 description
            return String(describing: v)
        }
    }

    // MARK: - 发送交易

    private var canSend: Bool {
        guard let account = selectedAccount, account.chain.isEVM,
              !isBusy else { return false }
        switch mode {
        case .erc20:
            return isValidAddress(contractAddress) && isValidAddress(recipient) && !amount.isEmpty
        case .abi:
            return selectedFunction != nil
        }
    }

    private func send() {
        guard let account = selectedAccount, let chainId = account.chain.eip155ChainId else {
            errorMessage = "当前账号不支持 EVM 合约调用"
            return
        }

        errorMessage = nil
        txHash = nil
        queryResult = nil
        isBusy = true

        let built = buildCalldata()
        if let message = built.error {
            isBusy = false
            errorMessage = message
            return
        }
        guard let calldata = built.calldata else {
            isBusy = false
            errorMessage = "calldata 构造失败"
            return
        }

        var dict: [String: Any] = [
            "to": contractAddress,
            "data": calldata,
        ]
        // 附带主币（ERC20 模式固定 0）
        let nativeValue = mode == .abi ? (valueText.isEmpty ? "0" : valueText) : "0"
        if let valueHex = Self.decimalToWeiHex(nativeValue, decimals: 18) {
            dict["value"] = valueHex
        }
        guard let tx = WCTransaction(json: dict) else {
            isBusy = false
            errorMessage = "交易参数构造失败"
            return
        }

        signing.sendTransaction(tx, account: account, chainId: chainId) { result in
            isBusy = false
            switch result {
            case .success(let hash):
                txHash = hash
            case .failure(let error):
                errorMessage = Self.describe(error: error)
            }
        }
    }

    // MARK: - 错误描述（含 revert 原因解析）

    static func describe(error: Error) -> String {
        if let e = error as? Web3Error {
            switch e {
            case .revert(let msg, let reason):
                return reason ?? msg
            case .revertCustom(let sig, let args):
                let argsDesc = args.map { "\($0.key)=\(formatValue($0.value))" }.joined(separator: ", ")
                return "合约自定义错误 \(sig)(\(argsDesc))"
            case .inputError(let desc):
                return desc
            case .processingError(let desc):
                return desc
            default:
                return e.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - 签名 / ABI 解析

    /// 解析函数签名，如 "transfer(address,uint256) returns (bool)"
    /// 也兼容带参数名与存储说明的写法："transfer(address recipient, uint256 amount) returns (bool success)"
    static func parseSignature(_ text: String) -> AbiFunction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "(") else { return nil }
        let name = trimmed[trimmed.startIndex..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }

        // 找与 "(" 配对的 ")"
        var depth = 0
        var closeIdx: String.Index?
        var i = open
        while i < trimmed.endIndex {
            let ch = trimmed[i]
            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth == 0 { closeIdx = i; break }
            }
            i = trimmed.index(after: i)
        }
        guard let close = closeIdx else { return nil }

        let paramsStr = String(trimmed[trimmed.index(after: open)..<close])
        let rest = String(trimmed[trimmed.index(after: close)...])
        let restLower = rest.lowercased()

        var mutability = "nonpayable"
        if restLower.contains("view") { mutability = "view" }
        else if restLower.contains("pure") { mutability = "pure" }
        else if restLower.contains("payable") { mutability = "payable" }

        // outputs: "returns (uint256)" / "returns(uint256,bool)"
        var outputTypes: [String] = []
        if let rOpen = rest.firstIndex(of: "("), let rClose = rest.lastIndex(of: ")"), rClose > rOpen {
            let outStr = String(rest[rest.index(after: rOpen)..<rClose])
            outputTypes = splitTopLevel(outStr).compactMap { parseParam($0).type }
        }

        let inputs = splitTopLevel(paramsStr)
        var inputTypes: [String] = []
        var inputNames: [String] = []
        for p in inputs {
            let parsed = parseParam(p)
            inputTypes.append(parsed.type ?? "")
            inputNames.append(parsed.name)
        }
        let signature = "\(name)(\(inputTypes.joined(separator: ",")))"
        return AbiFunction(
            name: name,
            signature: signature,
            inputTypes: inputTypes,
            inputNames: inputNames,
            outputTypes: outputTypes,
            mutability: mutability
        )
    }

    /// 解析 ABI JSON 中的所有 function 条目
    static func parseAbiJSONFunctions(_ text: String) -> [AbiFunction] {
        guard let data = text.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var result: [AbiFunction] = []
        for entry in arr {
            if let t = entry["type"] as? String, t != "function" { continue }
            let name = entry["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            let inputDicts = entry["inputs"] as? [[String: Any]] ?? []
            let inputTypes = inputDicts.map { $0["type"] as? String ?? "" }
            let inputNames = inputDicts.map { $0["name"] as? String ?? "" }
            let outputTypes = (entry["outputs"] as? [[String: Any]] ?? []).map { $0["type"] as? String ?? "" }
            let mutability = entry["stateMutability"] as? String ?? "nonpayable"
            result.append(AbiFunction(
                name: name,
                signature: "\(name)(\(inputTypes.joined(separator: ",")))",
                inputTypes: inputTypes,
                inputNames: inputNames,
                outputTypes: outputTypes,
                mutability: mutability
            ))
        }
        return result
    }

    /// 按顶层逗号切分（跳过嵌套括号/数组内的逗号）
    static func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            if ch == "(" || ch == "[" { depth += 1 }
            if ch == ")" || ch == "]" { depth -= 1 }
            if ch == "," && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty || !parts.isEmpty {
            parts.append(current)
        }
        return parts
    }

    /// 单个参数 → (类型, 参数名)，容错 "address recipient"、"uint256 calldata amount"
    static func parseParam(_ p: String) -> (type: String?, name: String) {
        let words = p.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        let cleaned = words.filter { !["memory", "calldata", "storage", "indexed", "payable"].contains($0.lowercased()) }
        if cleaned.count >= 2 {
            return (cleaned[0], cleaned[1])
        }
        if cleaned.count == 1 {
            return (cleaned[0], "")
        }
        return (nil, "")
    }

    /// 含 outputs 的 ABI JSON（用于解码返回值）
    static func abiJSONWithOutputs(for f: AbiFunction) -> String {
        let inputs = f.inputTypes.enumerated().map { (i, t) -> [String: Any] in
            ["name": f.inputNames.indices.contains(i) ? f.inputNames[i] : "", "type": t]
        }
        let outputs = f.outputTypes.map { ["name": "", "type": $0] }
        let entry: [String: Any] = [
            "type": "function",
            "name": f.name,
            "inputs": inputs,
            "outputs": outputs,
            "stateMutability": f.mutability,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: [entry]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    // MARK: - 参数值转换

    /// 把用户输入文本转成 web3swift encodeParameters 接受的 Any
    /// （convertToBigUInt 原生接受十进制/0x hex 字符串，convertToData 接受 0x hex）
    static func convertParamValue(type: String, text: String, index: Int) -> (value: Any?, error: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let label = "参数\(index)"
        guard !trimmed.isEmpty else { return (nil, "\(label)不能为空") }

        // 数组类型 type[] / type[N]
        if type.hasSuffix("]") {
            guard let base = baseType(of: type) else { return (nil, "\(label)类型不支持: \(type)") }
            let elems = splitTopLevel(trimmed)
            var values: [Any] = []
            for (j, e) in elems.enumerated() {
                let converted = convertParamValue(type: base, text: e, index: index)
                if let msg = converted.error { return (nil, "\(label)[\(j)]: \(msg)") }
                values.append(converted.value!)
            }
            return (values, nil)
        }

        if type.hasPrefix("uint") || type.hasPrefix("int") {
            let lower = trimmed.lowercased()
            let isDecimal = trimmed.allSatisfy { $0.isNumber }
            let isNegativeDecimal = trimmed.hasPrefix("-") && trimmed.dropFirst().allSatisfy { $0.isNumber }
            let isHex = lower.hasPrefix("0x")
            guard isDecimal || isNegativeDecimal || isHex else {
                return (nil, "\(label)应为数字（十进制或 0x hex）")
            }
            return (trimmed, nil)
        }

        if type == "address" {
            guard trimmed.hasPrefix("0x"), trimmed.count == 42,
                  Data(hexString: trimmed.stripHexPrefix()) != nil else {
                return (nil, "\(label)应为 0x 开头的 20 字节地址")
            }
            return (trimmed, nil)
        }

        if type == "bool" {
            switch trimmed.lowercased() {
            case "true", "1": return (true, nil)
            case "false", "0": return (false, nil)
            default: return (nil, "\(label)应为 true / false")
            }
        }

        if type == "string" {
            return (trimmed, nil)
        }

        if type.hasPrefix("bytes") {
            guard trimmed.lowercased().hasPrefix("0x"),
                  Data(hexString: trimmed.stripHexPrefix()) != nil else {
                return (nil, "\(label)应为 0x 开头的 hex 数据")
            }
            return (trimmed, nil)
        }

        return (nil, "\(label)类型暂不支持: \(type)（tuple 请粘贴完整 ABI 并手动展开）")
    }

    /// "uint256[]" → "uint256"；"uint256[3]" → "uint256"
    static func baseType(of type: String) -> String? {
        guard type.hasSuffix("]"), let open = type.lastIndex(of: "[") else { return nil }
        return String(type[..<open])
    }

    // MARK: - 工具

    private func isValidAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("0x"), trimmed.count == 42 else { return false }
        return Data(hexString: trimmed.stripHexPrefix()) != nil
    }

    private func explorerURL(for hash: String) -> URL? {
        switch selectedAccount?.chain {
        case .bsc: return URL(string: "https://bscscan.com/tx/\(hash)")
        case .polygon: return URL(string: "https://polygonscan.com/tx/\(hash)")
        case .avalanche: return URL(string: "https://snowtrace.io/tx/\(hash)")
        default: return URL(string: "https://etherscan.io/tx/\(hash)")
        }
    }

    /// 十进制金额 → wei 的 hex quantity（纯字符串/字节运算，避免 Double 精度损失）
    /// 例：("1.5", 18) -> "0x14d1120d7b160000"
    static func decimalToWeiHex(_ amount: String, decimals: Int) -> String? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let intPart = parts[0]
        let fracPart = parts.count == 2 ? parts[1] : Substring()
        guard fracPart.count <= decimals else { return nil } // 精度超出，拒绝而不是静默截断

        // 拼出完整数字串（去掉小数点后补零到目标小数位）
        let digits = intPart + fracPart + String(repeating: "0", count: decimals - fracPart.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) else { return nil }

        // 十进制字符串 → 大端字节（逐位 乘10+加）
        var bytes: [UInt8] = [0]
        for ch in digits {
            let d = ch.wholeNumberValue!
            var carry = d
            for i in stride(from: bytes.count - 1, through: 0, by: -1) {
                let v = Int(bytes[i]) * 10 + carry
                bytes[i] = UInt8(v % 256)
                carry = v / 256
            }
            while carry > 0 {
                bytes.insert(UInt8(carry % 256), at: 0)
                carry /= 256
            }
        }
        while bytes.count > 1 && bytes.first == 0 { bytes.removeFirst() }
        return "0x" + Data(bytes).hexString
    }
}

#Preview {
    NavigationView {
        ContractCallView(profileVM: ProfileViewModel())
    }
}
