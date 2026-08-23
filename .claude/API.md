# AniStream Data Layer

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [CODING_RULES.md](CODING_RULES.md) · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · **API.md** · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the AniList and Nyaa.si integrations, torrent scraping/scoring, and caching. **See also:** [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where these services live, § 5 for how the two streaming paths (on-device vs. remote server) differ.

## 1. Overview

| Source | Role | Auth |
| --- | --- | --- |
| **AniList** | Primary metadata (titles, covers, scores, airing schedule), user authentication, and watch-progress tracking | OAuth2 (implicit grant), read+write |
| **Nyaa.si** | Torrent discovery via RSS scraping | None (unauthenticated read) |
| **MyAnimeList** | **Passive link-out only** — a button on the details screen opens `myanimelist.net/anime/<id>` in the system browser | N/A — no API calls are made to MAL |

The optional Go server's own REST surface (`/api/stream`, etc.) is a separate, LAN-local API this app talks to for remote torrenting. It isn't a data source in the sense above — see [`anistream_server/README.md`](../anistream_server/README.md) and [ARCHITECTURE.md](ARCHITECTURE.md) § 6, not here.

## 2. AniList

**Auth flow** (`AnilistAuthService`) — OAuth2 implicit grant:

- `login()` opens `https://anilist.co/api/v2/oauth/authorize?client_id=43011&response_type=token` in the system browser, and binds a local `HttpServer` on `127.0.0.1:3456`.
- AniList redirects back to `/callback`, which serves a small static HTML page. Its inline script reads the token from `window.location.hash` (never sent to any server by the browser itself) and `POST`s it to `/store` on the same loopback server.
- The token persists via `SharedPreferencesAsync` under `anilist_access_token`.
- The whole flow times out after 5 minutes if no token arrives.

**Endpoint:** a single GraphQL endpoint, `https://graphql.anilist.co`, POSTed to via `AnilistQueryService.executeRaw`. Every query lives in `anilist_queries.dart`:

| Query/Mutation | Used for |
| --- | --- |
| `trending` | Home screen — "Trending Now" |
| `seasonPopular` | Home screen — "Popular This Season" |
| `allTimePopular` | Home screen — "All Time Popular" |
| `search` | Search screen, and the nav bar's instant-results dropdown |
| `currentlyAiring` | Schedule screen |
| `userWatchlistPaged` | Watchlist screen (per-tab: CURRENT/PLANNING/COMPLETED) |
| `viewerId` | Resolves the logged-in user's numeric AniList ID once per session |
| `mediaListEntryStatus` / `mediaProgress` | Reads the viewer's existing status/progress for one anime |
| `saveMediaListEntry` | Writes progress back to AniList (see auto-tracking, below) |

Most queries interpolate the shared `AnilistFragments.mediaCore` fragment for their field selection.

- KNOWN DRY GAP: `currentlyAiring` inlines its own near-identical field list instead of reusing the fragment. Harmless today (the two lists match) — fold it into the shared fragment next time this query is touched ([CODING_RULES.md](CODING_RULES.md) § 2).
- KNOWN DRY GAP: `mediaProgress` is a strict subset of `mediaListEntryStatus` (same shape, minus `status`), kept separate only because the two call sites differ (`AnimeDetailsScreen`'s "up next" readout vs. `AnilistTrackerService`'s eligibility check) — not because the data need differs. Candidate for consolidation next time either is touched ([CODING_RULES.md](CODING_RULES.md) § 2).

**Content filtering asymmetry:** `_bannedGenres` is `['Hentai', 'Ecchi']` when "Filter Ecchi" is on, else `['Hentai']`.

- For `trending`/`seasonPopular`/`allTimePopular`/`search`/`currentlyAiring`, this is passed server-side as AniList's `genre_not_in` GraphQL variable.
- For `userWatchlistPaged`, AniList's `mediaList` field has no genre filter, so filtering happens **client-side** — after decoding, by inspecting each entry's `media.genres` and dropping any that intersect the banned set.

**Auto-tracking** (`AnilistTrackerService`):

- Watches playback position. Once it crosses **90%** of the episode's duration, a 5-second timer arms.
- On expiry, fires `saveMediaListEntry` with the new progress, and flips status `PLANNING → CURRENT`, or `→ COMPLETED` if this episode is the anime's last.
- A per-session flag stops it firing twice. It only arms if the viewer is logged in and this episode is ahead of their existing recorded progress (or their status is still `PLANNING`).

## 3. Nyaa.si

**Mirrors:** `nyaa.si`, then `nyaa.iss.one` as fallback, tried in order with a 7-second per-mirror timeout (`TorrentMirrorFetcher`).

**Query construction:** for a given anime + episode, the search queue is the de-duplicated set of {romaji title, English title (if different), synonyms}. Each candidate is queried as `<title> <episode, zero-padded>` (or bare `<title>` for movies/batch-mode), against `<mirror>/?page=rss&q=<query>&c=1_2&f=0`, with `&s=seeders&o=desc` appended in batch mode.

**Concurrency:**

- Batch-mode and episode-mode search run concurrently via `Future.wait`.
- Within each, candidate titles are tried in list order — but a title that hasn't resolved within 500ms lets the *next* candidate start concurrently rather than blocking behind it. The first non-empty result by original list order still wins, even if a later concurrent request finishes first.
- Titles longer than 4 words also get a concurrent truncated-title fallback query, used only if the full-title query comes back empty.

**Parsing:** happens off the UI thread, in a single long-lived isolate (`TorrentParserWorker`, spawned lazily on first search, falling back to a one-shot `compute()` if isolate spawn ever fails). `TorrentParser` extracts season/episode/batch-range/resolution via a hand-written single-pass tokenizer rather than a chain of regexes — the file's own comments document the equivalence testing this was checked against. One regex is deliberately kept, for detecting `NN-NN` batch ranges, since that pattern's two-sided boundary check fits a regex engine and not a manual scanner.

**Scoring** (`TorrentScoringEngine`, starts at 100 points):

| Signal | Effect |
| --- | --- |
| Batch mode: not actually a batch, or wrong season | Rejected outright |
| Batch mode: covers episode 1 through the anime's full episode count | +20 |
| Batch/season match (either mode) | ±100 |
| Non-batch mode: episode number doesn't match | Rejected outright |
| "Final season" tag matches the anime's own title | ±100 |
| OVA/ONA/OAD/Special tag matches the anime's actual format | ±100 / +50 |
| Movie tag matches the anime's actual format | ±100 / +50 |
| Resolution | 1080p +20, 720p +10 |
| Codec | AV1 +30, HEVC/x265 +20, AVC/x264 +5 |
| 10-bit color | +15 |
| Opus audio | +15 |
| WebRip / WebDL | +10 / +5 |
| Trusted-uploader flag | +30 |
| Seeder count | `log(seeders + 1) × 5`, clamped 0–50 |
| Size-per-episode | Penalized outside a plausible range (episodes: ~250–1200 MB; movies: ~1500–6000 MB), rewarded inside it |

## 4. Caching

This table is the single authoritative list of every cache in the app, regardless of which subsystem owns it — a codebase-wide concern, not limited to AniList/Nyaa. [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule routes "new cache, or a changed TTL" here for exactly this reason: add a row even if the new cache lives outside `data/`.

| Cache | TTL | Cap | Scope |
| --- | --- | --- | --- |
| `_AnilistCache` | 2 min | 40 entries | Read-only, non-personalized queries only (trending, season/all-time popular, currently airing, search). NEVER used for watchlist or progress queries — those must always reflect live state. |
| `_TorrentSearchCache` | 5 min | 60 entries | Keyed by `animeId:episodeNumber`. Only a successful, non-empty result is cached — a "no seeded torrents found" outcome is never cached, so a transient scrape failure doesn't get stuck. |
| `SettingsCache` | N/A (sync mirror, not TTL-based) | — | In-memory copy of the current `AppSettings`, kept live by `SettingsController` — see [ARCHITECTURE.md](ARCHITECTURE.md) § 3. |
| Image decoding | N/A | — | Not a persistent disk cache. `Image.network` calls are capped with a `cacheWidth` matched to the widget's actual rendered size, so Flutter's in-memory image cache never holds a full-resolution decode of a thumbnail-sized poster. |

---
*Last reviewed against the codebase: 2026-08-15. Added a query, a data source, or a cache? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
