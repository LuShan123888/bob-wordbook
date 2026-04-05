# bob-wordbook

Bob 翻译插件 — 将查询的英语单词自动收集到扇贝单词本和本地 Markdown 文件。

## 特性

- **扇贝同步**：查词时自动添加到扇贝单词本（即时）
- **本地 Markdown 单词本**：以表格形式记录单词，支持 Created/Updated 时间追踪
- **自动提取 Cookie**：无需手动复制 `auth_token`，通过 helper 工具自动从浏览器提取
- **定时刷新**：LaunchAgent 每 1 分钟自动处理单词队列和刷新 token
- **多浏览器支持**：Chrome、Edge、Firefox
- **智能去重**：已有单词仅更新 Updated 时间，Created 保持不变

## 单词本表格格式

本地 Markdown 文件以表格形式存储，自动按 Updated 时间倒序排列：

```markdown
# Word Book

| Word | Created | Updated |
|:-----|:--------|:--------|
| serendipity | 2026-04-05 14:30 | 2026-04-07 10:15 |
| ephemeral | 2026-04-05 15:02 | 2026-04-05 15:02 |
```

- **Word**：单词（小写）
- **Created**：首次遇到该单词的时间
- **Updated**：最近一次遇到的时间（忘记了再查一次）

## 架构

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

## 安装

### 前置条件

- macOS 13+
- [Bob](https://bobtranslate.com/) 翻译软件
- Xcode Command Line Tools（`xcode-select --install`）
- 在浏览器中登录 [扇贝](https://www.shanbay.com/)（如需扇贝同步）

### 步骤

#### 1. 安装 helper 工具

```bash
cd helper
make install
```

这会编译 Swift helper、安装到 `/usr/local/bin/`、配置 LaunchAgent。

#### 2. 配置本地 Markdown 单词本

```bash
bob-wordbook-helper init
```

按提示输入 Markdown 文件路径，例如 `/Users/cian/Notes/wordbook.md`。

> 如果不需要本地单词本，直接跳过此步骤即可（仅使用扇贝同步）。

#### 3. 安装 Bob 插件

```bash
cd src
zip -r -j ../bob-wordbook.bobplugin info.json main.js shanbay.js
# 双击 bob-wordbook.bobplugin 安装到 Bob
```

#### 4. 配置插件（可选）

在 Bob 偏好设置 → 插件 → 单词本 中按需调整：

- **扇贝 Auth Token**：留空（使用自动提取）
- **仅添加单词**：按需选择
- **自动提取 Cookie**：保持「是」
- **显示添加结果**：按需选择

### 验证

在插件设置中点击「验证」按钮，应显示 `✅ auth_token 验证成功`。

## 使用

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

## 卸载

```bash
cd helper
make uninstall
```

## 开发

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

## 致谢

- 基于 [yuhaowin/wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin) 二次开发
- [Bob](https://bobtranslate.com/) 翻译软件

## License

MIT
