var MAX_RENDER_EPOCH = 100;

function computeTransitionStart(currentState, reason, settleMs) {
    var isNew = !currentState.transitionActive;

    return {
        transitionActive: true,
        transitionToken: isNew ? currentState.transitionToken + 1 : currentState.transitionToken,
        suppressedCount: isNew ? 0 : currentState.suppressedCount,
        pendingRemount: currentState.pendingRemount,
        lastReason: reason,
        shouldRestartTimer: true,
        timerInterval: settleMs
    };
}

function computeTransitionClear(emitSettleEpoch, currentSettleEpoch) {
    return {
        transitionActive: false,
        pendingRemount: false,
        suppressedCount: 0,
        lastReason: "",
        shouldStopTimer: true,
        settleEpoch: emitSettleEpoch ? currentSettleEpoch + 1 : currentSettleEpoch,
        emittedSettle: emitSettleEpoch
    };
}

function computeTransitionSettle(currentState, triggerReason) {
    if (!currentState.transitionActive && !currentState.pendingRemount) {
        return {
            changed: false,
            shouldBumpEpoch: false,
            cleared: null
        };
    }

    var cleared = computeTransitionClear(true, currentState.settleEpoch);

    return {
        changed: true,
        shouldBumpEpoch: currentState.pendingRemount,
        bumpReason: "layout_settled",
        cleared: cleared,
        logContext: {
            transitionToken: currentState.transitionToken,
            trigger: String(triggerReason || "timer"),
            suppressedCount: currentState.suppressedCount,
            pendingRemount: currentState.pendingRemount,
            lastReason: currentState.lastReason
        }
    };
}

function computeRenderEpochBump(currentEpoch) {
    if (currentEpoch > MAX_RENDER_EPOCH) {
        return {
            epoch: 0,
            capped: true
        };
    }

    return {
        epoch: currentEpoch + 1,
        capped: false
    };
}

function shouldResetOnReopen(chapterLoadState, pageUrlsLength) {
    return chapterLoadState === "success" && pageUrlsLength > 0;
}
