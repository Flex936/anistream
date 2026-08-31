# AniStream Data Layer

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [CODING_RULES.md](CODING_RULES.md) · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · **API.md** · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the AniList and Nyaa.si integrations, torrent scraping/scoring, and caching. **See also:** [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where these services live, § 5 for how the two streaming paths (on-device vs. remote server) differ.

## 1. Overview

| Source | Role | Auth |
| --- | --- | --- |
| **AniList** | Primary metadata (titles, covers, scores, airing schedule), user authentication, and watch-progress tracking | OAuth2 (implicit grant), read+write |
| **TsukiHime API** | Primary torrent discovery — anime- and episode-aware torrent listings, keyed off AniList ID (§ 5) | None (unauthenticated read) |
| **Nyaa.si** | Torrent discovery via RSS scraping — fallback only, used when TsukiHime has no match (§ 3) | None (unauthenticated read) |
| **BitTorrent trackers** | Live seeder/leecher counts for TsukiHime-sourced candidates, via direct tracker scrape (§ 6) | None |
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
| `mediaByExternalId` | Browser-extension deep link (ARCHITECTURE.md § 8) — resolves an AniList or MyAnimeList id into a full `Anime` |
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
- `mediaByExternalId` applies no genre filter at all, deliberately — the caller already named one specific title by identity (a browser-extension deep link), not a browsable list, so hiding it would be surprising rather than protective.

**Auto-tracking** (`AnilistTrackerService`):

- Watches playback position. Once it crosses **90%** of the episode's duration, a 5-second timer arms.
- On expiry, fires `saveMediaListEntry` with the new progress, and flips status `PLANNING → CURRENT`, or `→ COMPLETED` if this episode is the anime's last.
- A per-session flag stops it firing twice. It only arms if the viewer is logged in and this episode is ahead of their existing recorded progress (or their status is still `PLANNING`).

## 3. Nyaa.si

**Fallback role:** everything below describes the path used only when TsukiHime (§ 5) has no internal-ID match for the anime, or its own endpoints return zero usable torrents — not the primary source anymore.

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

## 5. TsukiHime API

**Role:** primary torrent source. Nyaa.si (§ 3) only runs when this returns nothing.

**Base URL:** `https://api.tsukihime.org/v1`, no auth. Endpoints used stay under the default 120 req/min rate limit — `/search/torrents` (50 req/min) is unused.

**Flow** (`TsukihimeApiService`):

1. `resolveInternalId(anilistId)` — `GET /animes/anilist/{anilistId}`. A 404 means the anime isn't in TsukiHime's database yet; `fetchTorrents` falls back to Nyaa in that case, not an error.
2. `getEpisodeTorrents(internalId, episodeNumber)` — `GET /animes/{id}/episodes/{n}`. Always queried — pre-filtered to that exact episode server-side, unlike Nyaa's own filename-guessing.
3. `getSeriesTorrents(internalId)` — `GET /animes/{id}`. Only queried when `anime.status == 'FINISHED' && anime.format != 'MOVIE'` (same condition the Nyaa-native batch branch already uses). Returns every torrent ever associated with the anime, batch and per-episode releases mixed together — `episode_no == null` on a result is what actually means "whole-series/season torrent," not which endpoint returned it.

Both list endpoints share one paginated envelope: `{ total, start, limit, error, results: [...] }`. Only the first page (`limit`'s default, 50) is fetched — not enough volume seen in practice to justify paging further.

**Fields consumed** (`TsukihimeTorrentWire`):

| Field | Maps to |
| --- | --- |
| `btih` | `Torrent.id` — the info hash; skip any result missing this outright, nothing else about it is usable |
| `name` | `Torrent.title` |
| `totalsize` (bytes) | `Torrent.size`, formatted |
| `episode_no` | `Torrent.isBatch` (`null` → batch) |
| `group.name` | `Torrent.releaseGroup` — real structured data, replaces `TorrentParser`'s bracket-extraction for this path |
| `nyaa_id` | gates whether a candidate is worth a tracker-scrape lookup at all (§ 6) — unrelated to `main_source` |

`group` itself can be `null` — happens on older/unattributed entries, mostly seen via `getSeriesTorrents`'s much larger, longer-lived result set rather than the tightly-filtered episode endpoint.

**Not provided by this API, and where it comes from instead:**

- **Resolution/codec** — no structured field. Still derived from `name` via the existing `TorrentParser.parse()`.
- **Seeders** — no field at all. Backfilled via direct tracker scraping — see § 6.

## 6. Tracker Scraping (Seeder Enrichment)

TsukiHime has no seeder data (§ 5). Rather than cross-referencing Nyaa.si per candidate, `TrackerScrapeService` queries real BitTorrent trackers directly, keyed by the info hash TsukiHime already provided.

**Two protocols, five trackers:**

| Tracker | Protocol | Notes |
| --- | --- | --- |
| `nyaa.tracker.wf:7777` | HTTP scrape | unofficial but universal convention — swap `/announce` for `/scrape`, `info_hash` query params, bencoded response |
| `tracker.opentrackr.org:1337` | HTTP scrape | same convention |
| `exodus.desync.com:6969` | UDP scrape ([BEP 0015](https://www.bittorrent.org/beps/bep_0015.html)) | no HTTP scrape endpoint |
| `open.stealth.si:80` | UDP scrape | scrape-only — not in `Torrent`'s own magnet-link tracker list (`torrent.dart`) |
| `tracker.torrent.eu.org:451` | UDP scrape | same — scrape-only |

The last two are queried purely to catch more of a swarm than the trackers actually embedded in AniStream's own magnet links would see — they're not added to `Torrent.magnetLink`'s tracker list, which stays exactly as it was.

**Batching and load:** one scrape request covers many info hashes at once (both protocols support this natively), so this is a small, fixed number of requests regardless of result-set size — unlike a per-candidate Nyaa search. Still bounded to the top `_kSeedersEnrichmentCount` (currently 10) candidates by preliminary score, since there's no reason to look up seeders for a torrent that's already scored out of contention.

**Merging:** where more than one tracker reports on the same hash, the higher seeder count wins — each tracker only knows about peers that announced to it, so taking the max avoids undercounting a real swarm split across trackers.

**Scoring:** folded in via the same `log(seeders + 1) × 5`, clamped 0–50, formula `TorrentScoringEngine` already uses for the Nyaa-native path — deliberately kept identical so a seeder count means the same thing regardless of which path found the torrent.

**Known caveat:** these five trackers have no guaranteed relationship to whatever trackers a given release's original uploader actually embedded — a swarm relying purely on DHT, or on trackers outside this list, won't be reflected here even if it has real seeders. nyaa.si's own displayed seeder count doesn't have this problem, since it reads whatever the specific upload it hosts actually declares — this is a deliberate trade-off (avoids hitting Nyaa at all), not a bug.

---
*Last reviewed against the codebase: 2026-08-30. Added a query, a data source, or a cache? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
