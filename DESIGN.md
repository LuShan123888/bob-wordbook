# 设计文档

## 1. 项目背景

### 问题

使用 [Bob](https://bobtranslate.com/) 查词时，希望将生词自动收集到扇贝单词本以便后续复习。现有方案（[wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin)）需要用户手动从浏览器 DevTools 复制 `auth_token` 并粘贴到插件设置中，存在以下痛点：

1. **操作繁琐**：需要打开浏览器 DevTools → Application → Cookies → 复制 token → 粘贴到 Bob 设置
2. **频繁失效**：扇贝的 `auth_token` 会过期，每隔一段时间就需要重新操作
3. **体验差**：用户需要理解 cookie 的概念，门槛较高

### 目标

实现「零感知」的单词收集体验：用户只需在 Bob 中正常查词，单词自动同步到扇贝，无需任何手动配置 token 的操作。

## 2. 技术方案

### 整体架构

```
用户查词 → Bob 插件 → 读取沙箱 token → 调扇贝 API → 添加到单词本
                        ↑
              Swift Helper (定时刷新)
                        ↑
              浏览器 Cookie 存储
```

### 2.1 Bob 插件（JavaScript）

**运行环境**：Bob 的 JavaScriptCore 引擎，非浏览器/Node.js 环境。

**核心流程**：
1. 拦截 Bob 的 `translate()` 调用
2. 判断是否为英文单词（`detectFrom === "en"`）
3. 读取 auth_token（优先级见下文）
4. 调用扇贝 API `POST /wordscollection/words_bulk_upload`
5. 返回添加结果

**Token 获取优先级**：
1. **自动提取**：从 `$sandbox/shanbay_auth_token` 文件读取（由 Swift helper 写入）
2. **手动配置**：从 `$option.auth_token` 读取（用户在设置中手动填写）

**扇贝 API 详情**：
- Endpoint: `https://apiv3.shanbay.com/wordscollection/words_bulk_upload`
- Method: POST
- Header: `Cookie: auth_token=<token>`
- Body: `{"business_id": 6, "words": ["word1"]}`

### 2.2 Swift Cookie Helper

**功能**：从浏览器 Cookie 存储中提取扇贝的 `auth_token`。

**支持浏览器**：

| 浏览器 | Cookie 格式 | 加密方式 | 提取难度 |
|--------|------------|---------|---------|
| Chrome | SQLite + AES-128-CBC | PBKDF2 密钥派生 + Keychain | 中等 |
| Edge | SQLite + AES-128-CBC | 同 Chrome | 中等 |
| Firefox | SQLite 明文 | 无加密 | 简单 |

**Chrome Cookie 解密流程**：
1. 读取 `~/Library/Application Support/Google/Chrome/Default/Cookies`（SQLite）
2. 查询 `cookies` 表中 `host_key LIKE '%shanbay.com%' AND name = 'auth_token'`
3. 获取 `encrypted_value`（二进制 blob，前缀 `v10`）
4. 从 macOS Keychain 获取密码：
   - Service: `Chrome Safe Storage`
   - Account: `Chrome`
5. PBKDF2-HMAC-SHA1 派生 AES 密钥：
   - Salt: `"saltysalt"` (ASCII)
   - Iterations: `1003`
   - Key length: `16 bytes`
6. AES-128-CBC 解密：
   - IV: 16 bytes of `0x20`
   - Padding: PKCS7
7. 解密结果即为 `auth_token` 明文

**实现选择**：
- 使用 Swift + CryptoKit 实现 PBKDF2（纯 Swift，无需 CommonCrypto）
- 使用 macOS 自带 `openssl` 命令行执行 AES-CBC 解密（避免 CommonCrypto 模块导入问题）
- 使用 SQLite3 C API 直接读取 cookie 数据库

### 2.3 定时刷新（LaunchAgent）

通过 macOS LaunchAgent 实现每 30 分钟自动刷新：

```xml
<key>StartInterval</key>
<integer>1800</integer>
<key>RunAtLoad</key>
<true/>
```

- 安装路径：`~/Library/LaunchAgents/com.shanbay-cookie-helper.refresh.plist`
- 日志：`/tmp/shanbay-cookie-helper.log`

### 2.4 文件通信机制

Swift helper 和 Bob 插件通过文件系统通信：

- **写入方**（Swift helper）：`~/Library/Containers/com.hezongyidev.Bob/Data/Documents/InstalledPluginSandbox/shanbay_auth_token`
- **读取方**（Bob 插件）：`$sandbox/shanbay_auth_token`

两个路径指向同一物理位置。Bob 插件的 `$sandbox/` 前缀在运行时由 Bob 映射到实际沙箱路径。

## 3. 安全性考虑

1. **Keychain 授权**：首次运行时系统会弹出 Keychain 访问对话框，用户需授权
2. **Token 本地存储**：auth_token 仅存储在本地文件系统，不上传到任何第三方服务
3. **最小权限**：Swift helper 仅读取特定域名（shanbay.com）的特定 cookie
4. **数据库复制**：读取浏览器 cookie 数据库前先复制到临时目录，避免锁冲突
5. **手动 token 使用 `secure` 类型**：在 Bob 插件设置中以密码输入框显示

## 4. 故障排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| helper 提取失败 | 未登录扇贝 | 在浏览器中登录 shanbay.com |
| helper 提取失败 | Keychain 拒绝 | 在 Keychain Access 中检查 Chrome Safe Storage 权限 |
| 插件验证失败 | token 过期 | 手动运行 `shanbay-cookie-helper` 刷新 |
| LaunchAgent 未运行 | plist 错误 | 检查 `launchctl list \| grep shanbay` |
| 插件找不到 token | 沙箱路径不匹配 | 确认 Bob 安装方式（App Store / DMG） |

## 5. 局限性

1. **Safari 不支持**：Safari cookie 存储格式为私有二进制格式，且受 App Sandbox 严格保护，无法从外部读取
2. **Bob 非沙箱版本**：如果 Bob 通过 DMG 直接安装（非 App Store），沙箱路径可能不同
3. **Chrome 多用户**：仅扫描 `Default` 和 `Profile *` 目录下的第一个有效 cookie
4. **首次 Keychain 授权**：LaunchAgent 在后台运行时可能无法弹出 Keychain 授权窗口，建议先手动运行一次 `shanbay-cookie-helper`
