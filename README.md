# bob-wordbook

> Bob 翻译插件 — 查词时自动收集生词到扇贝单词本和本地 Markdown 文件。
>
> Bob translate plugin — automatically collect words to Shanbay wordbook and local Markdown file.

每次在 Bob 中查词，单词自动同步到扇贝单词本（即时）和本地 Markdown 文件（1 分钟内）。

---

## 为什么需要它 / Why

使用 Bob 查词时，你可能会遇到这些问题：

```
😖 查了很多生词，但没有系统收集起来复习
😖 手动复制 auth_token 到插件设置，还经常过期
😖 想把生词记到 Obsidian，但插件只能写沙箱目录
```

bob-wordbook 的做法：

```
查词 → Bob 插件
         ├─ 扇贝 API（即时同步，用于间隔重复）
         └─ word_queue.jsonl → LaunchAgent 每 1 分钟
                                      └─ 更新本地 Markdown（可放 Obsidian vault）
```

- **零感知收集** — 查词即收集，无需额外操作
- **双目标存储** — 扇贝（即时）+ 本地 Markdown（延迟 1 分钟）
- **自动提取 Cookie** — 无需手动复制 auth_token，helper 从浏览器自动提取
- **时间追踪** — 记录 Created（首次遇到）和 Updated（最近遇到），遗忘曲线一目了然

---

## 对比其他方案 / Comparison

### vs 手动添加

查词后手动复制到扇贝或笔记，极易遗漏，且无法追踪时间。

### vs [wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin)

| | wordbook-bob-plugin | bob-wordbook |
|---|---|---|
| **Token 获取** | 手动从 DevTools 复制 | 自动从浏览器提取（Chrome/Edge/Firefox） |
| **Token 过期** | 手动重新复制 | LaunchAgent 每 1 分钟自动刷新 |
| **本地存储** | 不支持 | Markdown 表格，支持 Obsidian 等知识库 |
| **去重逻辑** | 覆盖 | 保留 Created，更新 Updated，移到顶部 |
| **时间追踪** | 无 | Created + Updated 双时间戳 |

---

## 快速开始 / Quick Start

### 安装 / Install

#### 前置条件

- macOS 13+
- [Bob](https://bobtranslate.com/) 翻译软件
- Xcode Command Line Tools（`xcode-select --install`）
- 在浏览器中登录 [扇贝](https://www.shanbay.com/)（如需扇贝同步）

#### 步骤

##### 1. 安装 helper 工具

```bash
cd helper
make install
```

这会编译 Swift helper、安装到 `/usr/local/bin/`、配置 LaunchAgent。

##### 2. 配置本地 Markdown 单词本（可选）

```bash
bob-wordbook-helper init
```

按提示输入 Markdown 文件路径，例如 `/Users/cian/Notes/wordbook.md`。

> 不需要本地单词本？跳过此步骤即可，仅使用扇贝同步。

##### 3. 安装 Bob 插件

```bash
bash release.sh
# 双击生成的 .bobplugin 文件安装到 Bob
```

##### 4. 配置插件（可选）

在 Bob 偏好设置 → 插件 → 单词本 中按需调整：

- **扇贝 Auth Token**：留空（使用自动提取）
- **自动提取 Cookie**：保持「是」

**验证**：点击「验证」按钮，应显示 `✅ auth_token 验证成功`。

---

### 使用 / Usage

安装完成后，每次在 Bob 中查询英文单词：

1. **即时**同步到扇贝单词本
2. **1 分钟内**自动写入本地 Markdown 单词本

常用命令：

```bash
bob-wordbook-helper              # 手动触发一次完整处理
bob-wordbook-helper extract      # 仅刷新扇贝 token
bob-wordbook-helper process      # 仅处理单词队列
bob-wordbook-helper init         # 重新配置 Markdown 路径
tail -f /tmp/bob-wordbook-helper.log  # 查看日志
```

### 卸载 / Uninstall

```bash
cd helper
make uninstall
```

---

## 单词本表格格式 / Wordbook Format

本地 Markdown 文件以表格形式存储，自动按 Updated 时间倒序排列：

```markdown
# Word Book

| Word | Created | Updated |
|:-----|:--------|:--------|
| serendipity | 2026-04-05 14:30 | 2026-04-07 10:15 |
| ephemeral | 2026-04-05 15:02 | 2026-04-05 15:02 |
```

- **Word**：单词（自动转小写）
- **Created**：首次遇到该单词的时间
- **Updated**：最近一次遇到的时间（忘记了再查一次）

---

## 架构 / Architecture

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

---

## 开发 / Development

### 项目结构

```
bob-wordbook/
├── src/                    # Bob 插件源码
│   ├── info.json           # 插件清单
│   ├── main.js             # 插件入口（队列写入 + 扇贝同步）
│   └── shanbay.js          # 扇贝 API 集成
├── helper/                 # 辅助工具
│   ├── Sources/
│   │   └── ShanbayCookieHelper/
│   │       └── main.swift  # Swift CLI（Cookie 提取 + Markdown 处理）
│   ├── config.json.example # 配置示例
│   ├── Makefile
│   ├── install.sh
│   └── uninstall.sh
├── DESIGN.md               # 设计文档
├── appcast.json
├── release.sh
└── README.md
```

### 构建插件包

```bash
bash release.sh
```

## 致谢 / Credits

- 基于 [yuhaowin/wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin) 二次开发
- [Bob](https://bobtranslate.com/) 翻译软件

## License

MIT

---

# bob-wordbook

> Bob translate plugin — automatically collect looked-up words to Shanbay wordbook and local Markdown file.

Every time you look up an English word in Bob, it automatically syncs to Shanbay wordbook (instant) and a local Markdown file (within 1 minute).

## Why

- **Manual collection** — Copying words to Shanbay or notes after looking them up is tedious and error-prone
- **Token management** — The original plugin requires manually copying `auth_token` from browser DevTools, which expires frequently
- **Local storage** — No way to save words to Obsidian or other knowledge bases

bob-wordbook solves these with automatic Cookie extraction and dual-target storage.

### vs [wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin)

| | wordbook-bob-plugin | bob-wordbook |
|---|---|---|
| **Token** | Manual copy from DevTools | Auto-extract from browser (Chrome/Edge/Firefox) |
| **Token expiry** | Manual re-copy | Auto-refresh every 1 minute |
| **Local storage** | Not supported | Markdown table, works with Obsidian etc. |
| **Dedup** | Overwrite | Preserve Created, update Updated, move to top |
| **Time tracking** | None | Created + Updated timestamps |

## Quick Start

### Prerequisites

- macOS 13+
- [Bob](https://bobtranslate.com/) translate app
- Xcode Command Line Tools (`xcode-select --install`)
- Logged in to [Shanbay](https://www.shanbay.com/) in your browser (for Shanbay sync)

### Install

```bash
# 1. Build and install helper
cd helper && make install

# 2. Configure local Markdown wordbook (optional)
bob-wordbook-helper init

# 3. Build and install Bob plugin
cd .. && bash release.sh
# Double-click the generated .bobplugin file to install
```

### Usage

After installation, every word lookup in Bob:

1. **Instantly** syncs to Shanbay wordbook
2. **Within 1 minute** writes to local Markdown wordbook

```bash
bob-wordbook-helper              # Trigger a full processing cycle
bob-wordbook-helper extract      # Refresh Shanbay token only
bob-wordbook-helper process      # Process word queue only
bob-wordbook-helper init         # Reconfigure Markdown path
tail -f /tmp/bob-wordbook-helper.log  # View logs
```

## Wordbook Format

Local Markdown file stores words as a table, sorted by Updated time (descending):

```markdown
# Word Book

| Word | Created | Updated |
|:-----|:--------|:--------|
| serendipity | 2026-04-05 14:30 | 2026-04-07 10:15 |
| ephemeral | 2026-04-05 15:02 | 2026-04-05 15:02 |
```

## Development

```bash
bash release.sh    # Build plugin package
```

## Credits

- Based on [yuhaowin/wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin)
- [Bob](https://bobtranslate.com/) translate app

## License

MIT
