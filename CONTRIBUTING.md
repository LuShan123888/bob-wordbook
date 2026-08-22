# Contributing

感谢你改进 Bob Wordbook。提交改动前，请先确认问题属于本项目，而不是 Bob 本体或其他翻译服务。

## 开发环境

- macOS 13 或更高版本
- Go 1.22 或兼容版本
- Node.js 24（用于测试 Bob 插件逻辑）
- Python 3（用于验证元数据和构建确定性的 `.bobplugin` 文件）

## 本地验证

```bash
make check
make build
make plugin
```

`make check` 会执行 Go 单元测试与竞态检测、`go vet`、Go 格式检查、插件行为测试、JavaScript 语法检查、Shell 语法检查和插件元数据验证。

## 变更边界

- 保持 Go 1.22 兼容，不引入无必要的第三方依赖。
- 不要让 helper 监听非回环地址。
- 不要在日志、测试或示例中提交真实用户名、私有路径或词库内容。
- JSONL schema、helper 持久化接口和 Codex 接口、默认路径、插件标识符和最低 Bob 版本属于公开契约；变更时必须说明兼容性并更新文档。
- 不要在测试、日志或示例中使用真实 AIHubMix API Key；Key 不得发送给 helper 或写入 JSONL。
- Codex 测试必须使用假的可执行文件，不得在 CI 或普通单元测试中消耗维护者的真实套餐用量。
- 安装和卸载不得删除用户的 JSONL 单词本。

## Pull Request

一个 PR 只处理一个主要问题。请说明问题、方案、验证结果和兼容性影响。发布由维护者通过 `v<version>` 标签触发，不要在普通 PR 中创建 Release 或修改现有 Git 历史。
