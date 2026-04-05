#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");

function readWorkspaceFile(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
}

function createDiagnosticsCollector() {
  const events = [];
  const push = (level, event, context, message) => {
    events.push({
      level,
      event,
      context: context || {},
      message: message || "",
    });
  };

  return {
    events,
    diagnostics: {
      debug: (event, context, message) => push("debug", event, context, message),
      info: (event, context, message) => push("info", event, context, message),
      warn: (event, context, message) => push("warn", event, context, message),
      error: (event, context, message) => push("error", event, context, message),
      childContext: (base, extra) => ({ ...(base || {}), ...(extra || {}) }),
    },
  };
}

function createXhrHarness() {
  const queue = [];
  const requests = [];

  class StubXMLHttpRequest {
    constructor() {
      this.readyState = 0;
      this.status = 0;
      this.responseText = "";
      this.timeout = 0;
      this.onreadystatechange = null;
      this.onerror = null;
      this.ontimeout = null;
      this._requestHeaders = {};
      this._responseHeaders = {};
      this.method = "GET";
      this.url = "";
      this.body = null;
    }

    open(method, url) {
      this.method = String(method || "GET").toUpperCase();
      this.url = String(url || "");
    }

    setRequestHeader(name, value) {
      this._requestHeaders[String(name).toLowerCase()] = String(value);
    }

    getResponseHeader(name) {
      return this._responseHeaders[String(name).toLowerCase()] || "";
    }

    send(body) {
      this.body = body;
      requests.push({
        method: this.method,
        url: this.url,
        body: this.body,
        headers: { ...this._requestHeaders },
      });

      const scenario = queue.shift();
      if (!scenario) {
        throw new Error("No queued XHR scenario for request " + this.method + " " + this.url);
      }

      if (scenario.type === "error") {
        if (typeof this.onerror === "function") {
          this.onerror();
        }
        return;
      }

      if (scenario.type === "timeout") {
        if (typeof this.ontimeout === "function") {
          this.ontimeout();
        }
        return;
      }

      this.status = Number(scenario.status || 0);
      this._responseHeaders = {};
      for (const [k, v] of Object.entries(scenario.headers || {})) {
        this._responseHeaders[String(k).toLowerCase()] = String(v);
      }

      if (Object.prototype.hasOwnProperty.call(scenario, "responseText")) {
        this.responseText = String(scenario.responseText || "");
      } else if (Object.prototype.hasOwnProperty.call(scenario, "body")) {
        this.responseText = JSON.stringify(scenario.body);
      } else {
        this.responseText = "";
      }

      this.readyState = 4;
      if (typeof this.onreadystatechange === "function") {
        this.onreadystatechange();
      }
    }
  }

  return {
    queue,
    requests,
    XMLHttpRequest: StubXMLHttpRequest,
  };
}

function loadScript(relativePath, extras = {}) {
  const code = readWorkspaceFile(relativePath);
  const context = {
    console,
    Date,
    Math,
    JSON,
    String,
    Number,
    Boolean,
    Object,
    Array,
    RegExp,
    Error,
    encodeURIComponent,
    decodeURIComponent,
    parseFloat,
    parseInt,
    isNaN,
    ...extras,
  };

  vm.createContext(context);
  vm.runInContext(code, context, { filename: relativePath });
  return context;
}

function callAsync(invoke) {
  return new Promise((resolve, reject) => {
    let settled = false;
    invoke(
      (value) => {
        if (!settled) {
          settled = true;
          resolve(value);
        }
      },
      (err) => {
        if (!settled) {
          settled = true;
          reject(err);
        }
      },
    );
  });
}

async function testMangaDexApi() {
  const diagnosticsCollector = createDiagnosticsCollector();
  const xhrHarness = createXhrHarness();

  const api = loadScript("mangadex/MangaDexApi.js", {
    XMLHttpRequest: xhrHarness.XMLHttpRequest,
  });

  api.setDiagnostics(diagnosticsCollector.diagnostics);

  // 1) Retry behavior on 429 and eventual success.
  xhrHarness.queue.push(
    {
      status: 429,
      body: { errors: [{ detail: "Rate limited" }] },
      headers: { "Retry-After": "1", "X-RateLimit-Remaining": "0" },
    },
    {
      status: 200,
      body: { data: [{ id: "m1" }] },
    },
  );

  const searchResult = await callAsync((resolve, reject) =>
    api.searchManga(
      "test",
      0,
      20,
      {},
      "",
      resolve,
      reject,
      {
        maxRetries: 2,
        backoffBaseMs: 1,
        pacingMs: 0,
      },
    ),
  );

  assert.equal(Array.isArray(searchResult.data), true, "search retry flow should eventually return data");
  assert.equal(xhrHarness.requests.length, 2, "search retry should issue two requests");
  assert.equal(
    diagnosticsCollector.events.some((e) => e.event === "api.request.retry"),
    true,
    "search retry should emit api.request.retry diagnostics",
  );

  // 2) Retry-After parsing and error shape on terminal 429.
  xhrHarness.queue.push({
    status: 429,
    body: { errors: [{ detail: "Slow down" }] },
    headers: { "Retry-After": "120" },
  });

  let terminalError = null;
  try {
    await callAsync((resolve, reject) =>
      api.getMangaFeed(
        "manga-id",
        0,
        100,
        {},
        "",
        resolve,
        reject,
        {
          maxRetries: 0,
          pacingMs: 0,
        },
      ),
    );
  } catch (errorObj) {
    terminalError = errorObj;
  }

  assert.ok(terminalError, "terminal 429 request should return an error object");
  assert.equal(Number(terminalError.retryAfterSeconds || 0), 120, "Retry-After should be parsed to seconds");

  // 3) Request shaping limits for search/feed.
  xhrHarness.queue.push(
    { status: 200, body: { data: [] } },
    { status: 200, body: { data: [] } },
  );

  await callAsync((resolve, reject) =>
    api.searchManga("shape", -40, 999, {}, "", resolve, reject, { pacingMs: 0 }),
  );
  await callAsync((resolve, reject) =>
    api.getMangaFeed("shape-id", 99999, 999, {}, "", resolve, reject, { pacingMs: 0 }),
  );

  const searchReq = xhrHarness.requests[xhrHarness.requests.length - 2];
  const feedReq = xhrHarness.requests[xhrHarness.requests.length - 1];

  const searchUrl = new URL(searchReq.url);
  const feedUrl = new URL(feedReq.url);

  assert.equal(searchUrl.searchParams.get("limit"), "100", "search limit should be clamped to 100");
  assert.equal(searchUrl.searchParams.get("offset"), "0", "search offset should clamp to >= 0");
  assert.equal(feedUrl.searchParams.get("limit"), "500", "feed limit should be clamped to 500");
  assert.equal(feedUrl.searchParams.get("offset"), "10000", "feed offset should be clamped to max offset");

  // 4) Pacing diagnostics visible on consecutive rapid requests.
  xhrHarness.queue.push(
    { status: 200, body: { data: [] } },
    { status: 200, body: { data: [] } },
  );

  await callAsync((resolve, reject) =>
    api.searchManga("pace", 0, 20, {}, "", resolve, reject, { pacingMs: 400, maxRetries: 0 }),
  );
  await callAsync((resolve, reject) =>
    api.searchManga("pace", 20, 20, {}, "", resolve, reject, { pacingMs: 400, maxRetries: 0 }),
  );

  const pacingEvents = diagnosticsCollector.events.filter((e) => e.event === "api.request.delay");
  assert.equal(
    pacingEvents.some((e) => Number(e.context?.pacingDelayMs || 0) > 0),
    true,
    "rapid requests should produce pacing delay diagnostics",
  );
}

async function testAuthService() {
  const diagnosticsCollector = createDiagnosticsCollector();
  const xhrHarness = createXhrHarness();

  const auth = loadScript("mangadex/AuthService.js", {
    XMLHttpRequest: xhrHarness.XMLHttpRequest,
  });

  auth.setDiagnostics(diagnosticsCollector.diagnostics);

  xhrHarness.queue.push(
    { type: "error" },
    {
      status: 200,
      body: {
        access_token: "token-1",
        refresh_token: "refresh-1",
        expires_in: 600,
      },
    },
  );

  const tokenData = await callAsync((resolve, reject) =>
    auth.requestPasswordToken(
      "cid",
      "secret",
      "user",
      "pass",
      resolve,
      reject,
      {
        maxRetries: 1,
        backoffBaseMs: 1,
      },
    ),
  );

  assert.equal(tokenData.accessToken, "token-1", "auth retry path should eventually return token data");
  assert.equal(xhrHarness.requests.length, 2, "auth retry should issue two requests");
  assert.equal(
    diagnosticsCollector.events.some((e) => e.event === "auth.request.retry"),
    true,
    "auth retry should emit auth.request.retry diagnostics",
  );
}

function testReaderService() {
  const diagnosticsCollector = createDiagnosticsCollector();
  const reader = loadScript("mangadex/ReaderService.js");
  reader.setDiagnostics(diagnosticsCollector.diagnostics);

  const urls = reader.buildPageUrls(
    {
      baseUrl: "https://uploads.mangadex.network",
      chapter: {
        hash: "abc123",
        data: [],
        dataSaver: ["001.jpg", "002.jpg"],
      },
    },
    "data",
  );

  assert.equal(urls.length, 2, "reader should fallback to alternate quality array when requested quality is empty");
  assert.equal(urls[0].includes("/data-saver/abc123/001.jpg"), true, "reader fallback should use data-saver path");

  const invalid = reader.buildPageUrls(null, "data");
  assert.equal(invalid.length, 0, "reader should return empty array for invalid payload");
  assert.equal(
    diagnosticsCollector.events.some((e) => e.event === "reader_service.page_urls.invalid_payload"),
    true,
    "reader invalid payload should emit diagnostics",
  );
}

function testStaticQmlChecks() {
  const mainQml = readWorkspaceFile("mangadex/Main.qml");
  const panelQml = readWorkspaceFile("mangadex/Panel.qml");
  const settingsQml = readWorkspaceFile("mangadex/Settings.qml");
  const manifestJson = JSON.parse(readWorkspaceFile("mangadex/manifest.json"));

  assert.equal(mainQml.includes("chapterLoadToken"), true, "Main.qml should include chapter load token state");
  assert.equal(mainQml.includes("if (loadToken !== chapterLoadToken)"), true, "Main.qml should guard stale callbacks");
  assert.equal(mainQml.includes("chapterLoadState = \"success\""), true, "Main.qml should set success terminal state");
  assert.equal(mainQml.includes("chapterLoadState = \"error\""), true, "Main.qml should set error terminal state");

  assert.equal(panelQml.includes("pageRepeater.itemAt(i)"), true, "Panel.qml should activate pages through repeater item lookup");
  assert.equal(panelQml.includes("item.inViewport = nextVisible"), true, "Panel.qml should update inViewport on resolved delegates");

  assert.equal(settingsQml.includes("valueLoggingMode"), true, "Settings.qml should expose logging mode state");
  assert.equal(settingsQml.includes("pluginApi.pluginSettings.diagnostics.loggingMode"), true, "Settings.qml should persist diagnostics mode");

  assert.equal(manifestJson.metadata.defaultSettings.diagnostics.loggingMode, "normal", "Manifest should define diagnostics logging default");
  assert.equal(typeof manifestJson.metadata.defaultSettings.network.requestPacingMs, "number", "Manifest should define request pacing default");
  assert.equal(typeof manifestJson.metadata.defaultSettings.network.maxRetryAttempts, "number", "Manifest should define max retry attempts default");
  assert.equal(typeof manifestJson.metadata.defaultSettings.network.retryBaseDelayMs, "number", "Manifest should define retry base delay default");
}

async function main() {
  await testMangaDexApi();
  await testAuthService();
  testReaderService();
  testStaticQmlChecks();

  console.log("Verification passed: MangaDex loading/logging/rate-limit changes validated via mock harness.");
}

main().catch((error) => {
  console.error("Verification failed:", error && error.stack ? error.stack : error);
  process.exit(1);
});
