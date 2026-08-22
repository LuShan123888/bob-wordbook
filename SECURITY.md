# Security Policy

## Supported Versions

安全修复面向最新发布版本。旧版本可能要求先升级后再验证问题。

## Reporting a Vulnerability

请不要通过公开 Issue 报告可被利用的安全问题。使用仓库的 GitHub Security Advisory 私密报告入口：

<https://github.com/LuShan123888/bob-wordbook/security/advisories/new>

报告应包含受影响版本、macOS 与 Bob 版本、复现步骤、影响范围和建议修复。不要附带真实词库、个人路径或其他敏感数据。

## Security Boundaries

- helper 默认且强制只监听回环地址。
- 本机接口不是远程服务，也不应通过端口转发或反向代理暴露。
- 输出路径由本机 Bob 插件设置提供，helper 使用当前 macOS 用户权限写入。
- AIHubMix API Key 由 Bob 插件直接发送到 `https://aihubmix.com`，不会发送给 helper、写入 JSONL 或输出到 helper 日志。
- 本地 Codex 认证由 Codex CLI 管理；helper 只启动固定位置找到的 `codex` 可执行文件，不读取、复制或记录 Codex 认证文件。
- Codex 翻译运行在隔离的临时目录和只读沙箱中，并禁用不需要的工具；用户级 Codex 配置和项目规则不会加载。
- JSONL 会保存用户输入和完整模型结果，用户应自行选择符合隐私要求的输出目录和同步服务。
- Release 中的 helper 使用临时签名，不代表 Apple Developer ID 签名或公证；安装前应核对 `SHA256SUMS`。
