# bob-wordbook 设计规划文档

## 1. 项目定位

bob-wordbook 是一个 Bob 翻译插件的单词收集工具。在 Bob 中查词时，自动将英文单词同步到扇贝单词本（即时）和本地 Markdown 文件（延迟 1 分钟），实现「零感知」的生词收集体验。

### 1.1 目标用户

使用 Bob 查词、同时希望系统化收集生词进行复习的英语学习者。

### 1.2 核心价值

| 价值 | 说明 |
|------|------|
| 零感知收集 | 查词即收集，无需额外操作 |
| 双目标存储 | 扇贝（即时，用于间隔重复）+ 本地 Markdown（可放 Obsidian 等知识库） |
| 自动 Token 管理 | 从浏览器自动提取 Cookie，LaunchAgent 定时刷新，无需手动复制 |
| 时间追踪 | Created + Updated 双时间戳，遗忘曲线一目了然 |

---

## 2. 当前架构（v2.0）

### 2.1 整体架构

```
用户查词 → Bob 插件 → 扇贝 API（即时）+ 写入队列（即时）
                              ↓
                    LaunchAgent 每 1 分钟
                              ↓
                    helper 读取队列 → 写入 Markdown + 刷新 token
```

```
┌──────────────────────────────────────────────────────┐
│                    Bob 翻译软件                        │
│  ┌────────────────────────────────────────────────┐  │
│  │           Bob 插件 (JavaScript)                 │  │
│  │                                                │  │
│  │  1. 调用扇贝 API 添加单词（即时）               │  │
│  │  2. 写入单词到 $sandbox/word_queue.jsonl       │  │
│  └────────────────┬───────────────────────────────┘  │
│                   │ $sandbox/                         │
└───────────────────┼──────────────────────────────────┘
                    │ 每 1 分钟 (LaunchAgent)
      ┌─────────────┴─────────────┐
      │  bob-wordbook-helper       │
      │                           │
      │  1. 读取 word_queue.jsonl  │
      │  2. 更新本地 Markdown 文件  │
      │  3. 提取浏览器 Cookie       │
      │  4. 更新沙箱中的 token     │
      └─────────────┬─────────────┘
                    │
      ┌─────────────┴─────────────┐
      │      浏览器 Cookie 存储     │
      │  Chrome  → AES 加密 SQLite │
      │  Edge    → AES 加密 SQLite │
      │  Firefox → 明文 SQLite     │
      └───────────────────────────┘
```

**为什么用队列而不是直接写 Markdown？**

Bob 插件运行在 JavaScriptCore 沙箱中，只能写入 `$sandbox/` 目录。用户的 Markdown 单词本通常在 Obsidian vault 等位置，插件无法直接写入。因此通过队列 + helper 的方式间接实现。

### 2.2 Bob 插件（JavaScript）

**运行环境**：Bob 的 JavaScriptCore 引擎，非浏览器/Node.js 环境。

**核心流程**：
1. 拦截 `translate()` 调用，判断是否为英文单词（`detectFrom === "en"`）
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

**插件选项**：

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `shanbei_auth_token` | text (secure) | 空 | 手动备选 token，留空则完全依赖自动提取 |
| `word_only` | menu | 是 | 仅添加单个单词，不添加包含空格的词组 |
| `auto_extract` | menu | 是 | 是否使用 helper 自动提取的 token |
| `show_result` | menu | 是 | 是否在翻译结果中显示收集状态 |

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
| `help` | 显示帮助 |

**配置文件**：`~/.config/bob-wordbook/config.json`
```json
{
  "markdown_path": "/Users/cian/Notes/wordbook.md"
}
```

**技术选型**：
- **语言**：Swift 5.9，单文件实现（`main.swift`，约 770 行）
- **依赖**：CryptoKit（PBKDF2/HMAC）、Security（Keychain）、SQLite3（Cookie 读取）、Foundation
- **构建**：`swiftc` 直接编译 + Makefile
- **安装**：`make install` 编译并安装到 `/usr/local/bin/`，自动配置 LaunchAgent

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

**文件处理策略**：
- 文件不存在：创建新文件，写入完整 header + 表格
- 文件存在且有表格：解析现有表格，合并后重写
- 文件存在但无表格：在文件末尾追加表格
- 保留 header 和 footer（表格前后的非表格内容）

### 2.5 Chrome Cookie 解密

Chrome 在 macOS 上使用 AES-128-CBC 加密 cookie：

1. 从 macOS Keychain 获取密码（service: `Chrome Safe Storage`, account: `Chrome`）
2. PBKDF2-HMAC-SHA1 派生 AES 密钥（salt: `saltysalt`, iterations: 1003, key length: 16）
3. IV = 16 bytes of `0x20`
4. 密文前缀 `v10`/`v20`，去掉前缀后为 AES-CBC 密文
5. 实现方式：CryptoKit (PBKDF2/HMAC) + openssl CLI (AES-CBC)

Firefox cookie 为明文存储，直接读取 SQLite。

**浏览器支持**：

| 浏览器 | Cookie 加密 | Keychain Service | Keychain Account |
|--------|------------|-----------------|-----------------|
| Chrome | AES-128-CBC | Chrome Safe Storage | Chrome |
| Edge | AES-128-CBC | Microsoft Edge Safe Storage | Microsoft Edge |
| Firefox | 明文 | 无 | 无 |

**多 Profile 支持**：Chrome 和 Edge 扫描 `Default` 和所有 `Profile *` 目录，取最新的 cookie。

### 2.6 LaunchAgent

```xml
<key>Label</key>
<string>com.bob-wordbook-helper.refresh</string>
<key>StartInterval</key>
<integer>60</integer>    <!-- 每 1 分钟 -->
<key>RunAtLoad</key>
<true/>                  <!-- 登录时立即运行 -->
```

安装路径：`~/Library/LaunchAgents/com.bob-wordbook-helper.refresh.plist`
日志路径：`/tmp/bob-wordbook-helper.log`、`/tmp/bob-wordbook-helper.err`

### 2.7 安全机制

1. **Keychain 授权**：首次运行弹出授权窗口，用户需允许
2. **本地存储**：token 仅存于本地沙箱，不上传第三方
3. **最小权限**：仅读取 `shanbay.com` 的 `auth_token` cookie
4. **数据库复制**：复制到临时目录后读取，避免锁冲突
5. **原子写入**：Markdown 和 token 文件均使用 `atomically: true`

---

## 3. 用户场景与预期行为

### 3.1 基本场景

| # | 场景 | 操作 | 预期行为 |
|---|------|------|----------|
| S1 | 查询英文单词 | 在 Bob 中查询单词 "serendipity" | 即时添加到扇贝单词本 + 写入 `$sandbox/word_queue.jsonl` |
| S2 | 查询英文词组（word_only=是） | 查询 "look up" | 不收集（包含空格），正常翻译 |
| S3 | 查询非英文 | 查询中文 "你好" | 不收集，正常翻译 |
| S4 | Helper 定时处理 | LaunchAgent 每 1 分钟触发 | 读取队列 → 写入 Markdown → 清空队列 |
| S5 | 新单词首次出现 | 首次查询 "ephemeral" | Created = Updated = 当前时间，插入到表格 |
| S6 | 已有单词再次出现 | 再次查询 "serendipity" | 保留 Created，更新 Updated = 当前时间，移到表格顶部 |
| S7 | 同一批次重复单词 | 连续查询 3 次 "hello" | 队列去重，仅保留最后一次时间 |

### 3.2 Token 管理场景

| # | 场景 | 预期行为 |
|---|------|----------|
| T1 | 首次安装 | 手动运行 `bob-wordbook-helper extract` 触发 Keychain 授权 |
| T2 | Token 自动刷新 | LaunchAgent 每 1 分钟运行，自动从浏览器提取最新 token |
| T3 | Token 提取失败 | 浏览器未登录 shanbay.com → 输出 WARN 日志，不影响队列处理 |
| T4 | 自动提取 + 手动备选 | 优先读取 sandbox 文件，文件为空则使用手动配置的 token |
| T5 | 多浏览器 | Chrome → Edge → Firefox 依次尝试，取第一个成功的 |

### 3.3 边界场景

| # | 场景 | 预期行为 |
|---|------|----------|
| E1 | 队列为空 | 输出 "No pending words"，不修改 Markdown |
| E2 | Markdown 路径未配置 | 输出提示运行 `init`，跳过队列处理 |
| E3 | Markdown 文件不存在 | 自动创建并写入 header + 表格 |
| E4 | Markdown 文件有内容但无表格 | 在末尾追加表格 |
| E5 | Bob 沙箱目录不存在 | 自动创建目录 |
| E6 | 多浏览器多 Profile | 扫描所有 Profile，取最新 cookie |

---

## 4. 当前已知限制

### 4.1 设计约束（符合预期，不做调整）

| # | 约束 | 说明 |
|---|------|------|
| 1 | Markdown 写入延迟 | 最长 1 分钟延迟（LaunchAgent 间隔），这是队列架构的固有代价 |
| 2 | 单词判断依赖 Bob | 插件通过 `detectFrom === "en"` 判断，依赖 Bob 的语言检测结果 |
| 3 | 整表重写 | 每次处理队列都重写整个 Markdown 文件，单词量极大时可能较慢 |
| 4 | 扇贝 API 不可控 | 依赖扇贝第三方 API，接口变更可能导致同步失败 |

### 4.2 待优化

| # | 限制 | 影响 | 备注 |
|---|------|------|------|
| 5 | Safari 不支持 | Safari Cookie 格式私有且受沙箱保护 | 短期无解，建议使用 Chrome/Edge/Firefox |
| 6 | 首次 Keychain 授权 | 后台 LaunchAgent 可能无法弹出授权窗口 | 建议先手动运行一次 `bob-wordbook-helper extract` |
| 7 | 扇贝验证用 "the" | `validate()` 使用 "the" 作为测试单词 | 扇贝可能忽略已存在的单词，但 HTTP 200 仍表示成功 |

---

## 5. 演进规划

### 5.1 Phase 1：基础功能（v1.0）✅ 已完成

基于 [wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin) 二次开发。

- [x] 扇贝单词本同步（即时）
- [x] 手动配置 auth_token

### 5.2 Phase 2：自动化 + 本地存储（v2.0）✅ 已完成

**目标**：消除手动 token 管理的痛点，增加本地 Markdown 存储。

- [x] Swift helper 工具：浏览器 Cookie 自动提取
- [x] Chrome/Edge（AES 加密）+ Firefox（明文）支持
- [x] LaunchAgent 每 1 分钟自动运行
- [x] 本地 Markdown 单词本（表格格式，Created/Updated 时间追踪）
- [x] 智能去重（保留 Created，更新 Updated）
- [x] `bob-wordbook-helper init` 交互式配置
- [x] 队列架构（JSONL）解决沙箱限制

### 5.3 Phase 3：增强体验（v2.1 待定）

**目标**：提升单词本的可读性和实用性。

- [ ] 单词释义/例句（调用翻译 API 补充信息）
- [ ] Markdown 增加释义列
- [ ] 按日期分组的统计视图
- [ ] 支持更多浏览器（Brave、Arc 等 Chromium 系）

### 5.4 Phase 4：多端同步（v3.0 远期）

**目标**：支持跨设备单词本同步。

- [ ] Markdown 文件基于 Git 同步（用户自行配置）
- [ ] 支持 iCloud Drive 路径
- [ ] 扇贝 + 本地双向状态同步

---

## 6. 技术决策记录

### 6.1 为什么用队列 + helper 而不是直接写 Markdown？

Bob 插件运行在 JavaScriptCore 沙箱中，只能写入 `$sandbox/` 目录。用户的 Markdown 单词本通常在 Obsidian vault 等位置，插件无法直接写入。

方案对比：

| 方案 | 优点 | 缺点 |
|------|------|------|
| 直接写 Markdown | 简单 | 沙箱限制，无法写入外部路径 |
| 软链接 | 绕过沙箱 | 需要用户手动创建，沙箱内可能不支持 |
| **队列 + helper** | 解耦、可靠、可扩展 | 最长 1 分钟延迟 |

结论：队列 + helper 是在沙箱限制下的最优方案，1 分钟延迟对单词收集场景可以接受。

### 6.2 为什么用 JSONL 而不是 JSON 数组？

JSONL（每行一个 JSON 对象）支持追加写入，不需要读取-解析-重写整个文件。在 JavaScriptCore 环境中，追加写入比读写整个 JSON 文件更高效、更安全（避免写入中途崩溃导致数据丢失）。

### 6.3 为什么 Cookie 解密用 openssl CLI 而不是 CryptoKit？

CryptoKit 提供 AES-CBC 解密能力，但 API 使用较复杂（需要手动处理 padding）。openssl CLI 是 macOS 自带的，一行命令即可完成解密，且经过充分测试。

### 6.4 为什么是单文件 Swift 实现？

helper 工具功能单一（Cookie 提取 + 队列处理 + Markdown 更新），约 770 行代码，单文件足够清晰。Swift Package 仅用于声明 sqlite3 链接依赖，实际编译使用 `swiftc` 直接编译。

---

## 7. 故障排查

| 问题 | 解决方案 |
|------|---------|
| helper 提取失败 | 在浏览器中登录 shanbay.com |
| Keychain 拒绝 | 系统设置 → 隐私与安全 → 完全磁盘访问权限（或 Keychain Access → 检查 Chrome Safe Storage 权限） |
| 扇贝验证失败 | 手动运行 `bob-wordbook-helper extract` |
| Markdown 未更新 | 检查 `~/.config/bob-wordbook/config.json` 中的路径是否正确 |
| LaunchAgent 未运行 | `launchctl list | grep bob-wordbook` |
| Token 过期 | LaunchAgent 每 1 分钟自动刷新；手动运行 `bob-wordbook-helper extract` |
| Bob 沙箱路径不对 | DMG 安装的 Bob 路径可能不同，检查 `~/Library/Containers/com.hezongyidev.Bob/` |

---

## 8. 变更日志

按时间倒序记录每次讨论的关键决策、代码变更和待办事项。

### 2026-04-05 v2.0：自动化 + 本地 Markdown 单词本

**讨论内容**：
在 v1.0 基础上，增加浏览器 Cookie 自动提取、本地 Markdown 单词本、LaunchAgent 定时处理。

**关键决策**：
- 队列架构（JSONL）：解决 Bob 沙箱限制，插件只写队列，helper 负责外部操作
- Swift 实现：需要 Keychain 访问和 SQLite 读取，JavaScriptCore 无法做到
- LaunchAgent 每 1 分钟：平衡实时性和系统开销
- 表格格式：`| Word | Created | Updated |`，简洁且支持排序
- 去重策略：保留 Created、更新 Updated、移到顶部
- Cookie 解密：CryptoKit（PBKDF2）+ openssl CLI（AES-CBC）

**代码变更**：
- 新增 `helper/` 目录：Swift CLI 工具（main.swift，约 770 行）
- 新增 `src/shanbay.js`：扇贝 API 集成（从 main.js 抽取）
- 重构 `src/main.js`：插件入口，队列写入 + 扇贝同步
- 新增 `helper/Makefile`：编译、安装、卸载
- 新增 `helper/install.sh` / `helper/uninstall.sh`
- 新增 `helper/config.json.example`
- 新增 `release.sh`：插件包构建脚本
- 新增 `appcast.json`：Bob 插件更新配置
- 项目重命名为 bob-wordbook

### 2026-04-05 v1.0：初始发布

基于 [wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin) 二次开发。

- 扇贝单词本同步（即时）
- 手动配置 auth_token
- Bob 插件基本框架
