# MangaDex Reader (Noctalia Plugin)

MangaDex Reader adds a side-panel manga reading workflow to Noctalia:

- Search manga from MangaDex
- Browse chapter feeds
- Read chapters in-panel (`data-saver` or `data` quality)
- Optional account sync (followed feed, read markers, reading status)

Panel behavior: the reader panel opens detached from the bar (clipper-style), not attached to the widget anchor.

## Setup

1. Enable the plugin in Noctalia settings.
2. Add the bar widget to your bar section.
3. Open plugin settings and configure MangaDex personal client credentials:
   - Client ID (`personal-client-...`)
   - Client Secret
   - MangaDex username or email
4. Authenticate once using either:
   - `Login Now` in plugin settings (with one-time password), or
   - `Login` in the panel header (password field).
5. For subsequent launches, use `Use Saved Session` if refresh-session persistence is enabled.

Password is never persisted by this plugin. If session persistence is enabled, only refresh-session token data is stored.

## Reader Flow

1. Search a manga title.
2. Select a manga to load its chapter feed.
3. Select a chapter to resolve page URLs from MangaDex At-Home.
4. Read in-panel and switch quality mode as needed.

## Recovery And Refetch

- The reader keeps chapter visibility stable across panel reopen and layout changes using viewport-anchor restore plus render remount recovery.
- Each page is tracked with slot state (`loading`, `ready`, `error`, `stale`) so failures are isolated to a single page.
- Failed pages expose a manual `Refetch this page` action, which refreshes only the targeted page before escalating to chapter-wide reload.
- Search `Load more results` deduplicates manga by MangaDex UUID and appends only unseen entries in first-seen order.

## Module Layout

To reduce monolithic runtime logic, MangaDex internals are grouped by responsibility:

- `mangadex/api/` request and pagination helpers
- `mangadex/core/` reader recovery coordination helpers
- `mangadex/reader/` page-slot state model helpers
- `mangadex/components/` reusable QML pieces (for example refetch action)
- `mangadex/utils/` generic icon and search merge utilities

## Authenticated Features

When logged in:

- `Followed Feed` loads `/user/follows/manga/feed`
- `Mark Read` syncs chapter read markers
- Reading status can be updated from the chapter header controls

If auth expires or is missing, public browsing/reading still works and account-sync actions are blocked with a message.

## Notes And Constraints

- The plugin intentionally does not send auth headers to image hosts (`uploads.mangadex.org`, `*.mangadex.network`).
- MangaDex rate limiting is respected with cooldown handling after `429` responses.
- Collection requests use bounded pagination.
- If chapter image delivery fails, the plugin refreshes At-Home metadata and can auto-fallback between `data` and `data-saver`.

## Compliance Reminder

Use of MangaDex services is subject to MangaDex API acceptable-use rules and policies. If you expose reader experiences, credit MangaDex and scanlation groups appropriately.