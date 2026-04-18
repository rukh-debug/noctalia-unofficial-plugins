# AnimeReloaded

Anime plugin for Noctalia Shell. AniList metadata, AllAnime streams, AniList account sync, and MyAnimeList sync.

## Features

- Browse, search, show details with AniList metadata
- Season navigation and relation traversal
- AllAnime stream resolution with provider priority
- Local library tracking (watching, completed, plan to watch, etc.)
- AniList sync (browser login, push/pull, imports, optional auto-push)
- MyAnimeList sync (browser login, push/pull, optional auto-push)
- Settings inspector for recent sync results, skipped entries, and failure reasons
- Sync summaries are sent to Noctalia notification history as well as shell toasts
- Bar widget, panel, and settings integration

## Connect AniList

1. Create an AniList application in AniList developer settings.
2. Use `https://anilist.co/api/v2/oauth/pin` as the redirect URI for that app.
3. Copy the AniList client ID.
4. Open AnimeReloaded settings in Noctalia and go to `AniList Sync`.
5. Paste the client ID into `AniList Client ID`.
6. Click `Open AniList Login` and approve the request in your browser.
7. Paste the returned callback URL or raw token into `Callback URL or Access Token`.
8. Click `Finish Connect`.
9. Use `Pull From AniList`, `Push To AniList`, or enable `Auto Push` depending on how you want synchronization to behave.

## Architecture

All provider logic runs in-process via QML JavaScript. No Python runtime or external provider process.

```text
js/
  crypto-helper.js      CDN-loaded node-forge (AES-256-GCM, SHA-256)
  allanime-provider.js  AllAnime GraphQL + stream resolution
  anilist-provider.js   AniList GraphQL with cache + rate limiting
  anilist-sync-provider.js  AniList account sync
  mal-provider.js       MAL OAuth2 PKCE + library sync
  mapping-cache.js      AniList-to-AllAnime ID mapping
  providers.js          Unified dispatcher
```

## Requirements

- Noctalia Shell >= 3.6.0
- `mpv` for video playback
- `curl` for crypto library caching
- a browser for AniList and MAL login flows

## Notes

- Crypto operations use node-forge loaded from CDN (jsDelivr) on first use, cached to disk
- AllAnime API decryption uses AES-256-GCM with the standard reverse-engineered key
- AniList login uses the official browser flow with a returned token or callback URL paste step
- MAL auth uses OAuth2 PKCE flow via the declared backend proxy
