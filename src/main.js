// Bob 插件入口：将查询的英语单词自动添加到扇贝单词本
// 本插件不执行翻译，仅作为单词收集的桥梁

var shanbay = require("./shanbay.js");

function supportLanguages() {
    return ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "ru", "it", "pt"];
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

    shanbay.addWord(text, function (result) {
        var showResult = $option.show_result !== "0";
        if (result.error) {
            $log.error("Shanbay add word failed: " + result.error);
            completion({
                result: {
                    from: detectFrom,
                    to: query.to,
                    toParagraphs: showResult
                        ? ["⚠️ 扇贝添加失败: " + result.error]
                        : [],
                },
            });
        } else {
            $log.info("Shanbay add word success: " + text);
            completion({
                result: {
                    from: detectFrom,
                    to: query.to,
                    toParagraphs: showResult
                        ? ["✅ 已添加到扇贝单词本: " + text]
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
