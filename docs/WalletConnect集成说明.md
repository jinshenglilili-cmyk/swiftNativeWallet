# WalletConnect（Reown）集成说明

> 生成日期：2026-10-14 · reown-swift 2.4.0 · WalletCore 4.7.0
> 本文档覆盖本次集成的全部新增/修改文件：每个文件干什么、每个方法做什么、关键实现细节与踩坑记录。

---

## 一、总体架构

App 同时扮演 WalletConnect 协议的两个角色：

```
┌─────────────────────────── SwiftfulCrypto App ───────────────────────────┐
│                                                                          │
│  【钱包端 WalletKit】被外部 dApp 连接                                      │
│  WalletConnectService ── 签名/交易 ──> EthereumSigningService ──> WalletCore│
│        │                                                    │            │
│        └────────────────> EthRPCClient（nonce/gas/广播）<────┘            │
│                                                                          │
│  【dApp 端 AppKit】连接外部钱包（MetaMask / Trust 等）                      │
│  ExternalWalletService ──> AppKit.instance.present()                     │
│                                                                          │
│  【浏览器端】DApp Browser（WKWebView + trust-min.js 注入）                  │
│  Web3RPCService（薄壳）── 复用同一个 EthereumSigningService / EthRPCClient │
└──────────────────────────────────────────────────────────────────────────┘
```

**核心设计**：签名与 RPC 能力收敛到 `Core/Web3/` 共享层，浏览器端、WalletConnect 钱包端、外部钱包 dApp 端三方复用；读私钥只有一条路径（`ProfileViewModel.requestPrivateKey`，强制生物识别）。

### 目录结构

```
SwiftfulCrypto/
├── Core/
│   ├── WalletConnect/                    ← 新增：钱包端 + dApp 端集成
│   │   ├── WalletConnectConfig.swift         集中配置（Project ID、元数据、支持链）
│   │   ├── Models/WCUIState.swift            UI 状态机 + 展示模型
│   │   ├── Services/
│   │   │   ├── WalletConnectService.swift    钱包端核心服务（本集成最大文件）
│   │   │   ├── ExternalWalletService.swift   dApp 端服务（连接外部钱包）
│   │   │   ├── WCDefaultCryptoProvider.swift CryptoProvider（WalletCore 实现）
│   │   │   └── WCWalletSocketFactory.swift   Relay WebSocket 工厂（URLSession 实现）
│   │   └── Views/
│   │       ├── WCPairView.swift              配对入口（粘贴/扫码 URI）
│   │       ├── WCProposalApprovalView.swift  会话提案审批页
│   │       ├── WCConnectionsView.swift       已连接 dApp 列表
│   │       └── QRScanner/QRScannerView.swift 二维码扫描
│   └── Web3/                             ← 新增：共享签名层
│       ├── Models/
│       │   ├── ChainType+Web3.swift          链类型扩展（isEVM / eip155ChainId）
│       │   └── WCTransaction.swift           dApp 交易参数模型
│       └── Services/
│           ├── EthRPCClient.swift            JSON-RPC POST 客户端
│           └── EthereumSigningService.swift  签名服务（personal_sign / 712 / 交易）
├── SwiftfulCrypto.entitlements           ← 新增：Keychain access group（防 -34018 崩溃）
└── （修改）MainTabView / ProfileView / BrowserTabView / PendingRequest /
           Web3RPCService / Info.plist / project.pbxproj
```

---

## 二、Core/WalletConnect/ —— 钱包端与 dApp 端

### 1. WalletConnectConfig.swift —— 集中配置

| 成员 | 说明 |
|---|---|
| `projectId` | Reown Cloud 的 Project ID（已填真实值 `3dd0dbdb…`）。占位符无效时 `configure` 不报错，但 Relay 连不上、pair 后无响应 |
| `redirectScheme = "swiftfulcrypto"` | 深链回调 scheme，已在 Info.plist `CFBundleURLTypes` 注册；dApp 完成操作后跳回 App 用 |
| `eip155References = ["1","56","137","43114"]` | 支持的 EVM 链（Ethereum / BSC / Polygon / Avalanche），CAIP-2 reference。是"单一事实来源"：提案校验、审批 namespace、切链校验都用它 |
| `makeMetadata()` | 构造本 App 在 WC 协议里的元数据（名称/描述/URL/图标/redirect）。`AppMetadata.Redirect` 是 throwing init，所以此方法 `throws` |

**WCBootstrap**（同文件）：
- `configureNetworkingIfNeeded()` —— `Networking.configure` 全局只执行一次（钱包端 WalletKit 和 dApp 端 AppKit 共用同一个 Relay 连接）。传入 `groupIdentifier: "group.com.yournamehere.SwiftfulCrypto"` 和自定义 `socketFactory`。
- ⚠️ 这个 `groupIdentifier` 会被 SDK 的 `KeychainStorage` 直接用作 `kSecAttrAccessGroup` —— 这是 entitlements 必须包含 `group.*` 条目的原因（见第八节）。

---

### 2. Models/WCUIState.swift —— 状态机与展示模型

**`WCFlowState`（enum, Equatable）** 配对/审批流 UI 状态机：
- `.idle` 空闲（可发起新配对）
- `.pairing` URI 已提交，等待 dApp 发起请求（配对页显示转圈）
- `.awaitingProposal` 提案已到达，等用户批准/拒绝
- `.connecting` 已批准，SDK 正在建立会话
- `.error(String)` 出错（配对页显示红字；**此状态允许直接重试**，不用重新进页面）
- `isActive` 计算属性：非 idle/error 均视为"进行中"，用于禁用重复提交按钮

**`WCSessionDisplay`** 会话列表行模型：从 SDK `Session` 提取 topic、dApp 名称/图标、账号（CAIP-10 数组）、过期时间；`expiryText` 格式化为 `yyyy-MM-dd`。

**`WCProposalDisplay`** 提案审批页模型：dApp 信息 + 请求的链/方法；`hasUnsupportedChain` 计算属性检查请求链是否都在 `eip155References` 内 —— 含不支持的链时审批页禁用"批准"按钮（避免 `approve` 时 namespace 校验失败）。

> 用独立展示模型而不是直接绑 SDK 类型，是为了 Preview 可注入假数据、UI 与 SDK 解耦。

---

### 3. Services/WalletConnectService.swift —— 钱包端核心（最重要）

`@MainActor` `ObservableObject`。职责：配对 → 提案审批 → SIWE 认证 → 会话请求（签名/交易/切链）→ 响应/断开。

#### Published 状态

| 属性 | 用途 |
|---|---|
| `flowState` | 驱动 WCPairView 的状态机 |
| `sessions: [WCSessionDisplay]` | 会话列表（已连接的 dApp 页数据源） |
| `proposal: WCProposalDisplay?` | 非 nil 时弹提案审批 sheet |
| `pendingRequest: PendingRequest?` | 非 nil 时弹签名请求 sheet（复用 SigningRequestView） |
| `alertMessage: String?` | 全局错误/成功提示（审批失败、签名失败等必须立即可见） |
| `pairSheetVisible: Bool` | 配对 sheet 是否打开 —— **两个 sheet 挂载点互斥的开关**（见第五节踩坑） |

#### 私有存储

- `wcRequests: [String: Request]` —— 普通 WC 请求的 SDK 原始 Request（respond 时需要 topic/requestId）
- `authRequests: [String: (request: AuthenticationRequest, payload: AuthPayload, message: String)]` —— SIWE 认证请求上下文。⚠️ SIWE 请求**不进** `wcRequests`，两套字典，审批入口要分别处理（曾经因此出现"点同意没反应"）

#### 生命周期方法

- **`configureIfNeeded()`**：主线程调用一次。顺序严格：`Networking.configure`（经 WCBootstrap）→ `WalletKit.configure(metadata:crypto:)` → **之后**才能订阅（否则收不到事件）。订阅五个 publisher：
  - `sessionProposalPublisher` → `handleProposal`（普通连接流程）
  - `sessionRequestPublisher` → `handleSessionRequest`（签名/交易请求）
  - `authenticateRequestPublisher` → `handleAuthRequest`（SIWE 登录请求）
  - `sessionDeletePublisher` / `sessionSettlePublisher` → `refreshSessions`
  - `NotificationCenter .wcAccountDeleted` → `disconnectSessions(containing:)`（删账号必须断会话，权限不残留）

#### 配对

- **`pair(uriString:)`**：`WalletConnectURI(string:)` 是**可失败初始化器（非 throws）**，过期/格式错都返回 nil 且日志误导。所以失败时调用 `pairFailureMessage` 区分两种情况。
- **`pairFailureMessage(uriString:)`**（static）：解析 URI query 里的 `expiryTimestamp`，已过期 → 提示"有效期 5 分钟，请重新生成"；否则 → "无效的配对链接"。

#### 会话提案（普通连接流程，非 SIWE）

- **`handleProposal(_:)`**：从 `requiredNamespaces` 提取链/方法构造 `WCProposalDisplay`；请求了不支持的链 → 直接 `rejectSession(.unsupportedChains)`（不弹审批页）；否则置 `proposal` 弹审批页。
- **`evmAccountForApproval()`**：所有审批入口的统一守卫 —— 无账号 → 提示"请先创建或选择一个账号"；账号非 EVM（如 Bitcoin）→ 提示"当前选中的是 BTC 账号，无法操作 EVM dApp"。避免静默失败。
- **`approveProposal()`**：为 `eip155References` 全部 4 条链构造 CAIP-10 账号，组一个 `SessionNamespace`（methods 含 personal_sign / eth_sign / eth_signTypedData(_v4) / eth_sendTransaction / eth_signTransaction / wallet_switchEthereumChain，events 含 chainChanged / accountsChanged），`approve(proposalId:namespaces:)`。成功后清 proposal、复位 flowState、刷新会话列表。
- **`rejectProposal()`**：`rejectSession(.userRejected)`。

#### SIWE 登录（wc_sessionAuthenticate）

lab.reown.com 等使用 SIWE 的 dApp 不走 proposal，而是发 `wc_sessionAuthenticate`：

- **`handleAuthRequest(_:)`**：
  1. `evmAccountForApproval()` 守卫
  2. `buildAuthPayload(payload:supportedEVMChains:supportedMethods: ["personal_sign"])` —— 按本钱包能力收敛 payload，recap 权限合并进 statement
  3. `formatAuthMessage(payload:account:)` —— 生成 CAIP-122 明文消息（"lab.reown.com wants you to sign in…"）
  4. 构造 `PendingRequest(method: "wc_sessionAuthenticate", parameters: [message])`（params[0] 是明文，PendingRequest.messagePreview 对此特判）
  5. 存入 `authRequests` 字典，置 `pendingRequest` 弹 SigningRequestView

- **`approveAuthRequest(_:)`**：
  1. 消息明文 → hex（`Data(message.utf8)` 逐字节 `%02x`）
  2. `signing.personalSign(...)` —— 走生物识别 + WalletCore（EIP-191 前缀由 signer 内部加）
  3. 成功 → `buildSignedAuthObject(authPayload:signature: CacaoSignature(t: .eip191, s: signature), account:)` 构建 Cacao → `approveSessionAuthenticate(requestId:auths:)`
  4. 成功后：刷新会话、**`flowState = .idle`**（复位配对页）、弹"登录已批准"
  5. 失败：`flowState = .error`（配对页红字可见）
  - ⚠️ 本版本 SDK **没有** `rejectSessionAuthenticate` API —— 拒绝 = 静默丢弃，dApp 端超时。

#### 会话请求（签名 / 交易 / 切链）

- **`handleSessionRequest(_:)`**：按 topic 找到 session 取 dApp 信息，构造 PendingRequest（`chainId` 存 CAIP-2），Request 存入 `wcRequests`，弹 SigningRequestView。
- **`approvePendingRequest()`**：总入口，先分流 SIWE（`wc_sessionAuthenticate` 走 `approveAuthRequest`，因为它的上下文在 `authRequests`），再按方法分发：
  - `personal_sign` / `eth_sign`：params[0] 为 hex 消息 → `signing.personalSign`
  - `eth_signTypedData(_v4)`：params[1] 为 JSON → `signing.signTypedData`
  - `eth_sendTransaction`：params[0] → `WCTransaction(json:)` → `signing.sendTransaction`（链优先用请求里的 chainId，回退账号所在链）
  - `eth_signTransaction`：**拒绝**（只签不广播可被重放，主流钱包同样不支持）码 4001
  - `wallet_switchEthereumChain` → `handleSwitchChain`
  - 其他 → -32601 Method not supported
- **`rejectPendingRequest()`**：普通请求回错误码 4001（EIP-1474 用户拒绝）；SIWE 请求丢弃并复位 flowState。
- **`handleSwitchChain(_:params:)`**：params[0].chainId 是 hex quantity（"0x38"）→ 解析整数；不在支持列表 → 4902（EIP-3085 unrecognized chain）；支持 → respond 成功 + `emitChainChanged`。
- **`emitChainChanged(reference:topic:)`**：`WalletKit.instance.emit` 发 `chainChanged` 事件，dApp 感知链已切换。

#### 会话管理

- **`refreshSessions()`**：`getSessions()` → `[WCSessionDisplay]`（杀 App 重启后 SDK 自持久化，onAppear 调用即可恢复列表）
- **`disconnect(_:)`** / **`disconnectAll()`**：`WalletKit.instance.disconnect(topic:)`
- **`disconnectSessions(containing:)`**：按地址（CAIP-10 尾段匹配，大小写不敏感）断开所有相关会话 —— 删账号时由通知触发

#### 响应辅助

- `respondResult(_:result:)`：签名成功 → respond value；失败 → -32000
- `respondSuccess(_:result:)` / `respondError(_:code:message:)`：`WalletKit.instance.respond(topic:requestId:response:)`，result 用 `AnyCodable(any:)` 包装（WalletCore 4.7.0 的 AnyCodable 需要 `any:` 标签）
- `numericId(of:)`：RPCID（Either<String, Int64>）→ Int64 的两个重载（Request 版 / RPCID 版）

#### 文件底部

`Notification.Name.wcAccountDeleted` 扩展 + userInfo["address"] 约定。

---

### 4. Services/ExternalWalletService.swift —— dApp 端（连接外部钱包）

`@MainActor` ObservableObject。App 作为 dApp 通过 AppKit 连 MetaMask/Trust 等。

- **`configureIfNeeded()`**：Networking（共用 WCBootstrap）→ `AppKit.configure(projectId:metadata:crypto:authRequestParams: nil)` → 订阅 `sessionSettlePublisher`（连接成功）/ `sessionDeletePublisher`（断开）/ `sessionResponsePublisher`（签名结果，`.response` 存 `lastSignResult`，`.error` 提示"签名被拒绝"）。
- **`presentWalletModal()`**：`AppKit.present(from: topViewController())` —— SDK 自带钱包列表模态（二维码 + 钱包跳转）。
- **`refreshSession()`**：取第一个 session 更新 `isConnected / walletName / address`。
- **`disconnect()`**：断开当前会话。
- **`personalSign(message:)`**：`AppKit.instance.request(.personal_sign(address:message:))` 发起签名验证，结果走 `sessionResponsePublisher` 异步回来。
- **`topViewController()`**（static）：遍历 UIWindowScene 找最顶层 VC —— SwiftUI 环境下 UIKit present 必需。

> BrowserTabView 顶部的「连接外部钱包」状态条（状态灯 + 连接/断开按钮 + 错误文案）就绑在这个服务上。

---

### 5. Services/WCDefaultCryptoProvider.swift —— 加密 Provider

reown-swift 要求注入 `CryptoProvider`，官方示例带 web3 库，这里用已有的 WalletCore 实现，零新依赖：

- **`keccak256(_:)`**：`Hash.keccak256(data:)` 直通。
- **`recoverPubKey(signature:message:)`**：SDK 内部验证 Cacao 签名时用。
  - 输入的 `EthereumSignature` 是 (r, s, v) 结构；WalletCore 的 `PublicKey.recover` 要求 65 字节紧凑格式 `[recid, r(32), s(32)]`，所以先做 `v & 0x01` 转换再拼接。
  - 恢复出的是 uncompressed 公钥（65 字节，`0x04` 开头）；SDK 侧按 `keccak256(pubKey).suffix(20)` 还原地址，需要 **64 字节裸公钥**，所以去掉前缀。

---

### 6. Services/WCWalletSocketFactory.swift —— Relay WebSocket

reown-swift 只定义 `WebSocketFactory` 协议不带实现（官方示例用 Starscream）。这里用系统 `URLSessionWebSocketTask`，避免多一个三方依赖：

- **`WCWalletSocketFactory.create(with:)`**：工厂方法，SDK 每次建连调用。
- **`WCWalletSocket`**（实现 `WebSocketConnecting`）：
  - `connect()`：创建 task、resume、挂起 `receiveNextMessage()` 循环
  - `disconnect()`：`cancel(with: .goingAway)`；⚠️ 用 `self.webSocketTask = nil` 先置空，避免 delegate 回调里属性遮蔽导致的状态混乱
  - `write(string:completion:)`：send 失败也调 completion（SDK 等待回调）
  - `receiveNextMessage()`：收到消息回调 `onText` 后**继续挂起下一次接收**（Relay 长连接依赖）；失败时区分主动断开（`webSocketTask == nil`，忽略）与意外断开（回调 `onDisconnect`，SDK 负责重连）
  - `URLSessionWebSocketDelegate`：didOpen → `onConnect`；didClose → `onDisconnect`
  - 配置细节：`timeoutIntervalForRequest = 60`、`timeoutIntervalForResource = .infinity`（长连接），专用 utility 队列串行化操作。

---

### 7. Views/WCPairView.swift —— 配对入口

「连接 dApp」页（我的 tab 进入的 sheet）：

- 输入行：`TextField`（"wc:..." 占位、monospaced、禁自动大写/纠错）+ **粘贴按钮**（`UIPasteboard.general.string` 读剪贴板 —— 模拟器长按粘贴菜单经常失灵，显式按钮可靠）
- 状态区：`.pairing` 显示转圈"正在等待 dApp 响应…"；`.error` 显示红字
- 「连接」按钮：`canPair` 控制 —— flowState 在 pairing/awaitingProposal/connecting 时禁用（防重复提交）；**idle 和 error 都允许**（出错后改链接直接重试）
- 「扫描二维码」：弹 `QRScannerView`
- **sheet 内再挂审批弹窗**：`.modifier(WCApprovalSheets(...))` —— 配对 sheet 打开时到达的 SIWE 请求要盖在本 sheet 之上（根部的弹不上来）
- **`pairSheetVisible` 生命周期**：`onAppear` 置 true / `onDisappear` 置 false —— 让根部挂载点在配对页打开期间休眠，避免两处抢同一绑定导致审批页闪现后消失
- `@EnvironmentObject profileVM`：给 WCApprovalSheets 提供 `selectedAccount?.address`

---

### 8. Views/WCProposalApprovalView.swift —— 提案审批页

纯回调式 UI（`onApprove` / `onReject` 闭包，逻辑全在 Service）：
- dApp 图标（AsyncImage）/ 名称 / URL
- **请求的链**：逐条显示 ✓/✗（对照 `eip155References`）
- 请求的权限（methods 列表）、连接账号地址
- `hasUnsupportedChain` 时显示橙色警告并禁用批准按钮
- 拒绝（红）/ 批准（主题色）双按钮

### 9. Views/WCConnectionsView.swift —— 已连接 dApp 列表

- `InsetGroupedListStyle` + 主题色行背景（对齐 ProfileView 风格）
- 空状态：`listRowSeparator(.hidden)` 的引导卡片（图标 + "暂无已连接的 dApp" + 操作指引）
- 会话行：图标、名称、地址缩略（`shortAddress`：CAIP-10 → `0xAb…1234` 中间省略）、有效期、"断开"按钮（`BorderlessButtonStyle` 防整行误触）
- `onAppear { service.refreshSessions() }` —— 杀 App 重启后进来即恢复

### 10. Views/QRScanner/QRScannerView.swift —— 二维码扫描

`UIViewControllerRepresentable` 包装 `AVCaptureSession`：
- `makeUIViewController` → `ScannerViewController`（注入 `onCodeScanned` 回调）
- `ScannerViewController.setupCamera()`：摄像头输入 + `AVCaptureMetadataOutput`（`.qr`）+ 预览层铺满
- 识别成功 → 主线程回调一次并停会话；`viewWillDisappear` 停止采集释放相机
- 无摄像头/权限被拒 → 页面内显示错误文案
- ⚠️ 模拟器没有摄像头，扫码仅真机可用；`previewLayer.frame` 使用 `[.flexibleWidth, .flexibleLeftMargin, .flexibleRightMargin]` 自适应

---

## 三、Core/Web3/ —— 共享签名层（浏览器 + WC 两端复用）

### 1. Services/EthRPCClient.swift —— JSON-RPC POST 客户端

**背景**：旧 `Web3RPCService.forwardToRPC` 复用了 GET 语义的 `NetworkingManager.download`，POST body 根本没发出去。本类是真正的 JSON-RPC 客户端，浏览器与 WC 共用单例 `shared`。

- `endpoints: [Int: String]` —— 4 条链的公共 RPC（从 Web3RPCService 迁出成为单一来源）
- **`call(chainId:method:params:)`**：核心。组装 `{jsonrpc, id, method, params}` → **真 POST** → 解析响应；`error` 字段抛 `RPCError.rpcError(code:message:)`；result 为 NSNull 原样返回（切链成功响应就是 null）
- 高层封装（全部基于 `call`）：
  - `getTransactionCount(address:chainId:)` —— `eth_getTransactionCount("pending")`，含待确认交易的 nonce
  - `gasPrice(chainId:)` —— `eth_gasPrice`
  - `maxPriorityFeePerGas(chainId:)` —— 部分公共 RPC 不支持（报错）→ 调用方捕获后回退 legacy 模式
  - `estimateGas(tx:chainId:)` —— 失败回退 21000（普通转账标准值）
  - `sendRawTransaction(rawTxHex:chainId:)` —— 自动补 `0x`，返回交易 hash
- Hex 工具（static）：
  - `parseHexQuantity(_:)` —— "0x1a"/"0x0"/十进制字符串 → UInt64
  - `bigEndianData(...)` —— hex/UInt64 → **最小大端字节**（0 编码为空 Data，符合 RLP 语义；WalletCore 签名输入要求大端 Data 而非字符串）

### 2. Services/EthereumSigningService.swift —— 签名服务

三方共用的唯一签名实现。`final class`（非 MainActor，签名回调内部自行跳线程）。

- **`personalSign(messageHex:account:completion:)`**：hex → 明文（`EthereumMessageSigner.signMessage` **内部加 EIP-191 前缀**，不要自己加）→ 签名 → **统一补 `0x` 前缀**（WalletCore 返回裸 hex，dApp/SDK 验证按 ethers 习惯要求 `0x` 开头 —— 这是 SIWE 登录 dApp 端"没反应"的修复点）
- **`signTypedData(typedDataJSON:account:completion:)`**：EIP-712，`signTypedMessage(messageJson:)`，同样补 `0x`
- **`sendTransaction(_:account:chainId:completion:)`**：完整交易流程（见下）
- **`requestKey(account:completion:)`**：读私钥统一入口 —— `profileViewModel.requestPrivateKey`（生物识别）→ hex → `PrivateKey(data:)`；失败回调 `(nil, 具体原因)`。错误原因细分：取消 / 未录入生物识别 / 观察账号无密钥 / 私钥数据无效（曾经"取消"和"无密钥"混在一个错误里无法定位，已拆开）
- **`ensureHexPrefix(_:)`**（static）：`0x` 前缀规整

**`sendTransaction` → `signAndBroadcast`**（async）六步：
1. **nonce**：dApp 提供了用 dApp 的；否则 `getTransactionCount(pending)`
2. **gas limit**：dApp 提供了用 dApp 的；否则 estimateGas（失败回退 21000）
3. **费用模式**：dApp 指定 1559 字段 → enveloped；否则探测 `maxPriorityFeePerGas`（支持 → maxFee = gasPrice×2；不支持/legacy 字段 → gasPrice 模式，兼容 BSC 部分节点）
4. **构造 `TW_Ethereum_Proto_SigningInput`**：chainID/nonce/gasLimit/toAddress/privateKey 全是大端 Data；`callData` 为空 → `.transfer`（纯转账），否则 `.contractGeneric`（合约调用）；`txMode` 按第 3 步
5. **`AnySigner.sign`**：`output.error != .ok` 抛 signingFailed
6. **`eth_sendRawTransaction`** 广播 → 返回 hash

### 3. Models/WCTransaction.swift —— 交易参数模型

dApp 传来 `eth_sendTransaction` params[0]（所有数值为 hex quantity 字符串）：
- 字段：`from / to / valueHex(wei) / dataHex / gasHex(gas 或 gasLimit) / gasPriceHex / maxFeePerGasHex / maxPriorityFeePerGasHex / nonceHex`
- `init?(json:)`：可失败 —— 缺 `to` 视为非法请求（respond -32602）
- `isContractCall`：带非空 data 即合约调用

### 4. Models/ChainType+Web3.swift —— 链类型扩展

- **`isEVM`**：ethereum/bsc/avalanche/polygon → true；bitcoin/solana/tron → false。用于 `evmAccountForApproval` 守卫和交易前置校验
- **`eip155ChainId`**：EVM 链的 EIP-155 ID（1/56/137/43114）；非 EVM 返回 nil

---

## 四、修改的既有文件

| 文件 | 改动 |
|---|---|
| **MainTabView.swift** | ① 创建 `profileVM` + `wcService`（持有 profileVM）+ `externalWalletService`，三者 `.environmentObject` 注入；② 根部挂 `WCApprovalSheets` 修饰器（`suppressed: wcService.pairSheetVisible`）；③ `onAppear` 配置两个服务 |
| **MainTabView.swift 内 `WCApprovalSheets`（ViewModifier）** | 审批弹窗统一挂载点：签名请求 sheet + 提案 sheet + 全局 alert。`suppressed` 为 true 时三个绑定的 get 恒为 nil（本挂载点休眠不弹）。**根部与 WCPairView 各挂一份、用 pairSheetVisible 互斥**：根部弹不到已打开 sheet 的上层（SwiftUI 限制），两处同时抢绑定又会闪现后消失 |
| **ProfileView.swift** | 「常用功能」区新增：已连接的 dApp（带会话数角标）、连接 dApp（扫码/粘贴）两行；两个 sheet（WCPairView / WCConnectionsView）；无账号时「转账/导出」行整行不渲染（原 `.opacity(0)` 会留空白行）、占位区显示"暂无账号"引导 |
| **BrowserTabView.swift** | 顶部 externalWalletBar：状态灯（绿/灰）、「连接外部钱包」按钮 → `presentWalletModal`、已连接显示钱包名 + 断开、错误文案 |
| **PendingRequest.swift** | `chainId: String?`（WC 端存 CAIP-2 "eip155:1"，浏览器端存数字字符串）；加 `dAppName` / `dAppIconURL`；`messagePreview` 对 `wc_sessionAuthenticate` 特判（params[0] 是明文，不走 hex 解码）；`transactionSummary` 供签名页展示收款地址/金额/data |
| **Web3RPCService.swift** | 薄壳化：签名方法体删除、转发注入的 `EthereumSigningService`；只读请求转发 `EthRPCClient`（真 POST）；删除旧 `defaultRPCEndpoints`；`handleIncomingRPC` 每次同步 `selectedAccount = profileViewModel?.selectedAccount` |
| **Info.plist** | `NSCameraUsageDescription`（扫码）；`CFBundleURLTypes` 注册 scheme `swiftfulcrypto` |
| **project.pbxproj** | target 级 `packageProductDependencies`（WalletCore / WalletCoreSwiftProtobuf / ReownWalletKit / ReownAppKit）；`CODE_SIGN_ENTITLEMENTS` 指向 entitlements；注册新文件 |

---

## 五、配置文件

### SwiftfulCrypto.entitlements（新增，关键）

```xml
keychain-access-groups:
  - group.com.yournamehere.SwiftfulCrypto        ← SDK Keychain 的 access group
  - $(AppIdentifierPrefix)com.yournamehere.SwiftfulCrypto
com.apple.security.application-groups:
  - group.com.yournamehere.SwiftfulCrypto
```

**为什么必须有 `group.*` 这一条**：reown-swift 的 `KeychainStorage` 把 `Networking.configure` 传入的 `groupIdentifier` 原样用作 `kSecAttrAccessGroup`。iOS 17+ 模拟器严格执行 access group 校验，entitlements 里没有对应条目 → 启动即 `EXC_BREAKPOINT` + OSStatus **-34018** 崩溃（errSecMissingEntitlement）。

---

## 六、关键流程时序

### SIWE 登录（lab.reown.com 实测通过的主链路）

```
dApp(lab.reown.com)                     Wallet(WalletConnectService)
   │ Connect 复制 URI                        │
   │ ─────────── wc: URI（5分钟有效）────────>│ pair() → WalletKit.pair
   │                                        │ ⏳ flowState = .pairing
   │ ── wc_sessionAuthenticate (Relay) ────> │ authenticateRequestPublisher
   │                                        │ buildAuthPayload → formatAuthMessage
   │                                        │ 弹 SigningRequestView（CAIP-122 明文）
   │                                        │ 用户点同意 ↓
   │                                        │ personalSign（人脸 → WalletCore EIP-191）
   │                                        │ buildSignedAuthObject → Cacao
   │ <──────── approveSessionAuthenticate ── │ flowState = .idle，弹「登录已批准」
   │ 验证签名（要求 0x 前缀）→ 会话建立         │ sessionSettle → refreshSessions
```

### 普通会话请求（Sign Message 等）

```
dApp ── personal_sign ──> handleSessionRequest ──> 弹 SigningRequestView
   用户同意 → evmAccountForApproval → signing.personalSign（人脸）
   成功 → respond(topic, requestId, .response(AnyCodable)) ；失败 → -32000
   用户拒绝 → respond .error(4001)
```

### 真实转账（eth_sendTransaction）

```
弹 SigningRequestView（transactionSummary 显示 to/value/data）
   → 同意 → 人脸 → 读私钥 → 并行取 nonce/gas/estimateGas（各有回退）
   → 探测 1559 → WalletCore 构造+签名（EIP-155 replay 保护）
   → eth_sendRawTransaction 广播 → hash 回给 dApp
```

---

## 七、踩坑记录（重要，改代码前先看）

| # | 坑 | 原因 | 修复 |
|---|---|---|---|
| 1 | 启动即崩溃 -34018 | SDK 用 `group.*` 作 Keychain access group，entitlements 缺条目 | entitlements 加 `group.com.yournamehere.SwiftfulCrypto` |
| 2 | "URI 格式无效"实为过期 | `WalletConnectURI(string:)` 可失败初始化器把过期也当格式错；**URI 只有 5 分钟有效期** | `pairFailureMessage` 解析 expiryTimestamp 区分 |
| 3 | 点同意没反应（SIWE） | ① SIWE 请求存在 `authRequests`，`approvePendingRequest` 的 guard 查的是 `wcRequests`；② 选中账号是 Bitcoin/观察账号；③ Face ID 未录入静默失败 | 审批入口先分流 SIWE；`evmAccountForApproval` 守卫；错误全部上浮到 alert |
| 4 | 审批页闪现后消失 | 根部与配对页两个 `.sheet` 抢同一 `pendingRequest` 绑定 | `pairSheetVisible` 互斥：配对页打开时根部挂载点休眠 |
| 5 | 审批页弹不出来（转圈卡死） | 根部 sheet 盖不到已打开的 sheet 上 | 同上（配对页内也挂 WCApprovalSheets） |
| 6 | 批准后 dApp 没反应 | WalletCore 签名返回**裸 hex**，dApp/SDK 要求 `0x` 前缀 | `ensureHexPrefix` 统一补前缀 |
| 7 | 批准后配对页永远转圈 | flowState 停在 `.pairing` 没人复位 | 认证流程成功/失败/拒绝均复位 `.idle` |
| 8 | 签名失败原因无法定位 | "用户取消"与"私钥不可用"合并成同一错误 | `requestPrivateKey` 携带具体 failure 原因 |
| 9 | SPM 拉不下 yttrium 二进制 | SPM 的 URLSession 不走终端代理 | curl 预热 `~/Library/Caches/org.swiftpm` 二进制缓存（SHA256 需与 Package.swift 一致） |
| 10 | entitlements"没生效" | DerivedData 有两个容器，旧二进制误导 | 以 `-dybjmmeswgttuvbptlcjxywcbndq` 容器为准；`otool -s __TEXT __entitlements` 验证 |

---

## 八、测试指南

### 模拟器端到端（当前验证状态）

前提：模拟器菜单 **Features → Face ID → Enrolled**（必做，否则所有签名静默失败）。

1. 「我的」→ **助记词创建账号**（链选 Ethereum；⚠️ 手动填地址的是观察账号，签不了名）→ 创建后自动选中
2. lab.reown.com → Connect Wallet → WalletConnect → 复制 URI（**5 分钟内用掉**）
3. App「我的」→ 连接 dApp → 点**粘贴按钮** → 连接
4. dApp 授权 → 审批页同意 → 人脸弹窗出现时点 **Features → Face ID → Matching Face**
5. 浏览器自动登录 → 依次验证 Sign Message / Sign Typed Data / Switch Chain
6. **Send Transaction**：需要地址上有主网 gas；没币时告诉我把测试网（Sepolia 等）加入支持链
7. 杀 App 重启 →「已连接的 dApp」应恢复会话

### 真机补充

- 扫码配对、Face ID、深链跳回（redirect scheme）需真机验证
- 国内网络 Relay 可能不稳：无响应先查代理

### 排查手段

- 关键节点都有 `NSLog("[WC] …")`（pair / 收到请求 / 签名 / 批准），走系统日志，`log stream --predicate 'process == "SwiftfulCrypto"'` 可实时查看
- 签名/审批失败均弹全局「提示」alert，不再静默
