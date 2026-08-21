const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const pluginSource = fs.readFileSync(path.join(__dirname, "..", "src", "main.js"), "utf8");

function loadPlugin(httpHandler, outputPath = "~/Downloads/bob-wordbook.jsonl") {
  const context = {
    $http: { request: httpHandler },
    $option: { outputPath },
  };
  vm.createContext(context);
  vm.runInContext(pluginSource, context);
  return context;
}

test("translate sends original text and returns the stored path", () => {
  let request;
  let completion;
  const plugin = loadPlugin((value) => {
    request = value;
    value.handler({
      data: { ok: true, path: "/Users/test/Downloads/bob-wordbook.jsonl" },
      response: { statusCode: 201 },
    });
  });

  plugin.translate(
    {
      text: "processed text",
      originalText: "piece of cake",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(request.method, "POST");
  assert.equal(request.url, "http://127.0.0.1:19820/v1/entries");
  assert.equal(request.body.text, "piece of cake");
  assert.equal(request.body.path, "~/Downloads/bob-wordbook.jsonl");
  assert.equal(
    completion.result.toParagraphs[0],
    "已保存：piece of cake\n/Users/test/Downloads/bob-wordbook.jsonl",
  );
});

test("translate accepts an English sentence", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin((request) => {
    called = true;
    request.handler({
      data: { ok: true, path: "/Users/test/Downloads/bob-wordbook.jsonl" },
      response: { statusCode: 201 },
    });
  });

  plugin.translate(
    {
      text: "Learning English takes time.",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(called, true);
  assert.equal(completion.error, undefined);
});

test("translate reports a helper connection failure", () => {
  let completion;
  const plugin = loadPlugin((request) => {
    request.handler({ error: { message: "connection refused" } });
  });

  plugin.translate(
    {
      text: "hello",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(completion.error.type, "network");
  assert.match(completion.error.message, /辅助程序/);
});

test("translate rejects empty text without calling the helper", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin(() => {
    called = true;
  });

  plugin.translate(
    {
      text: "   ",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(called, false);
  assert.equal(completion.error.type, "param");
});

test("translate rejects non-English input without calling the helper", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin(() => {
    called = true;
  });

  plugin.translate(
    {
      text: "你好",
      detectFrom: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(called, false);
  assert.equal(completion.error.type, "unsupportedLanguage");
});

test("translate rejects input without an English detection result", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin(() => {
    called = true;
  });

  plugin.translate(
    {
      text: "你好",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(called, false);
  assert.equal(completion.error.type, "unsupportedLanguage");
});

test("translate rejects mixed Chinese and English input", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin(() => {
    called = true;
  });

  plugin.translate(
    {
      text: "hello 你好",
      detectFrom: "en",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(called, false);
  assert.equal(completion.error.type, "unsupportedLanguage");
});
