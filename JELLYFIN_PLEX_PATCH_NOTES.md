# Jellyfin / Plex basic adapter patch

Scope: basic remote library browsing, original-audio streaming, artwork and read-only cloud playlists through the existing `MusicAdapter`/`LibrarySync`/`MediaProxy`/`CacheManager` pipeline. Jellyfin also reads the server's structured lyrics.

## Setup

- **Jellyfin**: add a Jellyfin source with a server URL (including a reverse-proxy base path if used), username and password. The adapter requests `Users/AuthenticateByName`, saves its access token and verifies `System/Info/Public` plus `Users/Me` on reconnect. Jellyfin 12 does not support Emby's legacy token headers, so the adapter uses the `Authorization: MediaBrowser ... Token="..."` format.
- **Plex**: add a Plex source with a server URL and **an already obtained Plex server access token** in the access-token field; account PIN/JWT browser authorization is NOT included. The username/label field is optional and local only. The adapter binds the connection to the server's `machineIdentifier` and validates access to `library/sections` before scanning. It indexes all `artist` library sections with `type=10`. Playback uses same-server `Media.Part.key` URLs through the existing local proxy.
- **Cloud playlists**: both new source types are read-only. Existing local playlists can still contain these tracks. No server mutations are attempted.

## Important constraints

- Neither server supports cloud playlist writing, Plex account sign-in/PIN/JWT refresh, transcoding/HLS, playback reporting, or server-side starred/favorite updates through this patch. Plex users must supply a valid existing access token and renew it externally if it expires. To avoid mixing accounts under the same `TrackRef` namespace, changing a Plex token requires creating a new source instead of editing an existing one.
- Only same-server relative Plex media/image paths are used. Absolute external Plex artwork URLs are skipped rather than receiving credentials. HTTP redirects are not followed with credentials.
- Full index snapshots are staged and committed only after the remote scan completes. Server paging loops, duplicate IDs, invalid counts and malformed pages cause an error so the previous index survives.
- Playback and cache operate on original media files. Unsupported multi-part or transcoding-only media may fail with an explicit error. Partial downloads are not marked complete.
- The existing SQLite schema and `SourceProfile` fields are used; this patch does not require a database migration.

## Quick manual acceptance checks

1. Connect a Jellyfin 12 server and a token-authorized Plex server; verify an invalid token is rejected.
2. Index at least 300 songs in each source; verify second-page entries and count and that interruption retains the previous index.
3. Play, seek, pause and resume MP3/FLAC over HTTP Range and HTTPS reverse proxy.
4. Load a cover and Jellyfin .lrc lyrics; verify a source switch does not share assets or credentials.
5. Open a repeated-track server playlist; verify both entries are retained and it is marked read-only.
6. Disable/re-enable each source, then remove it; verify source-scoped credentials and in-flight requests are cleaned up.

API references:
- Jellyfin: https://jellyfin.org/posts/jellyfin-release-12.0/ and https://typescript-sdk.jellyfin.org/
- Plex: https://developer.plex.tv/pms/
