# bob-wordbook 设计文档

## 目标

bob-wordbook 在 Bob 接收到英文单词或短语时，将文本逐条追加到用户指定的本地 JSONL 文件。默认文件为：

```text
~/Downloads/bob-wordbook.jsonl
```

每次调用产生一个独立 JSON 对象，不负责翻译、在线词库同步、去重或内容改写。

## 架构

```text
Bob 划词或输入翻译
        │ originalText / text
        ▼
Bob 插件（JavaScriptCore）
        │ POST http://127.0.0.1:19820/v1/entries
        ▼
Go 本地辅助程序
        │ O_APPEND + 单次完整写入
        ▼
用户指定的 .jsonl 文件
```

Bob 插件的 `$file` 只能写插件沙盒，不能直接写 Downloads 或其他用户路径。因此插件通过 `$http` 调用只监听本机回环地址的辅助程序，由辅助程序执行文件写入。

## 插件

插件源码位于 `src/`：

- 优先读取 `query.originalText`，不可用时读取 `query.text`。
- 从 `$option.outputPath` 读取 JSONL 文件路径。
- 使用 `Content-Type: application/json` 调用本机辅助程序。
- 写入成功后在 Bob 结果中显示文本和实际输出路径。
- 连接或写入失败时返回明确的 Bob service error。

插件不会直接读取系统剪贴板。划词翻译和输入翻译由 Bob 负责取得文本并传给插件。

## 本地辅助程序

辅助程序位于 `cmd/bob-wordbook-helper/`，使用 Go 1.22 标准库实现。

### 接口

- `GET /healthz`：健康检查。
- `POST /v1/entries`：追加一条记录。

请求示例：

```json
{
  "text": "piece of cake",
  "path": "~/Downloads/bob-wordbook.jsonl"
}
```

响应示例：

```json
{
  "ok": true,
  "path": "/Users/example/Downloads/bob-wordbook.jsonl",
  "entry": {
    "text": "piece of cake",
    "created_at": "2026-08-22T10:30:00+08:00"
  }
}
```

### 文件约束

- 空路径使用 `~/Downloads/bob-wordbook.jsonl`。
- 配置路径必须是绝对路径或以 `~/` 开头。
- 文件扩展名必须为 `.jsonl`。
- 不存在的父目录会以 `0755` 创建；新文件权限为 `0600`。
- 每条记录在内存中完成 JSON 编码后，以一次追加写入落盘，并执行 `fsync` 后才返回成功。
- 进程内写入由互斥锁串行化，避免并发请求交叉写入。

### 本机接口边界

- 默认只监听 `127.0.0.1:19820`。
- 写入请求必须携带 `X-Bob-Wordbook-Client: bob-plugin`。
- 拒绝包含 `Origin` 的写入请求，避免普通网页向本机词库追加内容。
- 请求体上限为 64 KiB，且只接受一个没有未知字段的 JSON 对象。

## JSONL 数据契约

```json
{"text":"take care","created_at":"2026-08-22T10:30:00+08:00"}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `text` | string | 去除首尾空白后的原始单词或短语 |
| `created_at` | string | RFC 3339 时间戳，保留本地时区和必要的小数秒 |

文本中的换行、引号和反斜杠由 JSON 编码器转义，因此每个对象严格占一行。

## 构建与验证

```bash
make test
make build
make plugin
```

- `make test`：运行辅助程序测试。
- `make build`：生成 `bin/bob-wordbook-helper`。
- `make plugin`：根据 `src/info.json` 版本生成 `dist/bob-wordbook-v<version>.bobplugin`。

## 安装与后台运行

`scripts/install.sh` 将 helper 安装到 `~/.local/bin/`，并创建 `com.cian.bob-wordbook-helper` 用户 LaunchAgent。LaunchAgent 使用 `RunAtLoad` 和 `KeepAlive` 保持 helper 运行，标准输出和错误日志写入 `~/Library/Logs/bob-wordbook/`。

`scripts/uninstall.sh` 只移除 helper、LaunchAgent 和运行日志，不删除用户配置的 JSONL 单词本。安装器支持重复执行，用于覆盖升级；Release 同时提供 macOS arm64 和 amd64 合并后的 Universal Binary。
