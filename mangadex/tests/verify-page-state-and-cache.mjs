#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");

function readWorkspaceFile(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
}

function testMainQmlContracts() {
  const mainQml = readWorkspaceFile("mangadex/Main.qml");

  assert.equal(mainQml.includes("property var readerViewportAnchor"), true, "Main.qml should define reader viewport anchor state");
  assert.equal(mainQml.includes("function updateReaderViewportAnchor("), true, "Main.qml should expose anchor update API");
  assert.equal(mainQml.includes("function getReaderViewportAnchor("), true, "Main.qml should expose anchor query API");

  assert.equal(mainQml.includes("property var pageImageCacheEntries"), true, "Main.qml should define page cache entry state");
  assert.equal(mainQml.includes("property var pageImageCacheLru"), true, "Main.qml should define page cache LRU state");
  assert.equal(mainQml.includes("property int pageImageCacheRevision"), true, "Main.qml should expose cache revision state");

  assert.equal(mainQml.includes("function buildPageCacheKeyForValues("), true, "Main.qml should build deterministic page cache keys");
  assert.equal(mainQml.includes("function registerPageImageReady("), true, "Main.qml should register successful image loads in cache");
  assert.equal(mainQml.includes("function invalidatePageCacheEntry("), true, "Main.qml should invalidate corrupt cache entries");
  assert.equal(mainQml.includes("function attemptTargetedPageRecovery("), true, "Main.qml should support targeted page recovery");

  assert.equal(mainQml.includes("chapter.image_failure.targeted_recovery.start"), true, "Main.qml should emit targeted recovery diagnostics");
  assert.equal(mainQml.includes("readerAnchor: readerViewportAnchor"), true, "Main.qml should persist reader anchor in state cache");
}

function testPanelQmlContracts() {
  const panelQml = readWorkspaceFile("mangadex/Panel.qml");

  assert.equal(panelQml.includes("function captureReaderAnchor("), true, "Panel.qml should implement anchor capture");
  assert.equal(panelQml.includes("function scheduleAnchorRestore("), true, "Panel.qml should implement anchor restore scheduling");
  assert.equal(panelQml.includes("function tryRestoreReaderAnchor("), true, "Panel.qml should implement anchor restoration");

  assert.equal(panelQml.includes("captureReaderAnchor(\"before_utility_toggle\""), true, "Panel.qml should capture anchor before utility toggle");
  assert.equal(panelQml.includes("captureReaderAnchor(\"before_controls_toggle\""), true, "Panel.qml should capture anchor before controls toggle");

  assert.equal(panelQml.includes("source: (pageItem.inViewport || pageItem.keepLoaded) ? pageItem.imageSource : \"\""), true, "Panel.qml should keep cached pages loaded outside viewport");
  assert.equal(panelQml.includes("cache: true"), true, "Panel.qml should enable image cache usage");

  assert.equal(panelQml.includes("mainInstance.touchPageCacheEntry"), true, "Panel.qml should touch cache entries on viewport access");
  assert.equal(panelQml.includes("mainInstance.registerPageImageReady"), true, "Panel.qml should register successful page image loads");
  assert.equal(panelQml.includes("mainInstance.invalidatePageCacheEntry"), true, "Panel.qml should invalidate cache entries on image errors");
}

function testReaderSmokeContracts() {
  const mainQml = readWorkspaceFile("mangadex/Main.qml");
  const panelQml = readWorkspaceFile("mangadex/Panel.qml");

  assert.equal(mainQml.includes("function loadChapterPages("), true, "Main.qml should expose chapter loading flow");
  assert.equal(mainQml.includes("loadChapterPages(chapter.id);"), true, "Main.qml should trigger chapter loading from chapter selection");
  assert.equal(mainQml.includes("loadChapterPages(currentChapter.id);"), true, "Main.qml should support chapter reload for active chapter state");
  assert.equal(mainQml.includes("onQualityModeChanged:"), true, "Main.qml should react to quality changes");
  assert.equal(mainQml.includes("pageUrls = buildRuntimePageEntries(atHomeMetadata, qualityMode);"), true, "Main.qml should rebuild page entries for quality changes");

  assert.equal(panelQml.includes("function closePanel()"), true, "Panel.qml should provide panel close handler");
  assert.equal(panelQml.includes("pluginApi.closePanel(screen);"), true, "Panel.qml should close via plugin API on current screen");
  assert.equal(panelQml.includes("Keys.onEscapePressed: { closePanel(); }"), true, "Panel.qml should close on escape key");
  assert.equal(panelQml.includes("onClicked: root.closePanel()"), true, "Panel.qml should expose close action in UI controls");
}

function testManifestDefaults() {
  const manifestJson = JSON.parse(readWorkspaceFile("mangadex/manifest.json"));
  const readerDefaults = manifestJson?.metadata?.defaultSettings?.reader || {};

  assert.equal(typeof readerDefaults.pageCacheMaxEntries, "number", "Manifest should provide pageCacheMaxEntries default");
  assert.equal(typeof readerDefaults.pageCachePerChapterMaxEntries, "number", "Manifest should provide pageCachePerChapterMaxEntries default");
  assert.equal(readerDefaults.pageCacheMaxEntries >= readerDefaults.pageCachePerChapterMaxEntries, true, "Global cache max should be >= per-chapter max");
}

function main() {
  testMainQmlContracts();
  testPanelQmlContracts();
  testReaderSmokeContracts();
  testManifestDefaults();
  console.log("Verification passed: reader page-state, image-cache, and smoke-check contracts are present.");
}

main();
