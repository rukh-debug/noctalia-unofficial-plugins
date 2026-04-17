.pragma library

function normaliseMalStatus(value) {
    var status = String(value || "").trim().toLowerCase()
    if (status === "plan_to_watch"
            || status === "watching"
            || status === "completed"
            || status === "on_hold"
            || status === "dropped") {
        return status
    }
    return ""
}

function _normaliseEpisodeCount(value) {
    var parsed = Number(value)
    if (!isFinite(parsed) || parsed <= 0)
        return 0
    return Math.floor(parsed)
}

function _normaliseUserAction(value) {
    var action = String(value || "").trim().toLowerCase()
    if (action === "play" || action === "pause" || action === "drop" || action === "complete")
        return action
    return ""
}

function resolveAnimeStatus(input) {
    var currentStatus = normaliseMalStatus(input && input.currentStatus)
    var watchedEpisodes = _normaliseEpisodeCount(input && input.watchedEpisodes)
    var totalEpisodes = _normaliseEpisodeCount(input && input.totalEpisodes)
    var userAction = _normaliseUserAction(input && input.userAction)

    if (totalEpisodes > 0 && watchedEpisodes > totalEpisodes)
        watchedEpisodes = totalEpisodes

    if (userAction === "complete") {
        if (totalEpisodes > 0)
            watchedEpisodes = totalEpisodes
        return {
            status: "completed",
            watchedEpisodes: watchedEpisodes
        }
    }

    if (userAction === "pause") {
        return {
            status: "on_hold",
            watchedEpisodes: watchedEpisodes
        }
    }

    if (userAction === "drop") {
        return {
            status: "dropped",
            watchedEpisodes: watchedEpisodes
        }
    }

    if (userAction === "play") {
        if (watchedEpisodes <= 0) {
            return {
                status: "plan_to_watch",
                watchedEpisodes: 0
            }
        }
        if (totalEpisodes > 0 && watchedEpisodes >= totalEpisodes) {
            return {
                status: "completed",
                watchedEpisodes: totalEpisodes
            }
        }
        return {
            status: "watching",
            watchedEpisodes: watchedEpisodes
        }
    }

    if (currentStatus === "on_hold" || currentStatus === "dropped") {
        return {
            status: currentStatus,
            watchedEpisodes: watchedEpisodes
        }
    }

    if (watchedEpisodes <= 0) {
        return {
            status: "plan_to_watch",
            watchedEpisodes: 0
        }
    }

    if (totalEpisodes > 0 && watchedEpisodes >= totalEpisodes) {
        return {
            status: "completed",
            watchedEpisodes: totalEpisodes
        }
    }

    if (currentStatus === "completed" && totalEpisodes <= 0) {
        return {
            status: "completed",
            watchedEpisodes: watchedEpisodes
        }
    }

    return {
        status: "watching",
        watchedEpisodes: watchedEpisodes
    }
}

function updateAnimeStatus(input) {
    return resolveAnimeStatus({
        watchedEpisodes: input && input.watchedEpisodes,
        totalEpisodes: input && input.totalEpisodes,
        userAction: input && input.userAction
    })
}

function buildMalPayload(animeId, status, watchedEpisodes) {
    var resolvedStatus = normaliseMalStatus(status)
    var resolvedWatchedEpisodes = _normaliseEpisodeCount(watchedEpisodes)

    if (!resolvedStatus)
        resolvedStatus = resolvedWatchedEpisodes > 0 ? "watching" : "plan_to_watch"
    if (resolvedStatus === "plan_to_watch")
        resolvedWatchedEpisodes = 0

    return {
        anime_id: String(animeId || ""),
        status: resolvedStatus,
        num_watched_episodes: resolvedWatchedEpisodes
    }
}
