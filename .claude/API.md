
# AniStream Data Layer

> **AniStream Docs:** [CLAUDE.md — overview & index](CLAUDE.md) · [CODING_RULES.md — tech constraints](CODING_RULES.md) · [DESIGN.md — UI/UX rules](DESIGN.md) · [ARCHITECTURE.md — structure & platform](ARCHITECTURE.md) · **API.md — data & caching** · [README.md — project intro](../README.md) · [CONTRIBUTING.md — PR process](CONTRIBUTING.md)
> **Covers:** the AniList and Nyaa.si integrations, torrent scraping/scoring, and caching. **See also:** [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where these services live, § 5 for how the two streaming paths (on-device vs. remote server) differ.

## 1. Overview

| Source | Role | Auth |
| --- | --- | --- |
| **AniList** | Primary metadata (titles, covers, scores, airing schedule), user authentication, and watch-progress tracking | OAuth2 (implicit grant), read+write |
| **Nyaa.si** | Torrent discovery via RSS scraping | None (unauthenticated read) |
| **MyAnimeList** | **Passive link-out only** — a button on the details screen that opens `myanimelist.net/anime/<id>` in the system browser | N/A — no API calls are made to MAL from this app |

The optional Go server's own REST surface (`/api/stream`, etc.) is a separate, LAN-local API this app talks to for remote torrenting — it isn't a data source in the sense above, and is documented in [`anistream_server/README.md`](../anistream_server/README.md) and [ARCHITECTURE.md](ARCHITECTURE.md) § 6, not here.

## 2. AniList

**Auth flow** (`AnilistAuthService`): OAuth2 implicit grant. `login()` opens `https://anilist.co/api/v2/oauth/authorize?client_id=43011&response_type=token` in the system browser, while binding a local `HttpServer` on `127.0.0.1:3456`. AniList redirects back to `/callback`, which serves a small static HTML page whose inline script reads the token out of the URL fragment (`window.location.hash` — never sent to any server by the browser itself) and `POST`s it to `/store` on that same loopback server. The token is then persisted via `SharedPreferencesAsync` under `anilist_access_token`. The whole flow times out after 5 minutes if no token arrives.

**Endpoint:** a single GraphQL endpoint, `https://graphql.anilist.co`, POSTed to via `AnilistQueryService.executeRaw`. Every specific query lives in `anilist_queries.dart`:

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

Most queries interpolate the shared `AnilistFragments.mediaCore` fragment for their field selection. `currentlyAiring` is the one exception — it inlines its own near-identical field list instead of reusing the fragment. Functionally harmless today (the two lists happen to match), but worth folding into the shared fragment next time that query is touched, per [CODING_RULES.md](CODING_RULES.md) § 2's DRY directive.

`mediaProgress` is a strict subset of `mediaListEntryStatus` (same shape, minus `status`) — kept separate because it serves a different call site (`AnimeDetailsScreen`'s "up next" readout vs. `AnilistTrackerService`'s eligibility check), not because of any real difference in data need. Candidate for consolidation next time either is touched, per [CODING_RULES.md](CODING_RULES.md) § 2's DRY directive — same treatment as `currentlyAiring`'s fragment duplication above.

**Content filtering asymmetry:** `_bannedGenres` is `['Hentai', 'Ecchi']` when the user's "Filter Ecchi" setting is on, else just `['Hentai']`. For `trending` / `seasonPopular` / `allTimePopular` / `search` / `currentlyAiring`, this is passed server-side as AniList's own `genre_not_in` GraphQL variable. The personal watchlist query (`userWatchlistPaged`) has no such parameter — AniList's `mediaList` field doesn't expose a genre filter — so filtering there happens **client-side**, after the response is decoded, by inspecting each entry's `media.genres` and dropping any that intersect the banned set.

**Auto-tracking:** `AnilistTrackerService` watches playback position; once it crosses **90%** of the episode's duration, a 5-second timer arms, and on expiry it fires `saveMediaListEntry` with the new progress (and flips status `PLANNING → CURRENT`, or `→ COMPLETED` if this episode is the anime's last). A per-session flag stops it from firing twice, and it only arms at all if the viewer is logged in and this episode is actually ahead of their existing recorded progress (or their status is still `PLANNING`).

## 3. Nyaa.si

**Mirrors:** `nyaa.si`, then `nyaa.iss.one` as fallback, tried in order with a 7-second per-mirror timeout (`TorrentMirrorFetcher`).

**Query construction:** for a given anime + episode, the search queue is the de-duplicated set of {romaji title, English title (if different), synonyms}. Each candidate is queried as `<title> <episode, zero-padded>` (or bare `<title>` for movies/batch-mode), against `<mirror>/?page=rss&q=<query>&c=1_2&f=0`, with `&s=seeders&o=desc` appended in batch mode.

**Concurrency:** batch-mode and episode-mode search run concurrently via `Future.wait`. Within each, candidate titles are tried in list order, but a title that hasn't resolved within 500ms lets the *next* candidate start concurrently rather than blocking behind it (the first non-empty result by original list order still wins, even if a later concurrent request finishes first). Titles longer than 4 words also get a concurrent truncated-title fallback query, used only if the full-title query comes back empty.

**Parsing:** happens off the UI thread, in a single long-lived isolate (`TorrentParserWorker`, spawned lazily on first search, falling back to a one-shot `compute()` if isolate spawn ever fails). `TorrentParser` extracts season/episode/batch-range/resolution from the raw filename via a hand-written single-pass tokenizer rather than a chain of regexes — the file's own comments document the equivalence testing this was checked against. One regex is deliberately retained, for detecting `NN-NN` batch ranges, since that pattern's two-sided boundary check is a good fit for a regex engine and a poor fit for a manual scanner.

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

Caching is a codebase-wide concern, not limited to the AniList/Nyaa integrations covered above — this table is the single authoritative list of every cache in the app, regardless of which subsystem owns it. [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule routes "new cache, or a changed TTL" here for exactly this reason, so add a row here even if the new cache lives outside `data/`.

| Cache | TTL | Cap | Scope |
| --- | --- | --- | --- |
| `_AnilistCache` | 2 min | 40 entries | Read-only, non-personalized queries only (trending, season/all-time popular, currently airing, search). **Never** used for the watchlist or progress queries — those must always reflect live state. |
| `_TorrentSearchCache` | 5 min | 60 entries | Keyed by `animeId:episodeNumber`. Only a successful, non-empty result is cached — a "no seeded torrents found" outcome is never cached, so a transient scrape failure doesn't get stuck. |
| `SettingsCache` | N/A (sync mirror, not TTL-based) | — | An in-memory copy of the current `AppSettings`, kept live by `SettingsController` — see [ARCHITECTURE.md](ARCHITECTURE.md) § 3. |
| Image decoding | N/A | — | Not a persistent disk cache — `Image.network` calls are capped with a `cacheWidth` matched to the widget's actual rendered size, so Flutter's in-memory image cache never holds a full-resolution decode of a thumbnail-sized poster. |

---
*Last reviewed against the codebase: 2026-07-28. Added a query, a data source, or a cache? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
