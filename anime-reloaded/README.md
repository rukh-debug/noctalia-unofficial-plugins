# AnimeReloaded

Anime plugin for Noctalia Shell. AniList metadata, AllAnime streams, MyAnimeList sync.

## Features

- Browse, search, show details with AniList metadata
- Season navigation and relation traversal
- AllAnime stream resolution with provider priority
- Local library tracking (watching, completed, plan to watch, etc.)
- MyAnimeList sync (push/pull, OAuth2 PKCE)
- Bar widget, panel, and settings integration

## Architecture

All provider logic runs in-process via QML JavaScript. No Python or external dependencies.

```
js/
  crypto-helper.js    CDN-loaded node-forge (AES-256-GCM, SHA-256)
  allanime-provider.js  AllAnime GraphQL + stream resolution
  anilist-provider.js   AniList GraphQL with cache + rate limiting
  mal-provider.js       MAL OAuth2 PKCE, library sync
  mapping-cache.js      AniList-to-AllAnime ID mapping
  providers.js          Unified dispatcher
```

## Requirements

- Noctalia Shell >= 3.6.0
- `mpv` for video playback
- `curl` for crypto library caching (optional, falls back to CDN)

## Notes

- Crypto operations use node-forge loaded from CDN (jsDelivr) on first use, cached to disk
- AllAnime API decryption uses AES-256-GCM with the standard reverse-engineered key
- MAL auth uses OAuth2 PKCE flow via declared backend proxy
