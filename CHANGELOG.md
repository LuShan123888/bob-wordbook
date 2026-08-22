# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号采用语义化版本。

## [3.1.0] - Unreleased

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
