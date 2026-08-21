# Bob Wordbook

[![CI](https://github.com/LuShan123888/bob-wordbook/actions/workflows/ci.yml/badge.svg)](https://github.com/LuShan123888/bob-wordbook/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/LuShan123888/bob-wordbook)](https://github.com/LuShan123888/bob-wordbook/releases)
[![License](https://img.shields.io/github/license/LuShan123888/bob-wordbook)](LICENSE)

将 Bob 接收到的英文单词或短语逐条保存到本地 JSONL 文件。

Save English words and phrases received by Bob to a local JSONL file, one record per line.

## 特性

- 只保存 Bob 检测为英文且不含中文的单词、短语或句子，不修改原始文本内容。
- 默认写入 `~/Downloads/bob-wordbook.jsonl`，也可在 Bob 中配置其他 `.jsonl` 路径。
- 每条记录包含原文和 RFC 3339 时间戳，适合脚本、数据库或学习工具继续处理。
- helper 只监听本机回环地址，不会暴露为局域网服务。
- 提供 macOS LaunchAgent 安装器、Universal Binary Release、自动更新 appcast 和完整 CI。
- helper 仅使用 Go 标准库，运行时不需要 Go、Node.js 或 Python。

## 工作方式

Bob 插件无法直接写入 Downloads 等用户目录，因此项目分为两部分：

```text
Bob 划词或输入翻译
        │
        ▼
Bob 插件（src/）
        │ HTTP，仅 127.0.0.1
        ▼
Go helper（后台常驻）
        │
        ▼
~/Downloads/bob-wordbook.jsonl
```

插件优先保存 Bob 提供的 `originalText`，不可用时保存 `text`。Bob 没有向插件开放直接读取系统剪贴板的接口，因此需要通过划词翻译或输入翻译触发。

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

4. 双击同一目录中的 `bob-wordbook-v<version>.bobplugin`。
5. 在 Bob「设置 → 服务」中添加并启用「单词本 JSONL」。

安装器会将文件写入：

- helper：`~/.local/bin/bob-wordbook-helper`
- LaunchAgent：`~/Library/LaunchAgents/com.cian.bob-wordbook-helper.plist`
- 卸载器：`~/.local/share/bob-wordbook/uninstall.sh`
- 日志：`~/Library/Logs/bob-wordbook/`

Release helper 使用临时签名，尚未经过 Apple Developer ID 公证。如果 macOS 阻止运行，请从源码构建，不要下载来源不明的二进制文件。

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

然后双击 `dist/bob-wordbook-v2.1.0.bobplugin` 安装 Bob 插件。

## 使用

选中或输入英文单词、短语并调用 Bob。插件写入成功后会显示实际文件路径。

默认 JSONL 内容：

```jsonl
{"text":"take care","created_at":"2026-08-22T10:30:00+08:00"}
{"text":"piece of cake","created_at":"2026-08-22T10:31:12.123+08:00"}
```

在 Bob 插件设置中修改「JSONL 文件路径」即可更换位置。路径必须是绝对路径或以 `~/` 开头，并以 `.jsonl` 结尾；不要输入 shell
转义用的反斜杠，`~` 只能作为开头的 `~/` 使用。不存在的父目录会自动创建。

## 升级与卸载

升级时下载新 Release，并再次运行其中的 `install.sh`，然后安装新的 `.bobplugin`。

从 2.0.x 升级时请注意：2.1.0 使用新的合规插件标识符 `com.cian.bobwordbook`，Bob 可能将它显示为一个新插件。确认 JSONL 写入正常后，可手动移除旧的扇贝/Markdown 插件。旧 Markdown 单词本不会被迁移或删除。

卸载 helper：

```bash
bash ~/.local/share/bob-wordbook/uninstall.sh
```

从源码安装时使用：

```bash
make uninstall
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

- `无法连接 Wordbook 本地辅助程序`：helper 未运行或端口 `19820` 被占用。
- `path must point to a .jsonl file`：插件中配置的路径不是 `.jsonl` 文件。
- 无法写入 Downloads：在「系统设置 → 隐私与安全性 → 文件与文件夹」中允许 helper 访问。

## 开发与发布

```bash
make check   # 全部测试和静态检查
make build   # 构建当前架构 helper
make plugin  # 构建确定性的 Bob 插件包
```

推送与 `src/info.json` 版本一致的 `v<version>` 标签后，Release 工作流会测试项目、构建 macOS arm64/amd64 Universal helper，并创建包含校验和的 GitHub Release。发布前必须同步更新 `appcast.json` 中的版本、下载地址和确定性插件 SHA256。

更多信息：

- [设计与数据契约](DESIGN.md)
- [变更记录](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全政策](SECURITY.md)
- [Bob 插件开发文档](https://bobtranslate.com/plugin/)

## License

[MIT](LICENSE) © Cian Lu
