function nextRenderEpoch(currentEpoch) {
    var numeric = Number(currentEpoch || 0);
    if (isNaN(numeric) || numeric < 0) {
        numeric = 0;
    }
    return Math.round(numeric) + 1;
}

function shouldRemountForReason(reason) {
    var normalized = String(reason || "").toLowerCase().trim();
    if (normalized === "") {
        return false;
    }

    return normalized === "panel_open"
        || normalized === "panel_reopen"
        || normalized === "page_model_changed"
        || normalized === "chapter_changed"
        || normalized === "reader_width_changed"
        || normalized === "reader_height_changed"
        || normalized === "manual_refetch"
        || normalized === "blank_view_recovery";
}

function normalizeRecoveryReason(reason) {
    var normalized = String(reason || "").toLowerCase().trim();
    return normalized === "" ? "layout_change" : normalized;
}
