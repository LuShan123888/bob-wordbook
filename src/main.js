var helperURL = "http://127.0.0.1:19820/v1/entries";

function supportLanguages() {
  return ["auto", "en", "zh-Hans", "zh-Hant"];
}

function translate(query, completion) {
  var text = String(query.originalText || query.text || "").trim();
  if (!text) {
    complete(query, completion, {
      error: {
        type: "param",
        message: "没有可保存的单词或短语。"
      }
    });
    return;
  }

  if (query.detectFrom !== "en" || !/[A-Za-z]/.test(text) || /[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/.test(text)) {
    complete(query, completion, {
      error: {
        type: "unsupportedLanguage",
        message: "仅支持保存 Bob 检测为英文且不含中文的单词、短语或句子。"
      }
    });
    return;
  }

  var outputPath = String($option.outputPath || "").trim();
  $http.request({
    method: "POST",
    url: helperURL,
    header: {
      "Content-Type": "application/json",
      "X-Bob-Wordbook-Client": "bob-plugin"
    },
    body: {
      text: text,
      path: outputPath
    },
    timeout: 5,
    cancelSignal: query.cancelSignal,
    handler: function(resp) {
      if (resp.error) {
        complete(query, completion, {
          error: {
            type: "network",
            message: "无法连接 Wordbook 本地辅助程序，请确认它已经启动。",
            addition: resp.error
          }
        });
        return;
      }

      var statusCode = resp.response ? resp.response.statusCode : 0;
      if (statusCode < 200 || statusCode >= 300 || !resp.data || !resp.data.ok) {
        var message = resp.data && resp.data.message ? resp.data.message : "本地辅助程序写入失败。";
        complete(query, completion, {
          error: {
            type: "api",
            message: message,
            addition: resp.data
          }
        });
        return;
      }

      complete(query, completion, {
        result: {
          from: query.detectFrom || "en",
          to: query.detectTo || "zh-Hans",
          toParagraphs: ["已保存：" + text + "\n" + resp.data.path],
          raw: resp.data
        }
      });
    }
  });
}

function complete(query, completion, payload) {
  if (typeof query.onCompletion === "function") {
    query.onCompletion(payload);
    return;
  }
  completion(payload);
}
