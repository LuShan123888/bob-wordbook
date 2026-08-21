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
- Release 中的 helper 使用临时签名，不代表 Apple Developer ID 签名或公证；安装前应核对 `SHA256SUMS`。
