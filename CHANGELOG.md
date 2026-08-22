# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号采用语义化版本。

## [3.4.1] - Unreleased

### Fixed

- 保存成功提示中的空格使用终端转义形式展示，路径可直接复制到命令行中使用；实际写入路径保持不变。
- 修复 helper 由 LaunchAgent 启动时，Codex App Server 首次建立线程可能在 macOS Keychain 证书枚举阶段阻塞数十秒的问题。
- App Server 建立线程和回合超过 10 秒时立即失败并重建进程，避免 Bob 持续停留在“生成中”。

### Changed

- AIHubMix 新增独立思考深度配置；默认 Auto 不发送 `reasoning_effort`，显式选择时才向统一推理接口透传。
- 本地 Codex 新增并默认使用 GPT-5.6 支持的 `none` 思考深度，减少日常翻译的推理耗时；复杂语法分析仍可选择 `low` 或更高。
- 新安装默认使用更适合低延迟日常翻译的 `gpt-5.6-luna`；原有模型配置保持不变。
- 单词 JSON Schema 直接限制音标、词性、释义、搭配和例句数量，减少无效输出并避免完整生成后才因内容超限而失败。

## [3.4.0] - 2026-08-22

### Added

- 短语和句子的本地 Codex 翻译会把真实文本增量直接流式展示在 Bob 中。
- helper 启动时预热常驻 Codex App Server，并记录首段文本耗时。

### Changed

- 流式本地 Codex 翻译复用常驻 App Server，不再为每次划词重新启动 Codex CLI。
- 每次请求仍使用独立临时目录和临时线程，并关闭 MCP、Hooks、Plugins、技能搜索及所有无关工具，减少启动和 Prompt 开销。
- 单词查询只由 helper 的 JSON Schema 约束结构，移除插件 Prompt 中重复的 JSON 格式说明。

### Fixed

- 修复本地 Codex 已产生译文但 Bob 仍只显示“生成中”的体感延迟。
- 修复用户 Codex 配置中的 MCP 服务可能随翻译线程启动、额外增加数秒耗时的问题。

## [3.3.0] - 2026-08-22

### Added

- 本地 Codex 翻译新增启动、生成和结果整理阶段的流式进度反馈。
- helper 为每次 Codex 请求记录安全的生命周期日志，包括请求编号、阶段、耗时、取消、超时和失败；不记录划词正文。

### Changed

- helper 使用 `codex exec --json` 读取 JSONL 生命周期事件，并通过独立结果文件读取最终结构化输出。
- 新增 `/v1/codex/translate/stream` NDJSON 接口；原 `/v1/codex/translate` 保持兼容。

### Fixed

- 修复本地 Codex 完整结果返回前 Bob 一直空白显示“生成中”、无法判断当前阶段的问题。
- 修复用户关闭 Bob 窗口后，helper 日志无法识别请求已取消的问题。

## [3.2.0] - 2026-08-22

### Added

- 新增本地 Codex 翻译服务，可复用 Codex CLI 的 ChatGPT 登录状态。
- 支持配置 Codex 模型、`low` 至 `max` 思考深度，以及 Standard/Fast 速度模式。
- helper 新增 `/v1/codex/status` 与 `/v1/codex/translate`，并使用 JSON Schema 校验结构化结果。

### Changed

- 插件更名为「英语学习与单词本」，AIHubMix 继续作为默认兼容服务。
- JSONL schema v3 的 `provider` 新增 `local_codex` 取值。

### Security

- Codex 调用使用临时工作目录、只读沙箱和临时会话，并禁用与翻译无关的工具。
- helper 不读取、复制或记录 Codex 登录凭据。

## [3.1.0] - 2026-08-22

### Added

- 通过 AIHubMix OpenAI-compatible API 提供流式翻译、单词释义、例句和句子语法建议。
- 新增可配置的 AIHubMix API Key、模型和 System Prompt，支持 Bob Prompt 变量。
- 新增 `/v2/entries`，保存英文原文、完整结果、语言、服务商、模型和 schema 版本。
- 单个英文单词使用 Bob 原生 `toDict` 展示单词、音标、核心释义和一条例句。
- 新增 `/v3/entries` 和 JSONL schema v3，单词结果按音标、词义、搭配和例句保存为结构化字段。

### Changed

- 插件从单独的记录服务升级为翻译与学习结果持久化一体化服务。
- 中文及其他非英文输入继续提供翻译，但不持久化。
- JSONL 新记录升级为 schema v3；旧 schema v1/v2 记录和 `/v1/entries`、`/v2/entries` 接口继续兼容。
- 单词查询的模型 JSON 仅作为插件内部数据交换格式，不再流式显示到 Bob。
- Bob 只展示精简学习信息；更多搭配和例句保留在 JSONL 中。

### Fixed

- 将常见 Markdown 标记转换为 Bob 友好的纯文本，避免粗体、标题和列表语法被按字面显示。
- `/v3/entries` 返回 404 时明确提示 helper 版本过旧，不再只显示泛化写入失败。
- 只有收到完整流式结束标记后才写入，避免保存被截断的模型结果。
- helper 写入失败时保留译文并显示明确警告，不再把保存失败伪装成成功。

### Security

- AIHubMix API Key 仅发送给 AIHubMix，不进入 helper 请求、日志或 JSONL。

## [2.1.0] - 2026-08-22

### Added

- 使用 Go helper 将 Bob 接收到的单词或短语追加到可配置的本地 JSONL 文件。
- 提供 macOS LaunchAgent 安装和卸载脚本。
- 提供 macOS CI、Universal Binary Release、插件行为测试和确定性 Bob 插件打包。
- 增加贡献指南、安全政策、Issue 与 Pull Request 模板。

### Changed

- 默认输出改为 `~/Downloads/bob-wordbook.jsonl`。
- 插件标识符改为符合 Bob 规范的 `com.cian.bobwordbook`。
- 项目不再同步扇贝，也不再生成 Markdown 单词本。

### Fixed

- 拒绝包含反斜杠或中间 `~` 路径段的输出路径，避免拼写错误被当作新目录创建并返回保存成功。
- 仅持久化 Bob 检测为英文且不含中文的文本，缺失语言检测结果或中英混合文本不再写入。

### Security

- helper 只允许绑定回环地址，并限制 HTTP 超时、请求体大小、来源和媒体类型。

## [2.0.0] - 2026-04-05

### Added

- 自动同步扇贝单词本和本地 Markdown 单词本的初始实现。
