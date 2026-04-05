import Foundation
import Security
import CryptoKit
import SQLite3

// MARK: - Configuration

let shanbayDomain = "shanbay.com"
let tokenCookieName = "auth_token"

// Bob 沙箱路径（插件通过 $sandbox/ 前缀访问同一位置）
let bobSandboxPath = NSHomeDirectory()
    + "/Library/Containers/com.hezongyidev.Bob/Data/Documents/InstalledPluginSandbox"
let tokenFileName = "shanbay_auth_token"
let queueFileName = "word_queue.jsonl"

// Helper 配置路径
let configDir = NSHomeDirectory() + "/.config/bob-wordbook"
let configPath = configDir + "/config.json"

// MARK: - Config

struct HelperConfig: Codable {
    var markdown_path: String?
}

func loadConfig() -> HelperConfig {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
        let config = try? JSONDecoder().decode(HelperConfig.self, from: data)
    else {
        return HelperConfig()
    }
    return config
}

func saveConfig(_ config: HelperConfig) -> Bool {
    do {
        try FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(config)
        try data.write(to: URL(fileURLWithPath: configPath))
        return true
    } catch {
        print("[ERROR] Failed to save config: \(error.localizedDescription)")
        return false
    }
}

// MARK: - Command Line

enum Mode: String {
    case run = "run"
    case extract = "extract"
    case process = "process"
    case install = "install"
    case uninstall = "uninstall"
    case initConfig = "init"
    case help = "help"
}

func parseMode() -> Mode {
    let args = CommandLine.arguments
    if args.count > 1 {
        return Mode(rawValue: args[1]) ?? .help
    }
    return .run
}

func printUsage() {
    let usage = """
    bob-wordbook-helper — Bob 单词本辅助工具

    用法:
      bob-wordbook-helper              提取扇贝 token + 处理单词队列（默认）
      bob-wordbook-helper extract      仅提取扇贝 token
      bob-wordbook-helper process      仅处理单词队列（写入 Markdown）
      bob-wordbook-helper init         初始化配置（设置 Markdown 文件路径）
      bob-wordbook-helper install      安装 LaunchAgent（每 1 分钟自动运行）
      bob-wordbook-helper uninstall    卸载 LaunchAgent
      bob-wordbook-helper help         显示帮助
    """
    print(usage)
}

// MARK: - Date Formatting

let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.locale = Locale(identifier: "zh_CN")
    return f
}()

// MARK: - Browser Cookie Paths

func getChromeCookiePaths() -> [(path: String, browser: String)] {
    let chromeBase = NSHomeDirectory() + "/Library/Application Support/Google/Chrome"
    var results: [(String, String)] = []

    var allProfiles = ["Default"]
    if let contents = try? FileManager.default.contentsOfDirectory(atPath: chromeBase) {
        allProfiles.append(contentsOf: contents.filter { $0.hasPrefix("Profile ") })
    }

    for profile in allProfiles {
        let cookiePath = chromeBase + "/" + profile + "/Cookies"
        if FileManager.default.fileExists(atPath: cookiePath) {
            results.append((cookiePath, "chrome"))
        }
    }
    return results
}

func getEdgeCookiePaths() -> [(path: String, browser: String)] {
    let edgeBase = NSHomeDirectory()
        + "/Library/Application Support/Microsoft Edge"
    var results: [(String, String)] = []

    var allProfiles = ["Default"]
    if let contents = try? FileManager.default.contentsOfDirectory(atPath: edgeBase) {
        allProfiles.append(contentsOf: contents.filter { $0.hasPrefix("Profile ") })
    }

    for profile in allProfiles {
        let cookiePath = edgeBase + "/" + profile + "/Cookies"
        if FileManager.default.fileExists(atPath: cookiePath) {
            results.append((cookiePath, "edge"))
        }
    }
    return results
}

func getFirefoxCookiePaths() -> [(path: String, browser: String)] {
    let firefoxBase = NSHomeDirectory()
        + "/Library/Application Support/Firefox/Profiles"
    var results: [(String, String)] = []

    if let contents = try? FileManager.default.contentsOfDirectory(atPath: firefoxBase) {
        for item in contents where item.contains(".default") {
            let cookiePath = firefoxBase + "/" + item + "/cookies.sqlite"
            if FileManager.default.fileExists(atPath: cookiePath) {
                results.append((cookiePath, "firefox"))
            }
        }
    }
    return results
}

// MARK: - Keychain Access

func getKeychainPassword(service: String, account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data,
        let password = String(data: data, encoding: .utf8)
    else {
        print("[WARN] Keychain access denied for service='\(service)' account='\(account)' (status=\(status))")
        return nil
    }
    return password
}

// MARK: - Cryptography

func deriveKeyPBKDF2(password: String, salt: Data, iterations: Int, keyLength: Int) -> Data {
    let passwordData = Data(password.utf8)
    let blockSize = 20  // SHA1
    let blockCount = (keyLength + blockSize - 1) / blockSize
    var derivedKey = Data()

    for blockIndex in 1...blockCount {
        var u = hmacSHA1(key: passwordData, data: salt + bigEndianData(blockIndex))
        var result = u
        for _ in 1..<iterations {
            u = hmacSHA1(key: passwordData, data: u)
            for i in 0..<result.count {
                result[i] ^= u[i]
            }
        }
        derivedKey.append(result)
    }
    return Data(derivedKey.prefix(keyLength))
}

func hmacSHA1(key: Data, data: Data) -> Data {
    let symmetricKey = SymmetricKey(data: key)
    let authCode = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey)
    return Data(authCode)
}

func bigEndianData(_ value: Int) -> Data {
    var intVal = UInt32(value).bigEndian
    return Data(bytes: &intVal, count: 4)
}

func decryptAES128CBC(data: Data, key: Data, iv: Data) -> Data? {
    guard data.count % 16 == 0 else { return nil }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = [
        "enc", "-aes-128-cbc", "-d",
        "-K", key.map { String(format: "%02x", $0) }.joined(),
        "-iv", iv.map { String(format: "%02x", $0) }.joined(),
        "-nopad",
    ]

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe

    do {
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        try stdinPipe.fileHandleForWriting.close()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        guard let lastByte = outputData.last, lastByte > 0, lastByte <= 16 else {
            return outputData
        }
        let paddingLength = Int(lastByte)
        let paddingBytes = outputData.suffix(paddingLength)
        if paddingBytes.allSatisfy({ $0 == lastByte }) {
            return outputData.dropLast(paddingLength)
        }
        return outputData
    } catch {
        return nil
    }
}

func decryptChromiumCookie(encryptedValue: Data, browser: String) -> String? {
    guard encryptedValue.count > 3 else { return nil }
    let prefix = String(data: encryptedValue.prefix(3), encoding: .utf8)
    guard prefix == "v10" || prefix == "v20" else { return nil }

    let ciphertext = Data(encryptedValue.dropFirst(3))
    let (serviceName, accountName): (String, String) = browser == "edge"
        ? ("Microsoft Edge Safe Storage", "Microsoft Edge")
        : ("Chrome Safe Storage", "Chrome")

    guard let password = getKeychainPassword(service: serviceName, account: accountName)
    else { return nil }

    let salt = Data("saltysalt".utf8)
    let key = deriveKeyPBKDF2(password: password, salt: salt, iterations: 1003, keyLength: 16)
    let iv = Data(repeating: 0x20, count: 16)

    guard let decrypted = decryptAES128CBC(data: ciphertext, key: key, iv: iv)
    else { return nil }

    return String(data: decrypted, encoding: .utf8)
}

// MARK: - SQLite Cookie Extraction

func extractTokenFromChromiumDB(dbPath: String, browser: String) -> String? {
    let tempPath = NSTemporaryDirectory() + "bob_wordbook_\(browser)_cookies.db"
    try? FileManager.default.removeItem(atPath: tempPath)
    do {
        try FileManager.default.copyItem(atPath: dbPath, toPath: tempPath)
    } catch { return nil }
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    var db: OpaquePointer?
    guard sqlite3_open(tempPath, &db) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db,
        "SELECT encrypted_value FROM cookies WHERE host_key LIKE ? AND name = ? ORDER BY creation_utc DESC LIMIT 1",
        -1, &stmt, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, ("%\(shanbayDomain)"), -1, nil)
    sqlite3_bind_text(stmt, 2, tokenCookieName, -1, nil)

    if sqlite3_step(stmt) == SQLITE_ROW {
        let blobPtr = sqlite3_column_blob(stmt, 0)
        let blobSize = Int(sqlite3_column_bytes(stmt, 0))
        guard blobPtr != nil, blobSize > 0 else { return nil }
        let encryptedValue = Data(bytes: blobPtr!, count: blobSize)
        return decryptChromiumCookie(encryptedValue: encryptedValue, browser: browser)
    }
    return nil
}

func extractTokenFromFirefoxDB(dbPath: String) -> String? {
    let tempPath = NSTemporaryDirectory() + "bob_wordbook_firefox_cookies.db"
    try? FileManager.default.removeItem(atPath: tempPath)
    do {
        try FileManager.default.copyItem(atPath: dbPath, toPath: tempPath)
    } catch { return nil }
    defer { try? FileManager.default.removeItem(atPath: tempPath) }

    var db: OpaquePointer?
    guard sqlite3_open(tempPath, &db) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db,
        "SELECT value FROM moz_cookies WHERE host LIKE ? AND name = ? ORDER BY creationTime DESC LIMIT 1",
        -1, &stmt, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, ("%\(shanbayDomain)"), -1, nil)
    sqlite3_bind_text(stmt, 2, tokenCookieName, -1, nil)

    if sqlite3_step(stmt) == SQLITE_ROW {
        if let value = sqlite3_column_text(stmt, 0) {
            return String(cString: value)
        }
    }
    return nil
}

// MARK: - Shanbei Token Extraction

func extractShanbayAuthToken() -> (token: String, source: String)? {
    for (path, browser) in getChromeCookiePaths() {
        if let token = extractTokenFromChromiumDB(dbPath: path, browser: browser) {
            return (token, browser)
        }
    }
    for (path, browser) in getEdgeCookiePaths() {
        if let token = extractTokenFromChromiumDB(dbPath: path, browser: browser) {
            return (token, browser)
        }
    }
    for (path, _) in getFirefoxCookiePaths() {
        if let token = extractTokenFromFirefoxDB(dbPath: path) {
            return (token, "firefox")
        }
    }
    return nil
}

func saveToken(_ token: String) -> Bool {
    let savePath = bobSandboxPath + "/" + tokenFileName
    do {
        try FileManager.default.createDirectory(atPath: bobSandboxPath, withIntermediateDirectories: true)
        try token.write(toFile: savePath, atomically: true, encoding: .utf8)
        return true
    } catch {
        print("[ERROR] Failed to save token: \(error.localizedDescription)")
        return false
    }
}

// MARK: - Word Queue

struct QueueEntry: Codable {
    var word: String
    var time: String  // ISO 8601
}

func readQueue() -> [QueueEntry] {
    let queuePath = bobSandboxPath + "/" + queueFileName
    guard let content = try? String(contentsOfFile: queuePath, encoding: .utf8),
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return []
    }

    var entries: [QueueEntry] = []
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
            let data = trimmed.data(using: .utf8),
            let entry = try? JSONDecoder().decode(QueueEntry.self, from: data)
        else { continue }
        entries.append(entry)
    }
    return entries
}

func clearQueue() {
    let queuePath = bobSandboxPath + "/" + queueFileName
    try? "".write(toFile: queuePath, atomically: true, encoding: .utf8)
}

// MARK: - Markdown Wordbook

/// Markdown 单词本表格格式：
/// | Word | Created | Updated |
/// |:-----|:--------|:--------|
/// | example | 2026-04-05 14:30 | 2026-04-05 14:30 |

let markdownHeader = """
# Word Book

> 自动由 Bob 单词本插件生成，请勿手动编辑表格部分。

| Word | Created | Updated |
|:-----|:--------|:--------|
"""

let tableSeparator = "|:-----|:--------|:--------|"

func parseMarkdownTable(_ lines: [String]) -> (headerLines: [String], rows: [String], footerLines: [String]) {
    var headerLines: [String] = []
    var rows: [String] = []
    var footerLines: [String] = []
    var inTable = false
    var pastTable = false

    for line in lines {
        if line.trimmingCharacters(in: .whitespaces) == tableSeparator {
            inTable = true
            headerLines.append(line)
            continue
        }
        if inTable && line.hasPrefix("|") && line.hasSuffix("|") {
            // 跳过分隔行之后紧跟的空行
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pastTable = true
                inTable = false
                footerLines.append(line)
                continue
            }
            rows.append(line)
            continue
        }
        if inTable && !line.hasPrefix("|") {
            pastTable = true
            inTable = false
        }
        if pastTable {
            footerLines.append(line)
        } else {
            headerLines.append(line)
        }
    }

    return (headerLines, rows, footerLines)
}

/// 从表格行中提取单词（第一个 `|` 后到第二个 `|` 之间的内容）
func extractWordFromRow(_ row: String) -> String {
    let parts = row.split(separator: "|", omittingEmptySubsequences: true)
    guard parts.count >= 1 else { return "" }
    return parts[0].trimmingCharacters(in: .whitespaces).lowercased()
}

/// 构造表格行
func makeTableRow(word: String, created: String, updated: String) -> String {
    return "| \(word) | \(created) | \(updated) |"
}

func processQueueToMarkdown(entries: [QueueEntry], markdownPath: String) {
    let fileManager = FileManager.default

    // 读取现有文件
    var existingContent: String?
    if fileManager.fileExists(atPath: markdownPath) {
        existingContent = try? String(contentsOfFile: markdownPath, encoding: .utf8)
    }

    let lines = existingContent?.components(separatedBy: .newlines) ?? []

    // 检查文件是否有表格（通过查找分隔行）
    let hasTable = lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == tableSeparator })

    var wordMap: [String: (created: String, updated: String)] = [:]

    if hasTable {
        // 解析现有表格
        let (headerLines, rows, footerLines) = parseMarkdownTable(lines)

        // 收集已有单词
        for row in rows {
            let word = extractWordFromRow(row)
            guard !word.isEmpty else { continue }
            // 解析 created 和 updated
            let parts = row.split(separator: "|", omittingEmptySubsequences: true)
            let created = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            let updated = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : created
            wordMap[word] = (created, updated)
        }

        // 处理队列中的新单词
        for entry in entries {
            let word = entry.word.lowercased()
            let now = dateFormatter.string(from: Date())
            if let existing = wordMap[word] {
                // 单词已存在：保留 Created，更新 Updated
                wordMap[word] = (existing.created, now)
            } else {
                // 新单词：Created = Updated = now
                wordMap[word] = (now, now)
            }
        }

        // 重建表格内容
        var newLines = headerLines
        // 保留到分隔行
        if !newLines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == tableSeparator }) {
            newLines.append(tableSeparator)
        }
        for (word, times) in wordMap.sorted(by: { $0.value.updated > $1.value.updated }) {
            newLines.append(makeTableRow(word: word, created: times.created, updated: times.updated))
        }
        newLines.append(contentsOf: footerLines)

        let newContent = newLines.joined(separator: "\n")
        try? newContent.write(toFile: markdownPath, atomically: true, encoding: .utf8)

    } else {
        // 文件不存在或没有表格：创建新表格
        var newLines = lines
        if !newLines.isEmpty && newLines.last?.isEmpty == false {
            newLines.append("")
        }

        // 如果文件完全为空，写入完整 header
        if newLines.isEmpty || (newLines.count == 1 && newLines[0].isEmpty) {
            newLines = markdownHeader.components(separatedBy: .newlines)
            // 去掉末尾空行
            while newLines.last?.isEmpty == true { newLines.removeLast() }
        } else {
            // 文件有内容但没有表格，追加表格
            newLines.append("")
            newLines.append("| Word | Created | Updated |")
            newLines.append(tableSeparator)
        }

        // 处理队列
        for entry in entries {
            let word = entry.word.lowercased()
            let now = dateFormatter.string(from: Date())
            wordMap[word] = (now, now)
        }

        for (word, times) in wordMap {
            newLines.append(makeTableRow(word: word, created: times.created, updated: times.updated))
        }

        newLines.append("")
        let newContent = newLines.joined(separator: "\n")
        try? newContent.write(toFile: markdownPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Process Queue

func processQueue() {
    let config = loadConfig()

    guard let markdownPath = config.markdown_path, !markdownPath.isEmpty else {
        print("[INFO] No markdown_path configured. Run 'bob-wordbook-helper init' to set up.")
        return
    }

    let entries = readQueue()
    guard !entries.isEmpty else {
        print("[INFO] No pending words in queue.")
        return
    }

    // 去重：同一批次中重复的单词只保留最后一次
    var deduped: [String: QueueEntry] = [:]
    for entry in entries {
        deduped[entry.word.lowercased()] = entry
    }
    let uniqueEntries = Array(deduped.values)

    print("[INFO] Processing \(uniqueEntries.count) word(s)...")
    processQueueToMarkdown(entries: uniqueEntries, markdownPath: markdownPath)
    clearQueue()
    print("[SUCCESS] Words written to \(markdownPath)")
}

// MARK: - LaunchAgent

let launchAgentLabel = "com.bob-wordbook-helper.refresh"
let launchAgentPlistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(launchAgentLabel)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bob-wordbook-helper</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/bob-wordbook-helper.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/bob-wordbook-helper.err</string>
</dict>
</plist>
"""

func installLaunchAgent() {
    let launchAgentsDir = NSHomeDirectory() + "/Library/LaunchAgents"
    let plistPath = launchAgentsDir + "/" + launchAgentLabel + ".plist"
    let binaryPath = "/usr/local/bin/bob-wordbook-helper"

    guard FileManager.default.fileExists(atPath: binaryPath) else {
        print("[ERROR] Binary not found at \(binaryPath)")
        print("[HINT] Run 'make install' first.")
        exit(1)
    }

    do {
        try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        try launchAgentPlistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)

        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["bootout", "gui/\(getuid())/\(launchAgentLabel)"]
        try? unload.run()
        unload.waitUntilExit()

        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["bootstrap", "gui/\(getuid())", plistPath]
        try? load.run()
        load.waitUntilExit()

        print("[SUCCESS] LaunchAgent installed (runs every 1 minute).")
        print("[INFO] Log: /tmp/bob-wordbook-helper.log")
    } catch {
        print("[ERROR] Failed to install LaunchAgent: \(error.localizedDescription)")
        exit(1)
    }
}

func uninstallLaunchAgent() {
    let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/" + launchAgentLabel + ".plist"

    let unload = Process()
    unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unload.arguments = ["bootout", "gui/\(getuid())/\(launchAgentLabel)"]
    try? unload.run()
    unload.waitUntilExit()

    try? FileManager.default.removeItem(atPath: plistPath)

    for logFile in ["/tmp/bob-wordbook-helper.log", "/tmp/bob-wordbook-helper.err"] {
        try? FileManager.default.removeItem(atPath: logFile)
    }

    print("[SUCCESS] LaunchAgent uninstalled.")
}

// MARK: - Init Config

func initConfig() {
    print("=== bob-wordbook-helper 初始化 ===")
    print("")

    // 检查是否已有配置
    if FileManager.default.fileExists(atPath: configPath) {
        if let content = try? String(contentsOfFile: configPath, encoding: .utf8) {
            print("当前配置 (\(configPath)):")
            print(content)
            print("")
        }
    }

    print("请输入 Markdown 单词本文件的完整路径：")
    print("（例如：/Users/cian/Notes/wordbook.md）")
    print("留空则跳过本地单词本功能（仅使用扇贝）")
    print("")

    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
        !input.isEmpty
    else {
        // 无 Markdown 路径，保存空配置
        let config = HelperConfig(markdown_path: nil)
        if saveConfig(config) {
            print("")
            print("[INFO] 已保存配置（不使用本地 Markdown 单词本）。")
        }
        return
    }

    // 验证路径
    let expandedPath = (input as NSString).expandingTildeInPath
    let dir = (expandedPath as NSString).deletingLastPathComponent

    if !FileManager.default.fileExists(atPath: dir) {
        print("[ERROR] 目录不存在: \(dir)")
        exit(1)
    }

    // 如果文件不存在，创建初始内容
    if !FileManager.default.fileExists(atPath: expandedPath) {
        try? markdownHeader.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        print("[INFO] 已创建单词本文件: \(expandedPath)")
    }

    let config = HelperConfig(markdown_path: expandedPath)
    if saveConfig(config) {
        print("")
        print("[SUCCESS] 配置已保存到: \(configPath)")
        print("[INFO] 单词本路径: \(expandedPath)")
    }
}

// MARK: - Entry Point

let mode = parseMode()

switch mode {
case .help:
    printUsage()

case .extract:
    if let (token, source) = extractShanbayAuthToken() {
        print("[INFO] Extracted auth_token from \(source): \(token.prefix(8))...\(token.suffix(4))")
        if saveToken(token) {
            print("[SUCCESS] Shanbay auth_token updated.")
        } else {
            exit(1)
        }
    } else {
        print("[WARN] No Shanbay auth_token found. Make sure you're logged in to shanbay.com.")
    }

case .process:
    processQueue()

case .initConfig:
    initConfig()

case .install:
    installLaunchAgent()

case .uninstall:
    uninstallLaunchAgent()

// 默认模式（无参数）：提取 token + 处理队列
case .run:
    // 提取扇贝 token
    if let (token, source) = extractShanbayAuthToken() {
        print("[INFO] Extracted auth_token from \(source): \(token.prefix(8))...\(token.suffix(4))")
        if saveToken(token) {
            print("[SUCCESS] Shanbay auth_token updated.")
        }
    } else {
        print("[WARN] No Shanbay auth_token found.")
    }

    // 处理单词队列
    processQueue()
}
