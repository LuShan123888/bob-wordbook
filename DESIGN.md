# 设计文档

## 1. 项目背景

### 问题

使用 [Bob](https://bobtranslate.com/) 查词时，希望将生词自动收集起来以便后续复习。现有方案（[wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin)）存在以下痛点：

1. **手动复制 token**：需要从浏览器 DevTools 复制 `auth_token` 到插件设置
2. **频繁失效**：扇贝 `auth_token` 会过期，需反复操作
3. **单一存储**：仅支持扇贝，无法保存到本地知识库（如 Obsidian）

### 目标

实现「零感知」的单词收集体验，支持多目标存储：

1. **扇贝单词本**：即时同步，用于间隔重复学习
2. **本地 Markdown 单词本**：以表格形式记录，支持时间追踪，可集成到 Obsidian 等知识库

## 2. 技术方案

### 2.1 整体架构

```
用户查词 → Bob 插件 → 扇贝 API（即时）+ 写入队列（即时）
                              ↓
                    LaunchAgent 每 1 分钟
                              ↓
                    helper 读取队列 → 写入 Markdown + 刷新 token
```

**为什么用队列而不是直接写 Markdown？**

Bob 插件运行在 JavaScriptCore 沙箱中，只能写入 `$sandbox/` 目录。用户的 Markdown 单词本通常在 Obsidian vault 等位置，插件无法直接写入。因此通过队列 + helper 的方式间接实现。

### 2.2 Bob 插件（JavaScript）

**运行环境**：Bob 的 JavaScriptCore 引擎，非浏览器/Node.js 环境。

**核心流程**：
1. 拦截 `translate()` 调用，判断是否为英文单词
2. **扇贝同步**（即时）：读取沙箱中的 `auth_token`，调用扇贝 API
3. **队列写入**（即时）：将单词写入 `$sandbox/word_queue.jsonl`

**队列格式**（JSONL）：
```json
{"word":"serendipity","time":"2026-04-05T14:30:00+08:00"}
{"word":"ephemeral","time":"2026-04-05T15:02:00+08:00"}
```

**Token 获取优先级**：
1. 自动提取：从 `$sandbox/shanbay_auth_token`（helper 写入）
2. 手动配置：从 `$option.shanbei_auth_token`（用户在设置中填写）

**扇贝 API**：
- `POST https://apiv3.shanbay.com/wordscollection/words_bulk_upload`
- Header: `Cookie: auth_token=<token>`
- Body: `{"business_id": 6, "words": ["word"]}`

### 2.3 Swift Helper（bob-wordbook-helper）

**功能**：定时处理单词队列、提取浏览器 Cookie、更新 Markdown 文件。

**子命令**：

| 命令 | 功能 |
|------|------|
| （无参数）| 提取 token + 处理队列 |
| `extract` | 仅提取扇贝 token |
| `process` | 仅处理单词队列 |
| `init` | 初始化配置（设置 Markdown 路径） |
| `install` | 安装 LaunchAgent |
| `uninstall` | 卸载 LaunchAgent |

**配置文件**：`~/.config/bob-wordbook/config.json`
```json
{
  "markdown_path": "/Users/cian/Notes/wordbook.md"
}
```

### 2.4 Markdown 单词本

**表格格式**：
```markdown
| Word | Created | Updated |
|:-----|:--------|:--------|
| serendipity | 2026-04-05 14:30 | 2026-04-07 10:15 |
| ephemeral | 2026-04-05 15:02 | 2026-04-05 15:02 |
```

**列说明**：
- **Word**：单词（自动转小写）
- **Created**：首次遇到该单词的时间
- **Updated**：最近一次遇到的时间

**去重逻辑**：
- 新单词：Created = Updated = 当前时间，插入新行
- 已有单词：保留 Created，更新 Updated，行移动到表格顶部
- 同一批次中的重复单词：仅保留最后一次

**排序**：按 Updated 时间倒序（最近遇到的单词在最上面）

### 2.5 Chrome Cookie 解密

Chrome 在 macOS 上使用 AES-128-CBC 加密 cookie：

1. 从 macOS Keychain 获取密码（service: `Chrome Safe Storage`, account: `Chrome`）
2. PBKDF2-HMAC-SHA1 派生 AES 密钥（salt: `saltysalt`, iterations: 1003, key length: 16）
3. IV = 16 bytes of `0x20`
4. 密文前缀 `v10`，去掉前缀后为 AES-CBC 密文
5. 实现方式：CryptoKit (PBKDF2/HMAC) + openssl CLI (AES-CBC)

Firefox cookie 为明文存储，直接读取 SQLite。

### 2.6 LaunchAgent

```xml
<key>StartInterval</key>
<integer>60</integer>    <!-- 每 1 分钟 -->
<key>RunAtLoad</key>
<true/>                  <!-- 登录时立即运行 -->
```

安装路径：`~/Library/LaunchAgents/com.bob-wordbook-helper.refresh.plist`

## 3. 安全性

1. **Keychain 授权**：首次运行弹出授权窗口，用户需允许
2. **本地存储**：token 仅存于本地，不上传第三方
3. **最小权限**：仅读取 `shanbay.com` 的 `auth_token` cookie
4. **数据库复制**：复制到临时目录后读取，避免锁冲突

## 4. 故障排查

| 问题 | 解决方案 |
|------|---------|
| helper 提取失败 | 在浏览器中登录 shanbay.com |
| Keychain 拒绝 | Keychain Access → 检查 Chrome Safe Storage 权限 |
| 扇贝验证失败 | 手动运行 `bob-wordbook-helper extract` |
| Markdown 未更新 | 检查 `~/.config/bob-wordbook/config.json` 中的路径 |
| LaunchAgent 未运行 | `launchctl list \| grep bob-wordbook` |

## 5. 局限性

1. **Safari 不支持**：Cookie 格式私有且受沙箱保护
2. **Markdown 延迟**：最长 1 分钟延迟（LaunchAgent 间隔）
3. **Bob 非沙箱版本**：DMG 安装的 Bob 沙箱路径可能不同
4. **首次 Keychain 授权**：后台 LaunchAgent 可能无法弹出授权窗口，建议先手动运行一次
