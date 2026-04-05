// Bob 插件入口：将查询的英语单词自动收集到单词本
// 本插件不执行翻译，仅作为单词收集的桥梁
//
// 收集目标：
// 1. 扇贝单词本（即时，通过 HTTP API）
// 2. 本地 Markdown 文件（通过 helper 定时处理队列）

var shanbay = require("./shanbay.js");

var QUEUE_FILE = "$sandbox/word_queue.jsonl";

function supportLanguages() {
    return ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "ru", "it", "pt"];
}

/**
 * 将单词写入本地队列，供 helper 处理后写入 Markdown 文件
 */
function enqueueWord(word) {
    var entry = JSON.stringify({
        word: word,
        time: new Date().toISOString(),
    });
    var existing = "";
    try {
        existing = $file.read(QUEUE_FILE) || "";
    } catch (e) {
        // 文件不存在，忽略
    }
    try {
        $file.write(QUEUE_FILE, existing + entry + "\n");
    } catch (e) {
        $log.error("Failed to write word queue: " + e);
    }
}

function translate(query, completion) {
    var text = query.text.trim();
    var detectFrom = query.detectFrom;

    // 仅处理英文
    if (detectFrom !== "en") {
        completion({ result: { from: detectFrom, to: query.to, toParagraphs: [] } });
        return;
    }

    // 检查是否仅添加单词
    var wordOnly = $option.word_only !== "0";
    if (wordOnly && text.indexOf(" ") !== -1) {
        completion({ result: { from: detectFrom, to: query.to, toParagraphs: [] } });
        return;
    }

    // 写入本地队列（供 helper 写入 Markdown）
    enqueueWord(text);

    // 添加到扇贝（即时）
    shanbay.addWord(text, function (result) {
        var showResult = $option.show_result !== "0";
        if (result.error) {
            $log.warn("Shanbay: " + result.error);
            completion({
                result: {
                    from: detectFrom,
                    to: query.to,
                    toParagraphs: showResult
                        ? ["📋 已记录: " + text + "\n⚠️ 扇贝同步失败: " + result.error]
                        : [],
                },
            });
        } else {
            $log.info("Word collected: " + text);
            completion({
                result: {
                    from: detectFrom,
                    to: query.to,
                    toParagraphs: showResult
                        ? ["📋 已记录: " + text]
                        : [],
                },
            });
        }
    });
}

function pluginValidate(completion) {
    shanbay.validate(function (valid, message) {
        if (valid) {
            completion({
                result: {
                    from: "en",
                    to: "zh-Hans",
                    toParagraphs: ["✅ " + message],
                },
            });
        } else {
            completion({
                error: { type: "secretKey", message: message },
            });
        }
    });
}

function pluginTimeoutInterval() {
    return 15;
}
