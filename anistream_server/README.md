# AniStream Server

> **Part of the AniStream docs.** Main suite: [CLAUDE.md](../.claude/CLAUDE.md) · [CODING_RULES.md](../.claude/CODING_RULES.md) · [DESIGN.md](../.claude/DESIGN.md) · [ARCHITECTURE.md](../.claude/ARCHITECTURE.md) · [API.md](../.claude/API.md) · [README.md](../README.md) · [CONTRIBUTING.md](../.claude/CONTRIBUTING.md)
> **Covers:** building, running, and the REST API of the standalone Go server that offloads torrenting from thin clients. **See also:** [ARCHITECTURE.md](../.claude/ARCHITECTURE.md) § 6 for the condensed architecture summary (session state diagram, which Dart controller talks to this server) — that section links back here for the full reference.

A lightweight Go binary that handles BitTorrent downloading and HTTP streaming so thin clients (Android TV, phones, weak laptops) don't have to.

## 1. How It Fits In

```text
[Flutter app on TV]  ──POST magnet──►  [AniStream Server on PC / NAS]
                     ◄──stream URL───   (anacrolix/torrent does the work)
```

MPV on the TV opens the returned stream URL directly. HTTP range requests (seeking) are handled server-side via `http.ServeContent` + `torrent.Reader`.

## 2. Requirements

- Go 1.23 or later — <https://go.dev/dl/> (matches the floor declared in `go.mod`)
- Server and client on the same LAN, or connected via VPN

## 3. Build

```bash
cd anistream_server
go mod tidy          # fetches anacrolix/torrent and its deps (~30 s first run)
go build -o anistream-server .
```

Cross-compile for a Raspberry Pi (arm64):

```bash
GOOS=linux GOARCH=arm64 go build -o anistream-server-pi .
```

Cross-compile for Windows (to run on a gaming PC):

```bash
GOOS=windows GOARCH=amd64 go build -o anistream-server.exe .
```

## 4. Run

```bash
./anistream-server
# or with custom options:
./anistream-server -port 7878 -data /mnt/media/anistream
```

| Flag | Default | Description |
| --- | --- | --- |
| `-port` | `7878` | TCP port to listen on |
| `-data` | `$TMPDIR/anistream-server` | Directory for downloaded pieces |
| `-readahead-bytes` | `10485760` (~10 MB) | Per-stream torrent read-ahead size in bytes. Lower this on memory-constrained servers, e.g. a Raspberry Pi — this bounds *this machine's* memory use, not the client device's |
| `-upload-limit-kbps` | `0` | Caps upload/seeding bandwidth in KB/s. `0` means unlimited, matching the server's long-standing default of seeding at full speed after a download completes |

The server prints its address on startup — copy that IP into the Flutter app's Settings → Remote Server → Server URL field.

## 5. Run on Startup (Linux systemd)

Create the data directory and make sure the service's user can write to it first — running as `nobody` against a fresh, root-owned path is the most common reason this unit fails immediately on first start:

```bash
sudo mkdir -p /opt/anistream/data
sudo chown nobody:nogroup /opt/anistream/data   # group name varies by distro — e.g. 'nobody' instead of 'nogroup' on some systems
```

```ini
# /etc/systemd/system/anistream-server.service
[Unit]
Description=AniStream Server
After=network.target

[Service]
ExecStart=/opt/anistream/anistream-server -data /opt/anistream/data
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now anistream-server
```

## 6. API Reference

| Method | Path | Body / Response |
| --- | --- | --- |
| GET | `/api/health` | `{"name":"AniStream Server","status":"ok","version":"1.0.0"}` |
| POST | `/api/stream` | `{magnet, episode_number?}` → `{session_id}` |
| GET | `/api/stream/:id` | `StatusResponse` (see below) |
| POST | `/api/stream/:id/select` | `{file_index}` → `{ok:true}` |
| GET | `/api/stream/:id/video` | HTTP range-request video stream (for MPV) |
| DELETE | `/api/stream/:id` | 204 No Content |

### StatusResponse

`state` is one of `loading_metadata`, `needs_selection`, `buffering`, `ready`, `error`. **Fields are omitted, not sent as `null`, when they don't apply** — check for key absence, not a null value.

**`buffering`** — the common case while a single-episode torrent downloads:

```json
{
  "state": "buffering",
  "status_text": "Buffering… 4.2%",
  "buffer_pct": 4.2,
  "peers": 18
}
```

**`ready`** — `stream_url` appears only now; hand it straight to MPV/media_kit:

```json
{
  "state": "ready",
  "status_text": "Ready",
  "buffer_pct": 5.2,
  "peers": 24,
  "stream_url": "http://192.168.1.5:7878/api/stream/abc123/video"
}
```

**`needs_selection`** — a batch torrent; `files` appears only now, and the client is expected to `POST` back to `/select` with a chosen `file_index`:

```json
{
  "state": "needs_selection",
  "status_text": "Batch torrent – pick an episode",
  "buffer_pct": 0,
  "peers": 12,
  "files": [
    { "index": 0, "name": "Show S01E01.mkv", "size": 734003200 },
    { "index": 1, "name": "Show S01E02.mkv", "size": 741324800 }
  ]
}
```

`error` follows the same shape as `buffering`, plus an `error` string field in place of `stream_url`/`files`.

## 7. Notes

- Idle sessions (no requests for 30 minutes) are cleaned up automatically.
- The server keeps seeding after download so the swarm stays healthy.
- **No auth, CORS fully open** (`Access-Control-Allow-Origin: *`) — required so any LAN device can reach it.
  - Trusted-LAN use only. NEVER expose this directly to the internet — put it behind a firewall or VPN.
  - CORS here is not a security boundary. Don't treat it as one.

---
*Last reviewed against the codebase: 2026-08-16. Changed a CLI flag, an endpoint, a response shape, or a session state? Update this file — and check whether [ARCHITECTURE.md](../.claude/ARCHITECTURE.md) § 6's condensed summary needs the same update (see [CLAUDE.md](../.claude/CLAUDE.md) § 2).*
