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

// MARK: - Command Line Arguments

enum Mode: String {
    case extract = "extract"
    case install = "install"
    case uninstall = "uninstall"
    case help = "help"
}

func parseMode() -> Mode {
    let args = CommandLine.arguments
    if args.count > 1 {
        return Mode(rawValue: args[1]) ?? .help
    }
    return .extract
}

func printUsage() {
    let usage = """
    Shanbay Cookie Helper — 自动从浏览器提取扇贝 auth_token

    用法:
      shanbay-cookie-helper              提取 token 并保存到 Bob 沙箱
      shanbay-cookie-helper extract      同上
      shanbay-cookie-helper install      安装 LaunchAgent（每 30 分钟自动刷新）
      shanbay-cookie-helper uninstall    卸载 LaunchAgent
      shanbay-cookie-helper help         显示帮助
    """
    print(usage)
}

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

// MARK: - Cryptography (Pure Swift using CryptoKit + openssl for AES-CBC)

/// PBKDF2-HMAC-SHA1 key derivation
func deriveKeyPBKDF2(password: String, salt: Data, iterations: Int, keyLength: Int) -> Data {
    let passwordData = Data(password.utf8)
    let blockSize = 20  // SHA1 digest length
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

/// HMAC-SHA1 using CryptoKit
func hmacSHA1(key: Data, data: Data) -> Data {
    let symmetricKey = SymmetricKey(data: key)
    let authCode = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey)
    return Data(authCode)
}

/// Convert integer to 4-byte big-endian data
func bigEndianData(_ value: Int) -> Data {
    var intVal = UInt32(value).bigEndian
    return Data(bytes: &intVal, count: 4)
}

/// AES-128-CBC 解密（通过 macOS 自带的 openssl 命令行）
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

        // 移除 PKCS7 padding
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

/// 解密 Chromium 浏览器 cookie（v10 / v20）
func decryptChromiumCookie(encryptedValue: Data, browser: String) -> String? {
    guard encryptedValue.count > 3 else { return nil }

    let prefix = String(data: encryptedValue.prefix(3), encoding: .utf8)
    guard prefix == "v10" || prefix == "v20" else { return nil }

    let ciphertext = Data(encryptedValue.dropFirst(3))

    let (serviceName, accountName): (String, String) = browser == "edge"
        ? ("Microsoft Edge Safe Storage", "Microsoft Edge")
        : ("Chrome Safe Storage", "Chrome")

    guard let password = getKeychainPassword(service: serviceName, account: accountName)
    else {
        return nil
    }

    let salt = Data("saltysalt".utf8)
    let key = deriveKeyPBKDF2(
        password: password,
        salt: salt,
        iterations: 1003,
        keyLength: 16
    )

    let iv = Data(repeating: 0x20, count: 16)

    guard let decrypted = decryptAES128CBC(data: ciphertext, key: key, iv: iv)
    else { return nil }

    return String(data: decrypted, encoding: .utf8)
}

// MARK: - SQLite Cookie Extraction

/// 从 Chromium 系浏览器提取 auth_token
func extractTokenFromChromiumDB(dbPath: String, browser: String) -> String? {
    let tempPath = NSTemporaryDirectory() + "shanbay_helper_\(browser)_cookies.db"
    try? FileManager.default.removeItem(atPath: tempPath)
    do {
        try FileManager.default.copyItem(atPath: dbPath, toPath: tempPath)
    } catch {
        return nil
    }
    defer {
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    var db: OpaquePointer?
    guard sqlite3_open(tempPath, &db) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }

    let query = """
        SELECT encrypted_value FROM cookies
        WHERE host_key LIKE ? AND name = ?
        ORDER BY creation_utc DESC
        LIMIT 1
    """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
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

/// 从 Firefox 提取 auth_token（明文存储）
func extractTokenFromFirefoxDB(dbPath: String) -> String? {
    let tempPath = NSTemporaryDirectory() + "shanbay_helper_firefox_cookies.db"
    try? FileManager.default.removeItem(atPath: tempPath)
    do {
        try FileManager.default.copyItem(atPath: dbPath, toPath: tempPath)
    } catch {
        return nil
    }
    defer {
        try? FileManager.default.removeItem(atPath: tempPath)
    }

    var db: OpaquePointer?
    guard sqlite3_open(tempPath, &db) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }

    let query = """
        SELECT value FROM moz_cookies
        WHERE host LIKE ? AND name = ?
        ORDER BY creationTime DESC
        LIMIT 1
    """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
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

// MARK: - Core Logic

/// 从所有已安装的浏览器中提取扇贝 auth_token
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

/// 保存 token 到 Bob 沙箱目录
func saveToken(_ token: String, toPath customPath: String? = nil) -> Bool {
    let savePath: String
    if let custom = customPath {
        savePath = custom
    } else {
        savePath = bobSandboxPath + "/" + tokenFileName
    }

    do {
        let dir = (customPath != nil)
            ? (customPath! as NSString).deletingLastPathComponent
            : bobSandboxPath
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        try token.write(toFile: savePath, atomically: true, encoding: .utf8)
        print("[INFO] Token saved to: \(savePath)")
        return true
    } catch {
        print("[ERROR] Failed to save token: \(error.localizedDescription)")
        return false
    }
}

// MARK: - LaunchAgent Management

let launchAgentLabel = "com.shanbay-cookie-helper.refresh"
let launchAgentPlistName = launchAgentLabel + ".plist"
let launchAgentPlistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(launchAgentLabel)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/shanbay-cookie-helper</string>
    </array>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/shanbay-cookie-helper.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/shanbay-cookie-helper.err</string>
</dict>
</plist>
"""

func installLaunchAgent() {
    let launchAgentsDir = NSHomeDirectory() + "/Library/LaunchAgents"
    let plistPath = launchAgentsDir + "/" + launchAgentPlistName
    let binaryPath = "/usr/local/bin/shanbay-cookie-helper"

    guard FileManager.default.fileExists(atPath: binaryPath) else {
        print("[ERROR] Binary not found at \(binaryPath)")
        print("[HINT] Run install.sh first to build and install the helper.")
        exit(1)
    }

    do {
        try FileManager.default.createDirectory(
            atPath: launchAgentsDir,
            withIntermediateDirectories: true
        )
        try launchAgentPlistContent.write(
            toFile: plistPath,
            atomically: true,
            encoding: .utf8
        )

        // 先卸载旧的
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["bootout", "gui/\(getuid())/\(launchAgentLabel)"]
        try? unload.run()
        unload.waitUntilExit()

        // 加载新的
        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["bootstrap", "gui/\(getuid())", plistPath]
        try? load.run()
        load.waitUntilExit()

        print("[SUCCESS] LaunchAgent installed. Token will refresh every 30 minutes.")
        print("[INFO] Log: /tmp/shanbay-cookie-helper.log")
    } catch {
        print("[ERROR] Failed to install LaunchAgent: \(error.localizedDescription)")
        exit(1)
    }
}

func uninstallLaunchAgent() {
    let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/" + launchAgentPlistName

    let unload = Process()
    unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unload.arguments = ["bootout", "gui/\(getuid())/\(launchAgentLabel)"]
    try? unload.run()
    unload.waitUntilExit()

    try? FileManager.default.removeItem(atPath: plistPath)

    for logFile in [
        "/tmp/shanbay-cookie-helper.log",
        "/tmp/shanbay-cookie-helper.err",
    ] {
        try? FileManager.default.removeItem(atPath: logFile)
    }

    print("[SUCCESS] LaunchAgent uninstalled.")
}

// MARK: - Entry Point

let mode = parseMode()

switch mode {
case .help:
    printUsage()

case .extract:
    let result = extractShanbayAuthToken()
    if let (token, source) = result {
        print("[INFO] Extracted auth_token from \(source): \(token.prefix(8))...\(token.suffix(4))")
        if saveToken(token) {
            print("[SUCCESS] Shanbay auth_token updated successfully.")
        } else {
            exit(1)
        }
    } else {
        print("[ERROR] Could not find Shanbay auth_token from any browser.")
        print("[HINT] Make sure you are logged in to shanbay.com in Chrome, Edge, or Firefox.")
        exit(1)
    }

case .install:
    installLaunchAgent()

case .uninstall:
    uninstallLaunchAgent()
}
