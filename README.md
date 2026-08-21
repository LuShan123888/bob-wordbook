# Bob Wordbook

Bob Wordbook 将 Bob 接收到的英文单词或短语逐条追加到本地 JSONL 文件。默认输出文件是：

```text
~/Downloads/bob-wordbook.jsonl
```

Bob 插件只能写自己的沙盒目录，无法直接访问 Downloads，因此本项目由两部分组成：

- `src/`：Bob 文本翻译插件，读取 Bob 传入的原始文本并调用本机接口。
- `cmd/bob-wordbook-helper/`：只监听 `127.0.0.1` 的 Go 辅助程序，负责写入 JSONL。

## JSONL 格式

每次保存追加一个 JSON 对象和一个换行符：

```json
{"text":"take care","created_at":"2026-08-22T10:30:00+08:00"}
```

文本中的换行、引号等字符会由 JSON 编码器转义，因此一条记录始终只占 JSONL 的一行。

## 构建与测试

项目使用 Go 1.22，无第三方依赖：

```bash
make test
make build
make plugin
```

构建结果：

- `bin/bob-wordbook-helper`：本地辅助程序。
- `dist/bob-wordbook-v2.1.0.bobplugin`：Bob 插件安装包。

## 使用

1. 在终端启动辅助程序：

   ```bash
   ./bin/bob-wordbook-helper
   ```

2. 双击 `dist/bob-wordbook-v2.1.0.bobplugin` 安装插件。
3. 在 Bob 的「设置 → 服务」中添加并启用 `Wordbook JSONL`。
4. 选中或输入英文单词、短语并调用 Bob；插件会保存 Bob 传入的文本，并在结果中显示实际文件路径。

Bob 没有向插件提供直接读取系统剪贴板的接口。本插件保存的是 Bob 调用翻译服务时传入的文本：划词翻译优先使用未经预处理的 `originalText`，输入翻译使用 `text`。

## 自定义路径

在 Bob 的插件设置中修改「JSONL 文件路径」。路径必须满足：

- 是绝对路径，或以 `~/` 开头；
- 以 `.jsonl` 结尾。

辅助程序会自动创建不存在的父目录。也可以在启动辅助程序时修改其空路径请求所使用的默认文件：

```bash
./bin/bob-wordbook-helper -default-path ~/Documents/english/wordbook.jsonl
```

若 macOS 阻止终端或辅助程序访问 Downloads，请在「系统设置 → 隐私与安全性 → 文件与文件夹」中允许相应访问。

## 本机接口

- 健康检查：`GET http://127.0.0.1:19820/healthz`
- 新增记录：`POST http://127.0.0.1:19820/v1/entries`

写入接口只接受 Bob 插件使用的客户端请求头，并拒绝带网页 `Origin` 的请求，避免普通网页向本机词库追加内容。

## License

MIT
