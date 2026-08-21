# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号采用语义化版本。

## [2.1.0] - Unreleased

### Added

- 使用 Go helper 将 Bob 接收到的单词或短语追加到可配置的本地 JSONL 文件。
- 提供 macOS LaunchAgent 安装和卸载脚本。
- 提供 macOS CI、Universal Binary Release、插件行为测试和确定性 Bob 插件打包。
- 增加贡献指南、安全政策、Issue 与 Pull Request 模板。

### Changed

- 默认输出改为 `~/Downloads/bob-wordbook.jsonl`。
- 插件标识符改为符合 Bob 规范的 `com.cian.bobwordbook`。
- 项目不再同步扇贝，也不再生成 Markdown 单词本。

### Security

- helper 只允许绑定回环地址，并限制 HTTP 超时、请求体大小、来源和媒体类型。

## [2.0.0] - 2026-04-05

### Added

- 自动同步扇贝单词本和本地 Markdown 单词本的初始实现。
