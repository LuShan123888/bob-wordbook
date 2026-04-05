# bob-shanbay-wordbook

Bob 翻译插件 — 将查询的英语单词自动添加到扇贝单词本。

## 特性

- **自动添加单词**：在 Bob 中查询英文单词时，自动同步到扇贝单词本
- **自动提取 Cookie**：无需手动复制 `auth_token`，通过 helper 工具自动从浏览器提取
- **定时刷新**：LaunchAgent 每 30 分钟自动刷新 token，过期也无需手动干预
- **多浏览器支持**：Chrome、Edge、Firefox
- **手动备选**：自动提取失败时可回退到手动配置的 token
- **词组过滤**：可选仅添加单个单词，跳过包含空格的词组

## 架构

本项目由两部分组成：

```
┌─────────────────────────────────────────────────┐
│                   Bob 翻译软件                    │
│  ┌───────────────────────────────────────────┐  │
│  │           Bob 插件 (JavaScript)            │  │
│  │                                           │  │
│  │  1. 读取 $sandbox/shanbay_auth_token     │  │
│  │  2. 调用扇贝 API 添加单词                  │  │
│  │  3. 回退到手动配置的 $option.auth_token    │  │
│  └──────────────┬────────────────────────────┘  │
│                 │ $sandbox/                      │
└─────────────────┼───────────────────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │  Swift Helper (CLI 工具)   │
    │                           │
    │  • 读取 Chrome/Edge/Firefox│
    │  • 解密 Chromium Cookie    │
    │  • 写入 auth_token 到沙箱  │
    └─────────────┬─────────────┘
                  │ LaunchAgent (每 30 分钟)
                  │
    ┌─────────────┴─────────────┐
    │      浏览器 Cookie 存储     │
    │  Chrome  → AES 加密 SQLite │
    │  Edge    → AES 加密 SQLite │
    │  Firefox → 明文 SQLite     │
    └───────────────────────────┘
```

## 安装

### 前置条件

- macOS 13+
- [Bob](https://bobtranslate.com/) 翻译软件
- Xcode Command Line Tools（`xcode-select --install`）
- 在 Chrome / Edge / Firefox 中登录 [扇贝](https://www.shanbay.com/)

### 步骤

1. **安装 helper 工具**

```bash
cd helper
make install
```

这会编译 Swift helper、安装到 `/usr/local/bin/`、提取首次 token、并配置 LaunchAgent。

> 首次运行时，系统会弹出 Keychain 访问授权窗口（用于解密 Chrome cookie），请点击「允许」。

2. **安装 Bob 插件**

```bash
cd src
zip -r -j ../bob-shanbay-wordbook.bobplugin *
# 双击 bob-shanbay-wordbook.bobplugin 安装到 Bob
```

或在 Bob 中：偏好设置 → 插件 → 点击 `+` → 选择 `bob-shanbay-wordbook.bobplugin`

3. **配置插件**

在 Bob 偏好设置 → 插件 → 扇贝单词本 中：

- **自动提取 Cookie**：保持默认「是」（依赖 helper 工具）
- **Auth Token（手动备选）**：留空（除非 helper 无法工作）
- **仅添加单词**：按需选择
- **显示添加结果**：按需选择

### 验证

在插件设置中点击「验证」按钮，应显示 `✅ auth_token 验证成功`。

## 使用

安装完成后，每次在 Bob 中查询英文单词，该单词会自动添加到你的扇贝单词本。

- 查看日志：`tail -f /tmp/shanbay-cookie-helper.log`
- 手动刷新 token：`shanbay-cookie-helper`

## 卸载

```bash
cd helper
make uninstall
```

## 开发

### 项目结构

```
bob-shanbay-wordbook/
├── src/                    # Bob 插件源码
│   ├── info.json           # 插件清单
│   ├── main.js             # 插件入口
│   └── shanbay.js          # 扇贝 API 集成
├── helper/                 # Cookie 提取工具
│   ├── Sources/
│   │   └── ShanbayCookieHelper/
│   │       └── main.swift  # Swift CLI 工具
│   ├── Makefile            # 构建脚本
│   ├── install.sh          # 安装脚本
│   └── uninstall.sh        # 卸载脚本
├── DESIGN.md               # 设计文档
├── appcast.json            # 自动更新配置
├── release.sh              # 发布脚本
└── README.md               # 本文件
```

### 构建插件包

```bash
bash release.sh
```

### Chrome Cookie 解密原理

Chrome 在 macOS 上使用 AES-128-CBC 加密 cookie：

1. 从 macOS Keychain 获取加密密钥（service: `Chrome Safe Storage`）
2. 使用 PBKDF2-HMAC-SHA1 派生 AES 密钥（salt: `saltysalt`, iterations: 1003, key length: 16）
3. IV 为 16 字节的 `0x20`（空格字符）
4. 密文前缀为 `v10`，去掉前缀后为 AES-CBC 密文

Firefox 的 cookie 为明文存储，直接读取 SQLite 即可。

## 致谢

- 基于 [yuhaowin/wordbook-bob-plugin](https://github.com/yuhaowin/wordbook-bob-plugin) 二次开发
- [Bob](https://bobtranslate.com/) 翻译软件

## License

MIT
