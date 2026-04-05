#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");

function readWorkspaceFile(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
}

function exists(relativePath) {
  return fs.existsSync(path.join(repoRoot, relativePath));
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
    parseInt,
    parseFloat,
    isNaN,
    ...extras,
  };

  vm.createContext(context);
  vm.runInContext(code, context, { filename: relativePath });
  return context;
}

function testModuleStructure() {
  assert.equal(exists("mangadex/api/PaginationRules.js"), true, "api folder should include pagination module");
  assert.equal(exists("mangadex/core/ReaderRecovery.js"), true, "core folder should include render recovery module");
  assert.equal(exists("mangadex/reader/PageSlotModel.js"), true, "reader folder should include page slot model module");
  assert.equal(exists("mangadex/components/PageRefetchAction.qml"), true, "components folder should include refetch action component");
  assert.equal(exists("mangadex/utils/IconResolver.js"), true, "utils folder should include icon resolver module");
  assert.equal(exists("mangadex/utils/SearchMerge.js"), true, "utils folder should include search merge module");
}

function testMainAndPanelIntegration() {
  const mainQml = readWorkspaceFile("mangadex/Main.qml");
  const panelQml = readWorkspaceFile("mangadex/Panel.qml");

  assert.equal(mainQml.includes('import "api/PaginationRules.js" as PaginationRules'), true, "Main.qml should import pagination rules module");
  assert.equal(mainQml.includes('import "core/ReaderRecovery.js" as ReaderRecovery'), true, "Main.qml should import reader recovery module");
  assert.equal(mainQml.includes('import "reader/PageSlotModel.js" as PageSlotModel'), true, "Main.qml should import page slot model module");
  assert.equal(mainQml.includes('import "utils/SearchMerge.js" as SearchMerge'), true, "Main.qml should import search merge module");

  assert.equal(mainQml.includes("property int readerRenderEpoch"), true, "Main.qml should expose render epoch state");
  assert.equal(mainQml.includes("property var pageSlotStates"), true, "Main.qml should expose page slot map state");
  assert.equal(mainQml.includes("function requestPageRefetch("), true, "Main.qml should expose manual page refetch API");
  assert.equal(mainQml.includes("function replacePageEntryAtIndex("), true, "Main.qml should atomically replace a single page entry");
  assert.equal(mainQml.includes("replacePageEntryAtIndex(failedIndex, replacement"), true, "Main.qml should apply targeted recovery with atomic page replacement");
  assert.equal(mainQml.includes("bumpReaderRenderEpoch(\"page_model_changed\""), true, "Main.qml should trigger remount-safe render recovery on page model changes");

  assert.equal(panelQml.includes('import "utils/IconResolver.js" as IconResolver'), true, "Panel.qml should import icon resolver module");
  assert.equal(panelQml.includes('import "components" as Components'), true, "Panel.qml should import components module namespace");
  assert.equal(panelQml.includes('icon: resolveControlIcon("sliders", "adjustments-horizontal")'), true, "Panel.qml should resolve unsupported sliders icon through fallback mapping");
  assert.equal(panelQml.includes("Components.PageRefetchAction"), true, "Panel.qml should provide manual page refetch action");
  assert.equal(panelQml.includes("mainInstance.requestPageRefetch(modelData, pageItem.index, \"manual_refetch\")"), true, "Panel.qml should trigger manual per-page refetch");
  assert.equal(panelQml.includes("onRenderEpochChanged"), true, "Panel.qml should respond to render epoch remount events");
  assert.equal(panelQml.includes("scheduleAnchorRestore(\"reader_visible\""), true, "Panel.qml should restore viewport anchor on reader re-open");
  assert.equal(panelQml.includes("source: (pageItem.inViewport || pageItem.keepLoaded) ? pageItem.imageSource : \"\""), true, "Panel.qml should avoid duplicate stacked sources by binding one source per page slot");
}

function testSmokeFlowContracts() {
  const mainQml = readWorkspaceFile("mangadex/Main.qml");
  const panelQml = readWorkspaceFile("mangadex/Panel.qml");

  // Task 6.1: close/reopen continuity contracts.
  assert.equal(panelQml.includes("function closePanel()"), true, "Panel should expose close handler");
  assert.equal(panelQml.includes("Keys.onEscapePressed: { closePanel(); }"), true, "Panel should support keyboard close");
  assert.equal(panelQml.includes("onVisibleChanged:"), true, "Reader scroll should react to visible transitions");
  assert.equal(panelQml.includes("mainInstance.bumpReaderRenderEpoch(\"panel_open\""), true, "Panel open should trigger controlled render remount");
  assert.equal(panelQml.includes("scheduleAnchorRestore(\"reader_visible\""), true, "Panel open should restore reader anchor");

  // Task 6.2: manual refetch and non-overlap contracts.
  assert.equal(mainQml.includes("function requestPageRefetch("), true, "Main should expose manual refetch API");
  assert.equal(mainQml.includes("attemptTargetedPageRecovery("), true, "Main should perform targeted retry first");
  assert.equal(mainQml.includes("replacePageEntryAtIndex("), true, "Main should replace one page slot atomically");
  assert.equal(panelQml.includes("visible: pageItem.slotRecoverable"), true, "Panel should show refetch affordance only for recoverable slot states");
  assert.equal(panelQml.includes("mainInstance.requestPageRefetch(modelData, pageItem.index, \"manual_refetch\")"), true, "Panel refetch action should target a single page index");
}

function testSearchMergeAndPaginationHelpers() {
  const searchMerge = loadScript("mangadex/utils/SearchMerge.js");
  const pagination = loadScript("mangadex/api/PaginationRules.js");

  const merged = searchMerge.mergeByMangaId(
    [{ id: "a" }, { id: "b" }],
    [{ id: "b" }, { id: "c" }, { id: "a" }, { id: "d" }],
  );

  assert.equal(Array.isArray(merged.merged), true, "merge result should include merged list");
  assert.deepEqual(Array.from(merged.merged, (item) => item.id), ["a", "b", "c", "d"], "merge should preserve first-seen ordering while deduping ids");
  assert.equal(merged.dedupedCount, 2, "merge should report deduped count");
  assert.equal(merged.appendedCount, 2, "merge should report appended count");

  assert.equal(pagination.clampLimit(999, 20), 100, "limit should clamp to MangaDex max page size bound");
  assert.equal(pagination.clampOffset(-40), 0, "offset should clamp to zero lower bound");
  assert.equal(pagination.computeNextOffset(20, 20), 40, "next offset should increment by incoming count");
  assert.equal(pagination.hasMoreResults(20, 20, 40), true, "hasMore should remain true at full page responses");
}

function testIconResolverAndSlotModelHelpers() {
  const iconResolver = loadScript("mangadex/utils/IconResolver.js");
  const slotModel = loadScript("mangadex/reader/PageSlotModel.js");
  const recovery = loadScript("mangadex/core/ReaderRecovery.js");

  assert.equal(iconResolver.resolveIcon("sliders", "settings"), "adjustments-horizontal", "sliders icon should map to adjustments-horizontal");
  assert.equal(iconResolver.resolveIcon("non-existent-icon", "settings"), "settings", "unknown icons should fallback deterministically");

  const hydrated = slotModel.hydrateForEntries({}, "chapter-1", [
    { pageIdentity: "p1", source: "url-1" },
    { pageIdentity: "p2", source: "url-2" },
  ]);

  const key = slotModel.buildSlotKey("chapter-1", "p1", 0);
  assert.equal(hydrated[key].status, "loading", "slot hydration should default to loading status");

  const withError = slotModel.setSlotState(hydrated, key, { status: "error", failureCount: 1, lastError: "boom" });
  const recovered = slotModel.getSlotState(withError, key);
  assert.equal(recovered.status, "error", "slot state updates should persist status");
  assert.equal(recovered.failureCount, 1, "slot state updates should persist failure count");

  assert.equal(recovery.nextRenderEpoch(2), 3, "render epoch helper should increment epochs");
  assert.equal(recovery.shouldRemountForReason("panel_open"), true, "panel_open should trigger remount policy");
}

function main() {
  testModuleStructure();
  testMainAndPanelIntegration();
  testSearchMergeAndPaginationHelpers();
  testIconResolverAndSlotModelHelpers();
  testSmokeFlowContracts();
  console.log("Verification passed: structure split, icon fallback, refetch controls, and dedup helpers are wired.");
}

main();
