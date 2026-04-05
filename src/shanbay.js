// 扇贝单词本 API 集成
// 支持：自动从 helper 工具提取的文件读取 token / 手动配置的 token

var SHANBAY_API = "https://apiv3.shanbay.com";
var TOKEN_FILE = "shanbay_auth_token";

/**
 * 获取 auth_token
 * 优先级：自动提取（sandbox 文件） > 手动配置（$option）
 */
function getAuthToken(callback) {
    // 优先从 sandbox 文件读取（由 helper 工具写入）
    var autoExtract = $option.auto_extract !== "0";
    if (autoExtract) {
        try {
            var tokenFromFile = $file.read("$sandbox/" + TOKEN_FILE);
            if (tokenFromFile && tokenFromFile.trim().length > 0) {
                $log.info("Using auto-extracted auth_token from sandbox");
                callback(null, tokenFromFile.trim());
                return;
            }
        } catch (e) {
            $log.warn("Failed to read token from sandbox: " + e);
        }
    }

    // 回退到手动配置
    var manualToken = $option.auth_token;
    if (manualToken && manualToken.trim().length > 0) {
        $log.info("Using manually configured auth_token");
        callback(null, manualToken.trim());
        return;
    }

    callback({
        message:
            "未配置 auth_token。请安装 helper 工具自动提取，或在插件设置中手动填写。",
    });
}

/**
 * 添加单词到扇贝单词本
 */
function addWord(word, callback) {
    getAuthToken(function (err, token) {
        if (err) {
            callback({ error: err.message });
            return;
        }

        $http.request({
            url: SHANBAY_API + "/wordscollection/words_bulk_upload",
            method: "POST",
            header: {
                Cookie: "auth_token=" + token,
                "Content-Type": "application/json",
                "User-Agent":
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            },
            body: {
                business_id: 6,
                words: [word],
            },
            handler: function (resp) {
                if (resp.error) {
                    callback({
                        error: "网络请求失败: " + resp.error.localizedDescription,
                    });
                    return;
                }

                var statusCode = resp.response.statusCode;
                if (statusCode === 200 || statusCode === 201) {
                    callback({ success: true });
                } else {
                    var errorMsg = "HTTP " + statusCode;
                    try {
                        var data = resp.data;
                        if (data && data.msg) {
                            errorMsg = data.msg;
                        }
                    } catch (e) {
                        // ignore
                    }
                    callback({
                        error: errorMsg + "（auth_token 可能已过期）",
                    });
                }
            },
        });
    });
}

/**
 * 验证 auth_token 是否有效
 */
function validate(callback) {
    getAuthToken(function (err, token) {
        if (err) {
            callback(false, err.message);
            return;
        }

        $http.request({
            url: SHANBAY_API + "/wordscollection/words_bulk_upload",
            method: "POST",
            header: {
                Cookie: "auth_token=" + token,
                "Content-Type": "application/json",
                "User-Agent":
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            },
            body: {
                business_id: 6,
                words: ["the"],
            },
            handler: function (resp) {
                if (resp.error) {
                    callback(false, "验证请求失败: " + resp.error.localizedDescription);
                    return;
                }

                var statusCode = resp.response.statusCode;
                if (statusCode === 200 || statusCode === 201) {
                    callback(true, "auth_token 验证成功，插件可以正常使用");
                } else {
                    var msg = "auth_token 无效或已过期（HTTP " + statusCode + "）";
                    try {
                        var data = resp.data;
                        if (data && data.msg) {
                            msg = data.msg;
                        }
                    } catch (e) {
                        // ignore
                    }
                    callback(false, msg);
                }
            },
        });
    });
}
