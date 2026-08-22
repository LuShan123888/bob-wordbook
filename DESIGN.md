# bob-wordbook 设计文档

## 目标

bob-wordbook 是一个独立的 Bob 文本翻译服务。它通过 AIHubMix 生成翻译和英语学习建议，并仅将英文输入及完整成功结果追加到用户指定的本地 JSONL 文件。

默认文件为：

```text
~/Downloads/bob-wordbook.jsonl
```

项目不读取 Bob 的内部数据库，不拦截其他翻译服务，也不复制 Bob 原生 AIHubMix 服务的配置。

## 架构

```text
Bob query
   │
   ▼
JavaScriptCore 插件
   ├── POST https://aihubmix.com/v1/chat/completions
   │       └── OpenAI-compatible SSE
   │
   └── POST http://127.0.0.1:19820/v3/entries
           └── 仅完整、成功且检测为英文的结果
                    │
                    ▼
              Go 本地 helper
                    │ O_APPEND + fsync
                    ▼
              用户指定的 JSONL
```

Bob 插件的 `$file` 只能写插件沙盒，因此持久化仍由只监听本机回环地址的 helper 完成。

## 翻译流程

1. 插件优先读取 `query.originalText`，不可用时读取 `query.text`。
2. 校验 AIHubMix API Key 和模型配置。
3. 通过固定端点 `https://aihubmix.com/v1/chat/completions` 发起流式请求。
4. 插件按 SSE 事件边界重组任意分块并解析 `choices[0].delta.content`；短语和句子调用 `query.onStream`，单词等待完整 JSON 后再渲染，避免显示中间协议数据。
5. 只有 HTTP 成功、数据可解析、收到 `[DONE]` 且最终文本非空时，结果才被视为完整。
6. 英文且不含中文汉字的输入调用 helper v3 接口；其他输入只返回翻译结果。
7. helper 返回后，插件通过 `query.onCompletion` 返回最终结果：单词使用 Bob 原生 `toDict`，短语和句子使用 `toParagraphs`。

截断流、API 错误或空结果不会写入 JSONL。helper 写入失败不会丢弃已经成功生成的译文，而是在最终结果中追加保存失败警告。

## Prompt

未配置 System Prompt 时：

- 英文单词：要求返回受限 JSON，由插件校验后映射到 Bob 原生词典结构；Bob 只展示核心字段和第一条例句。
- 英文短语：要求含义、使用场景、搭配和例句。
- 英文句子：要求翻译、语法与自然度检查、修正版和推荐表达。
- 非英文输入：只翻译到 Bob 检测出的目标语言。

自定义 System Prompt 支持替换 `$query.text`、`$query.detectFromLang` 和 `$query.detectToLang`。API Key 不进入 Prompt、helper 请求、日志或 JSONL。

## 本地辅助程序

辅助程序位于 `cmd/bob-wordbook-helper/`，使用 Go 1.22 标准库实现。

### 接口

- `GET /healthz`：健康检查。
- `POST /v1/entries`：兼容 2.1.0 及更早插件的原文记录接口。
- `POST /v2/entries`：保存英文原文及完整 AIHubMix 结果。
- `POST /v3/entries`：保存结构化的单词或文本学习结果；3.1.0 插件使用此接口。

v2 请求示例：

```json
{
  "text": "piece of cake",
  "result": "## 释义\n小菜一碟",
  "source_language": "en",
  "target_language": "zh-Hans",
  "provider": "aihubmix",
  "model": "gpt-4o-mini",
  "path": "~/Downloads/bob-wordbook.jsonl"
}
```

### v2 校验

- `text` 必须包含英文字母且不得包含中文汉字。
- `result`、`target_language` 和 `model` 不得为空。
- `source_language` 必须为 `en`，`provider` 必须为 `aihubmix`。
- 输出路径必须是绝对路径或以 `~/` 开头，并以 `.jsonl` 结尾。
- 路径不得包含反斜杠，`~` 只能作为开头的 `~/` 使用。
- 请求体不得超过 64 KiB，不接受未知字段或连续多个 JSON 对象。

## JSONL v3 数据契约

```json
{
  "schema_version": 3,
  "text": "translation",
  "kind": "word",
  "content": {
    "word": "translation",
    "phonetics": [{"type": "us", "value": "trænzˈleɪʃən"}],
    "parts": [{"part": "n.", "means": ["翻译", "译文"]}],
    "collocations": [{"text": "Chinese translation", "meaning": "中文译文"}],
    "examples": [{"text": "Please send me the translation.", "translation": "请把译文发给我。"}]
  },
  "source_language": "en",
  "target_language": "zh-Hans",
  "provider": "aihubmix",
  "model": "gpt-4o-mini",
  "created_at": "2026-08-22T11:15:00+08:00"
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `schema_version` | number | 固定为 `3` |
| `text` | string | 去除首尾空白后的英文原文 |
| `kind` | string | `word` 或 `text` |
| `content` | object | 单词的结构化词典内容，或短语/句子的 `text` 结果 |
| `source_language` | string | 固定为 `en` |
| `target_language` | string | Bob 检测出的目标语言代码 |
| `provider` | string | 固定为 `aihubmix` |
| `model` | string | 本次请求使用的模型 ID |
| `created_at` | string | RFC 3339 时间戳，保留本地时区和必要的小数秒 |

每个对象严格占一行。已有 schema v1/v2 记录无需迁移，可以与 v3 记录共存。

## 文件与本机安全边界

- helper 默认且强制只绑定回环地址。
- 写入请求必须携带 `X-Bob-Wordbook-Client: bob-plugin`。
- 拒绝包含 `Origin` 的写入请求，避免普通网页向本机追加内容。
- 不存在的父目录以 `0755` 创建，新文件权限为 `0600`。
- 每条记录先在内存中完成 JSON 编码，再执行一次追加写入和 `fsync`。
- 进程内写入通过互斥锁串行化，避免并发请求交叉。

## 构建与验证

```bash
make check
make build
make plugin
```

`make check` 覆盖 Go 竞态测试、`go vet`、Go 格式、插件行为、JavaScript 语法、Shell 语法和插件元数据。
