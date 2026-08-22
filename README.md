# Bob Wordbook

[![CI](https://github.com/LuShan123888/bob-wordbook/actions/workflows/ci.yml/badge.svg)](https://github.com/LuShan123888/bob-wordbook/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/LuShan123888/bob-wordbook)](https://github.com/LuShan123888/bob-wordbook/releases)
[![License](https://img.shields.io/github/license/LuShan123888/bob-wordbook)](LICENSE)

面向英语学习的 Bob 翻译插件：通过 AIHubMix 或已登录的本地 Codex CLI 生成翻译、释义、例句和语法建议，并将英文输入及完整结果追加到本地 JSONL。

## 特性

- 可选择 AIHubMix 或本地 Codex；本地 Codex 可使用 ChatGPT 账号登录，不需要额外配置 AIHubMix API Key。
- AIHubMix 和本地 Codex 均可独立配置思考深度；本地 Codex 还支持 Standard/Fast 速度模式。
- 单个 Bob 服务同时完成翻译和本地单词本持久化，不读取 Bob 内部数据库。
- 英文单词使用 Bob 原生词典界面；短语和句子使用适合连续阅读的纯文本结果。
- 单词只展示音标、核心释义和一条例句；更多结构化学习内容保存在 JSONL 中。
- 中文等非英文输入可以正常翻译，但不会写入单词本。
- 只有收到完整且通过校验的模型结果后才会保存，截断或无效结果不会落盘。
- 保存失败时保留翻译结果并显示明确警告，不会误报“已保存”。
- 默认写入 `~/Downloads/bob-wordbook.jsonl`，也可指定其他 `.jsonl` 路径。
- helper 只监听本机回环地址，不接收或保存 AIHubMix API Key 或 Codex 登录凭据。
- 提供 macOS LaunchAgent 安装器、Universal Binary Release、自动更新 appcast 和 CI。

## 工作方式

```text
Bob 划词或输入翻译
        │
        ▼
Bob Wordbook 插件
        ├── AIHubMix ───────────▶ 流式翻译结果
        │
        └── HTTP 127.0.0.1 ────▶ Go 本地 helper ────▶ Codex CLI
                                      │
                                      ▼
                         ~/Downloads/bob-wordbook.jsonl
```

AIHubMix API Key 仅由 Bob 插件发送给 AIHubMix。Codex 登录由 CLI 自己管理；helper 不读取或复制 Codex 的认证文件。JSONL 不保存密钥、登录凭据或 System Prompt。

## 安装

### 从 Release 安装（推荐）

系统要求：macOS 13 或更高版本、Bob 1.8.0 或更高版本。

1. 从 [Releases](https://github.com/LuShan123888/bob-wordbook/releases) 下载：
   - `bob-wordbook-v<version>-darwin-universal.tar.gz`
   - `SHA256SUMS`
2. 在下载目录核对文件：

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

3. 解压并安装 helper：

   ```bash
   tar -xzf bob-wordbook-v<version>-darwin-universal.tar.gz
   cd bob-wordbook-v<version>
   bash install.sh
   ```

4. 双击同一目录中的 `.bobplugin` 文件。
5. 在 Bob「设置 → 服务 → 文本翻译」中添加并启用「英语学习与单词本」。
6. 选择 AIHubMix 或本地 Codex，并填写对应配置；需要时粘贴自己的 System Prompt。
7. 关闭原来的 AIHubMix 和旧版「单词本 JSONL」服务，避免一次翻译产生重复结果。

安装器会写入：

- helper：`~/.local/bin/bob-wordbook-helper`
- LaunchAgent：`~/Library/LaunchAgents/com.cian.bob-wordbook-helper.plist`
- 卸载器：`~/.local/share/bob-wordbook/uninstall.sh`
- 日志：`~/Library/Logs/bob-wordbook/`

Release helper 使用临时签名，尚未经过 Apple Developer ID 公证。如果 macOS 阻止运行，请从源码构建，不要安装来源不明的二进制文件。

### 从源码安装

需要 Go 1.22、Node.js 24 和 Python 3：

```bash
git clone https://github.com/LuShan123888/bob-wordbook.git
cd bob-wordbook
make check
make build
make plugin
bash scripts/install.sh bin/bob-wordbook-helper
```

然后双击 `dist/bob-wordbook-v3.4.1.bobplugin`。

## 配置

- 翻译服务：默认 AIHubMix，也可选择本地 Codex。
- AIHubMix API Key：选择 AIHubMix 时必填，仅用于请求 `https://aihubmix.com/v1/chat/completions`。
- AIHubMix 模型：默认 `gpt-4o-mini`；可填写 AIHubMix 模型广场中的其他模型 ID。
- AIHubMix 思考深度：默认 Auto，不发送 `reasoning_effort`；也可选择 `none`、`minimal`、`low`、`medium`、`high` 或 `xhigh`。具体档位是否生效取决于模型。
- Codex 模型：默认 `gpt-5.6-luna`，适合低延迟日常翻译；优先质量可使用 `gpt-5.6-terra`。模型必须对当前登录账号可用。
- Codex 思考深度：默认 `none`；支持 `none`、`low`、`medium`、`high`、`xhigh` 和 `max`。日常翻译使用 `none` 延迟最低，复杂语法分析可使用 `low` 或更高。
- Codex 速度模式：默认 Standard；Fast 延迟更低，但会消耗更多套餐用量。
- System Prompt：可选；留空使用内置英语学习 Prompt。
- JSONL 文件路径：默认 `~/Downloads/bob-wordbook.jsonl`。

### 使用本地 Codex

本地 Codex 模式需要先安装 [Codex CLI](https://developers.openai.com/codex/cli) 并完成登录：

```bash
codex login
codex login status
```

helper 会依次查找 `/opt/homebrew/bin/codex`、`/usr/local/bin/codex`、`~/.local/bin/codex` 和当前 `PATH`。helper 启动时会预热并复用一个 Codex App Server；每次翻译仍创建独立临时目录和临时线程，并使用只读沙箱，同时禁用 Shell、浏览器、Apps、MCP、Hooks、Plugins、技能搜索、图片生成及多 Agent 工具。短语和句子会从首段真实文本开始流式展示，单词则等结构化内容完整校验后使用 Bob 原生词典渲染并保存。

自定义 Prompt 支持 Bob 常用变量：

- `$query.text`：用户输入的原文。
- `$query.detectFromLang`：检测到的源语言名称。
- `$query.detectToLang`：检测到的目标语言名称。

路径必须是绝对路径或以 `~/` 开头，并以 `.jsonl` 结尾。不要输入 shell 转义用的反斜杠；`~` 只能作为开头的 `~/` 使用。

## JSONL 数据

英文翻译成功后，每次追加一个 schema v3 对象。`provider` 会记录为 `aihubmix` 或 `local_codex`。单词保存为结构化内容：

```jsonl
{"schema_version":3,"text":"translation","kind":"word","content":{"word":"translation","phonetics":[{"type":"us","value":"trænzˈleɪʃən"}],"parts":[{"part":"n.","means":["翻译","译文"]}],"collocations":[{"text":"Chinese translation","meaning":"中文译文"}],"examples":[{"text":"Please send me the translation.","translation":"请把译文发给我。"}]},"source_language":"en","target_language":"zh-Hans","provider":"aihubmix","model":"gpt-4o-mini","created_at":"2026-08-22T12:30:00+08:00"}
```

短语和句子的 `content.text` 保存完整纯文本学习结果。旧版 schema v1/v2 记录仍然有效，helper 继续保留 `/v1/entries` 和 `/v2/entries` 兼容接口。

## 升级与卸载

升级时必须同时运行新 Release 中的 `install.sh` 并安装新的 `.bobplugin`。本地 Codex 的真实文本流式展示和常驻 App Server 优化需要 3.4.0 或更高版本；LaunchAgent 环境下的证书冷启动修复需要 helper 3.4.1 或更高版本。旧版插件与 helper 可继续配合兼容接口使用，原有 AIHubMix 配置继续兼容。

卸载 helper：

```bash
bash ~/.local/share/bob-wordbook/uninstall.sh
```

卸载不会删除 JSONL 单词本。Bob 插件需要在 Bob 设置中单独移除。

## 故障排查

检查 helper：

```bash
curl --fail http://127.0.0.1:19820/healthz
~/.local/bin/bob-wordbook-helper -version
launchctl print gui/$(id -u)/com.cian.bob-wordbook-helper
```

查看日志：

```bash
tail -n 100 ~/Library/Logs/bob-wordbook/stderr.log
```

常见问题：

- `请先填写 AIHubMix API Key`：在插件设置中填写有效密钥并点击验证。
- `AIHubMix 流式响应未正常完成`：请求中途断开，插件不会保存不完整结果，可重试。
- `本地 Codex 尚不可用`：运行 `codex login status`，并确认 helper 能找到 Codex CLI。
- `Codex translation timed out`：降低思考深度或重试；日常翻译建议使用 `none`。
- 本地 Codex 返回模型不可用：将 Codex 模型改成当前 ChatGPT 账号可用的模型。
- `无法连接 Wordbook 本地辅助程序`：helper 未运行或端口 `19820` 被占用；译文仍会显示，但不会落盘。
- `path must point to a .jsonl file`：配置路径不是 `.jsonl` 文件。
- 无法写入目标目录：在「系统设置 → 隐私与安全性 → 文件与文件夹」中允许 helper 访问。

## 开发与发布

```bash
make check   # 全部测试和静态检查
make build   # 构建当前架构 helper
make plugin  # 构建确定性的 Bob 插件包
```

推送与 `src/info.json` 版本一致的 `v<version>` 标签后，Release 工作流会测试项目、构建 macOS arm64/amd64 Universal helper，并创建包含校验和的 GitHub Release。

更多信息：

- [设计与数据契约](DESIGN.md)
- [变更记录](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全政策](SECURITY.md)
- [Bob 插件开发文档](https://bobtranslate.com/plugin/)
- [AIHubMix API 文档](https://docs.aihubmix.com/en/quick-start)

## License

[MIT](LICENSE) © Cian Lu
