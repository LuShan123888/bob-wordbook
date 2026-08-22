const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const pluginSource = fs.readFileSync(path.join(__dirname, "..", "src", "main.js"), "utf8");

function loadPlugin(http, options = {}) {
  const context = {
    $http: http,
    $option: {
      provider: "aihubmix",
      apiKey: "test-key",
      model: "gpt-4o-mini",
      aiHubMixReasoningEffort: "auto",
      codexModel: "gpt-5.6-terra",
      codexReasoningEffort: "low",
      codexServiceTier: "standard",
      systemPrompt: "",
      outputPath: "~/Downloads/bob-wordbook.jsonl",
      ...options,
    },
  };
  vm.createContext(context);
  vm.runInContext(pluginSource, context);
  return context;
}

function successChunks(...contents) {
  return [
    ...contents.map(
      (content) => `data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`,
    ),
    "data: [DONE]\n\n",
  ];
}

function completeStream(request, chunks, statusCode = 200) {
  for (const text of chunks) {
    request.streamHandler({ text });
  }
  request.handler({ response: { statusCode } });
}

function completeLocalCodexStream(request, data, statusCode = 200) {
  const events = [
    { type: "status", stage: "starting", message: "正在启动本地 Codex…" },
    { type: "status", stage: "generating", message: "本地 Codex 正在生成翻译…" },
  ];
  if (data.kind === "text") {
    const midpoint = Math.ceil(data.content.text.length / 2);
    events.push(
      { type: "delta", delta: data.content.text.slice(0, midpoint) },
      { type: "delta", delta: data.content.text.slice(midpoint) },
    );
  }
  events.push({ type: "result", data });
  const body = events.map((event) => `${JSON.stringify(event)}\n`).join("");
  completeStream(request, [body.slice(0, 23), body.slice(23)], statusCode);
}

function wordJSON(overrides = {}) {
  return JSON.stringify({
    word: "translation",
    phonetics: [
      { type: "us", value: "/trænzˈleɪʃən/" },
      { type: "uk", value: "trænzˈleɪʃən" },
    ],
    parts: [{ part: "n.", means: ["翻译", "译文"] }],
    collocations: [{ text: "Chinese translation", meaning: "中文译文" }],
    examples: [
      {
        text: "Please send me the Chinese translation.",
        translation: "请把中文译文发给我。",
      },
    ],
    ...overrides,
  });
}

test("translate streams AIHubMix output and persists the completed English result", () => {
  let aiRequest;
  let helperRequest;
  let completion;
  const streamResults = [];
  const plugin = loadPlugin({
    streamRequest: (request) => {
      aiRequest = request;
      const chunks = successChunks("## 释义\n", "小菜一碟");
      completeStream(request, [chunks[0].slice(0, 17), chunks[0].slice(17), ...chunks.slice(1)]);
    },
    request: (request) => {
      helperRequest = request;
      request.handler({
        data: { ok: true, path: "/Users/test/Downloads/bob-wordbook.jsonl" },
        response: { statusCode: 201 },
      });
    },
  });

  plugin.translate(
    {
      text: "processed text",
      originalText: "piece of cake",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onStream: (value) => streamResults.push(value),
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(aiRequest.url, "https://aihubmix.com/v1/chat/completions");
  assert.equal(aiRequest.header.Authorization, "Bearer test-key");
  assert.equal(aiRequest.body.model, "gpt-4o-mini");
  assert.equal(aiRequest.body.messages[1].content, "piece of cake");
  assert.equal(aiRequest.body.stream, true);
  assert.equal(Object.prototype.hasOwnProperty.call(aiRequest.body, "reasoning_effort"), false);
  assert.equal(streamResults.at(-1).toParagraphs[0], "释义\n小菜一碟");

  assert.equal(helperRequest.url, "http://127.0.0.1:19820/v3/entries");
  assert.deepEqual(JSON.parse(JSON.stringify(helperRequest.body)), {
    text: "piece of cake",
    kind: "text",
    content: { text: "释义\n小菜一碟" },
    source_language: "en",
    target_language: "zh-Hans",
    provider: "aihubmix",
    model: "gpt-4o-mini",
    path: "~/Downloads/bob-wordbook.jsonl",
  });
  assert.equal(completion.result.toParagraphs[0], "释义\n小菜一碟");
  assert.match(completion.result.toParagraphs[1], /已保存到单词本/);
  assert.equal(completion.result.raw.saved, true);
});

test("translate sends an explicitly selected AIHubMix reasoning effort", () => {
  let aiRequest;
  const plugin = loadPlugin(
    {
      streamRequest: (request) => {
        aiRequest = request;
        completeStream(request, successChunks("结果"));
      },
      request: (request) => {
        request.handler({
          data: { ok: true, path: "/tmp/wordbook.jsonl" },
          response: { statusCode: 201 },
        });
      },
    },
    { aiHubMixReasoningEffort: "minimal" },
  );

  plugin.translate(
    {
      text: "take care",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: () => {},
    },
    undefined,
  );

  assert.equal(aiRequest.body.reasoning_effort, "minimal");
});

test("translate expands Bob prompt variables in a custom system prompt", () => {
  let aiRequest;
  const plugin = loadPlugin(
    {
      streamRequest: (request) => {
        aiRequest = request;
        completeStream(request, successChunks("结果"));
      },
      request: (request) => {
        request.handler({
          data: { ok: true, path: "/tmp/wordbook.jsonl" },
          response: { statusCode: 201 },
        });
      },
    },
    { systemPrompt: "分析 $query.text，并使用 $query.detectToLang 回答。" },
  );

  plugin.translate(
    {
      text: "take care",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: () => {},
    },
    undefined,
  );

  assert.equal(aiRequest.body.messages[0].content, "分析 take care，并使用 简体中文 回答。");
});

test("translate handles Chinese input without persisting it", () => {
  let helperCalled = false;
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks("How are you?")),
    request: () => {
      helperCalled = true;
    },
  });

  plugin.translate(
    {
      text: "你好吗？",
      detectFrom: "zh-Hans",
      detectTo: "en",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(helperCalled, false);
  assert.deepEqual(Array.from(completion.result.toParagraphs), ["How are you?"]);
  assert.equal(completion.result.raw.saved, false);
});

test("translate does not persist mixed Chinese and English input", () => {
  let helperCalled = false;
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks("分析结果")),
    request: () => {
      helperCalled = true;
    },
  });

  plugin.translate(
    {
      text: "hello 你好",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(helperCalled, false);
  assert.equal(completion.result.raw.saved, false);
});

test("translate rejects missing AIHubMix configuration before making requests", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin(
    {
      streamRequest: () => {
        called = true;
      },
      request: () => {
        called = true;
      },
    },
    { apiKey: "" },
  );

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

  assert.equal(called, false);
  assert.equal(completion.error.type, "secretKey");
});

test("translate rejects an invalid AIHubMix reasoning effort before making requests", () => {
  let called = false;
  let completion;
  const plugin = loadPlugin(
    {
      streamRequest: () => {
        called = true;
      },
      request: () => {
        called = true;
      },
    },
    { aiHubMixReasoningEffort: "max" },
  );

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

  assert.equal(called, false);
  assert.equal(completion.error.type, "param");
  assert.match(completion.error.message, /AIHubMix 思考深度/);
});

test("translate returns an API error without persisting", () => {
  let helperCalled = false;
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, [], 401),
    request: () => {
      helperCalled = true;
    },
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

  assert.equal(helperCalled, false);
  assert.equal(completion.error.type, "secretKey");
  assert.match(completion.error.message, /HTTP 401/);
});

test("translate rejects a truncated stream instead of saving partial output", () => {
  let helperCalled = false;
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks("partial").slice(0, 1)),
    request: () => {
      helperCalled = true;
    },
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

  assert.equal(helperCalled, false);
  assert.equal(completion.error.type, "api");
  assert.match(completion.error.message, /未正常完成/);
});

test("translate keeps the result visible when the helper cannot be reached", () => {
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks(wordJSON({ word: "hello" }))),
    request: (request) => {
      request.handler({ error: { message: "connection refused" } });
    },
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

  assert.equal(completion.error, undefined);
  assert.equal(completion.result.toDict.word, "hello");
  assert.match(completion.result.toParagraphs[0], /保存失败/);
  assert.match(completion.result.toParagraphs[0], /无法连接/);
  assert.equal(completion.result.raw.saved, false);
});

test("translate exposes a helper validation error instead of claiming success", () => {
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks(wordJSON({ word: "hello" }))),
    request: (request) => {
      request.handler({
        data: { ok: false, message: "path must point to a .jsonl file" },
        response: { statusCode: 400 },
      });
    },
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

  assert.match(completion.result.toParagraphs[0], /path must point to a \.jsonl file/);
  assert.equal(completion.result.raw.saved, false);
});

test("translate converts common Markdown markers to Bob-friendly plain text", () => {
  let completion;
  let persistedResult;
  const markdown = [
    "**translation** /trænzˈleɪʃən/  ",
    "n. 翻译；译文",
    "",
    "- Please send me the Chinese translation.  ",
    "  请把中文译文发给我。",
  ].join("\n");
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks(markdown)),
    request: (request) => {
      persistedResult = request.body.content.text;
      request.handler({
        data: { ok: true, path: "/tmp/wordbook.jsonl" },
        response: { statusCode: 201 },
      });
    },
  });

  plugin.translate(
    {
      text: "translation example",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  const expected = [
    "translation /trænzˈleɪʃən/",
    "n. 翻译；译文",
    "",
    "• Please send me the Chinese translation.",
    "  请把中文译文发给我。",
  ].join("\n");
  assert.equal(completion.result.toParagraphs[0], expected);
  assert.equal(persistedResult, expected);
});

test("translate identifies an outdated helper from its v3 404 response", () => {
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks(wordJSON({ word: "hello" }))),
    request: (request) => {
      request.handler({
        data: "404 page not found",
        response: { statusCode: 404 },
      });
    },
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

  assert.match(completion.result.toParagraphs[0], /helper 版本过旧/);
  assert.match(completion.result.toParagraphs[0], /3\.1\.0/);
});

test("translate renders a single English word with Bob's native dictionary result", () => {
  let aiRequest;
  let helperRequest;
  let completion;
  const streamResults = [];
  const plugin = loadPlugin({
    streamRequest: (request) => {
      aiRequest = request;
      completeStream(request, successChunks(wordJSON()));
    },
    request: (request) => {
      helperRequest = request;
      request.handler({
        data: { ok: true, path: "/tmp/wordbook.jsonl" },
        response: { statusCode: 201 },
      });
    },
  });

  plugin.translate(
    {
      text: "translation",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onStream: (value) => streamResults.push(value),
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.match(aiRequest.body.messages[0].content, /只输出一个 JSON 对象/);
  assert.equal(streamResults.length, 0);
  assert.deepEqual(JSON.parse(JSON.stringify(completion.result.toDict)), {
    word: "translation",
    phonetics: [
      { type: "us", value: "trænzˈleɪʃən" },
      { type: "uk", value: "trænzˈleɪʃən" },
    ],
    parts: [{ part: "n.", means: ["翻译", "译文"] }],
    additions: [
      {
        name: "例句",
        value: "Please send me the Chinese translation.\n请把中文译文发给我。",
      },
    ],
  });
  assert.match(completion.result.toParagraphs[0], /已保存到单词本/);
  assert.doesNotMatch(completion.result.toParagraphs[0], /translation/);
  assert.deepEqual(JSON.parse(JSON.stringify(helperRequest.body.content)), {
    word: "translation",
    phonetics: [
      { type: "us", value: "trænzˈleɪʃən" },
      { type: "uk", value: "trænzˈleɪʃən" },
    ],
    parts: [{ part: "n.", means: ["翻译", "译文"] }],
    collocations: [{ text: "Chinese translation", meaning: "中文译文" }],
    examples: [
      {
        text: "Please send me the Chinese translation.",
        translation: "请把中文译文发给我。",
      },
    ],
  });
});

test("translate rejects malformed word data instead of persisting or displaying raw JSON", () => {
  let helperCalled = false;
  let completion;
  const plugin = loadPlugin({
    streamRequest: (request) => completeStream(request, successChunks('{"word":"hello"}')),
    request: () => {
      helperCalled = true;
    },
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

  assert.equal(helperCalled, false);
  assert.equal(completion.error.type, "api");
  assert.match(completion.error.message, /缺少核心释义/);
});

test("translate uses local Codex settings and persists the structured result", () => {
  const requests = [];
  let codexRequest;
  let completion;
  const streamResults = [];
  const plugin = loadPlugin(
    {
      streamRequest: (request) => {
        codexRequest = request;
        completeLocalCodexStream(request, {
          ok: true,
          kind: "text",
          content: { text: "含义：小菜一碟\n例句：It is a piece of cake." },
          model: "gpt-5.6-terra",
        });
      },
      request: (request) => {
        requests.push(request);
        request.handler({
          data: { ok: true, path: "/tmp/wordbook.jsonl" },
          response: { statusCode: 201 },
        });
      },
    },
    {
      provider: "local_codex",
      apiKey: "",
      codexModel: "gpt-5.6-terra",
      codexReasoningEffort: "medium",
      codexServiceTier: "fast",
    },
  );

  plugin.translate(
    {
      text: "piece of cake",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onStream: (value) => streamResults.push(value),
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(codexRequest.url, "http://127.0.0.1:19820/v1/codex/translate/stream");
  assert.deepEqual(JSON.parse(JSON.stringify(codexRequest.body)), {
    text: "piece of cake",
    kind: "text",
    system_prompt: plugin.buildSystemPrompt(
      { detectFrom: "en", detectTo: "zh-Hans" },
      "piece of cake",
      "",
      false,
    ),
    model: "gpt-5.6-terra",
    reasoning_effort: "medium",
    service_tier: "fast",
  });
  assert.equal(streamResults[0].toParagraphs[0], "正在连接本地 Codex…");
  assert.equal(streamResults.at(-1).toParagraphs[0], "含义：小菜一碟\n例句：It is a piece of cake.");
  assert.equal(requests[0].url, "http://127.0.0.1:19820/v3/entries");
  assert.equal(requests[0].body.provider, "local_codex");
  assert.equal(requests[0].body.model, "gpt-5.6-terra");
  assert.equal(completion.result.raw.provider, "local_codex");
  assert.equal(completion.result.raw.saved, true);
  assert.match(completion.result.toParagraphs[0], /小菜一碟/);
});

test("translate renders a local Codex word with Bob native dictionary fields", () => {
  let completion;
  const plugin = loadPlugin(
    {
      streamRequest: (request) => {
        completeLocalCodexStream(request, {
          ok: true,
          kind: "word",
          content: JSON.parse(wordJSON()),
          model: "gpt-5.6-terra",
        });
      },
      request: (request) => {
        request.handler({
          data: { ok: true, path: "/tmp/wordbook.jsonl" },
          response: { statusCode: 201 },
        });
      },
    },
    { provider: "local_codex", apiKey: "" },
  );

  plugin.translate(
    {
      text: "translation",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(completion.result.toDict.word, "translation");
  assert.deepEqual(Array.from(completion.result.toDict.parts[0].means), ["翻译", "译文"]);
  assert.equal(completion.result.raw.model, "gpt-5.6-terra");
});

test("translate reports an outdated helper when the local Codex stream endpoint is missing", () => {
  let completion;
  const plugin = loadPlugin(
    {
      streamRequest: (request) => {
        request.streamHandler({ text: "404 page not found\n" });
        request.handler({ response: { statusCode: 404 } });
      },
      request: () => assert.fail("persistence must not run"),
    },
    { provider: "local_codex", apiKey: "" },
  );

  plugin.translate(
    {
      text: "piece of cake",
      detectFrom: "en",
      detectTo: "zh-Hans",
      onCompletion: (value) => {
        completion = value;
      },
    },
    undefined,
  );

  assert.equal(completion.error.type, "api");
  assert.match(completion.error.message, /helper 版本过旧/);
});

test("pluginValidate checks local Codex through the helper", () => {
  let validationRequest;
  let validationResult;
  const plugin = loadPlugin(
    {
      streamRequest: () => {},
      request: (request) => {
        validationRequest = request;
        request.handler({
          response: { statusCode: 200 },
          data: { ok: true, available: true, authenticated: true, version: "codex-cli 0.149.0" },
        });
      },
    },
    { provider: "local_codex", apiKey: "" },
  );

  plugin.pluginValidate((value) => {
    validationResult = value;
  });

  assert.equal(validationRequest.url, "http://127.0.0.1:19820/v1/codex/status");
  assert.equal(validationRequest.header["X-Bob-Wordbook-Client"], "bob-plugin");
  assert.equal(validationResult.result, true);
});

test("pluginValidate checks the configured key against AIHubMix", () => {
  let validationRequest;
  let validationResult;
  const plugin = loadPlugin({
    streamRequest: () => {},
    request: (request) => {
      validationRequest = request;
      request.handler({ response: { statusCode: 200 }, data: { object: "list", data: [] } });
    },
  });

  plugin.pluginValidate((value) => {
    validationResult = value;
  });

  assert.equal(validationRequest.method, "GET");
  assert.equal(validationRequest.url, "https://aihubmix.com/v1/models");
  assert.equal(validationRequest.header.Authorization, "Bearer test-key");
  assert.equal(validationResult.result, true);
});
