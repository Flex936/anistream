# AniStream Server

> 📚 **Part of the AniStream docs.** Main suite: [CLAUDE.md](../.claude/CLAUDE.md) · [DESIGN.md](../.claude/DESIGN.md) · [ARCHITECTURE.md](../.claude/ARCHITECTURE.md) · [API.md](../.claude/API.md) · [README.md](../README.md) · [CONTRIBUTING.md](../.claude/CONTRIBUTING.md)
> **Covers:** building, running, and the REST API of the standalone Go server that offloads torrenting from thin clients. **See also:** [ARCHITECTURE.md](../.claude/ARCHITECTURE.md) § 6 for the condensed architecture summary (session state diagram, which Dart controller talks to this server) — that section links back here for the full reference.

A lightweight Go binary that handles BitTorrent downloading and HTTP streaming
so thin clients (Android TV, phones, weak laptops) don't have to.

## How it fits in

```text
[Flutter app on TV]  ──POST magnet──►  [AniStream Server on PC / NAS]
                     ◄──stream URL───   (anacrolix/torrent does the work)

MPV on the TV then opens the stream URL directly. HTTP range requests
(seeking) are handled server-side via http.ServeContent + torrent.Reader.
```

## Requirements

- Go 1.23 or later — <https://go.dev/dl/> (matches the floor declared in `go.mod`)
- The server and the TV must be on the same LAN (or connected via VPN)

## Build

```bash
cd anistream_server
go mod tidy          # fetches anacrolix/torrent and go-astisub and their deps (~30 s first run)
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

## Run

```bash
./anistream-server
# or with custom options:
./anistream-server -port 7878 -data /mnt/media/anistream
```

| Flag | Default | Description |
| --- | --- | --- |
| `-port` | `7878` | TCP port to listen on |
| `-data` | `$TMPDIR/anistream-server` | Directory for downloaded pieces |

The server prints its address on startup. Copy that IP into the Flutter app's
Settings → Remote Server → Server URL field.

## Run on startup (Linux systemd)

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

## API reference

| Method | Path | Body / Response |
| --- | --- | --- |
| GET | `/api/health` | `{"name":"AniStream Server","status":"ok","version":"1.0.0"}` |
| POST | `/api/stream` | `{magnet, episode_number?}` → `{session_id}` |
| GET | `/api/stream/:id` | `StatusResponse` (see below) |
| POST | `/api/stream/:id/select` | `{file_index}` → `{ok:true}` |
| GET | `/api/stream/:id/video` | HTTP range-request video stream (for MPV) |
| DELETE | `/api/stream/:id` | 204 No Content |

### StatusResponse

`state` is one of `loading_metadata`, `needs_selection`, `buffering`, `ready`, `error`. The JSON shape actually changes per state — `stream_url` and `files` are omitted from the response entirely (not sent as `null`) whenever they don't apply, so a client should check for key *absence*, not a null value.

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

`error` follows the same shape as `buffering` but adds an `error` string field instead of `stream_url`/`files`.

## Notes

- Idle sessions (no requests for 30 minutes) are cleaned up automatically.
- The server keeps seeding after download so the swarm stays healthy.
- **No authentication and fully open CORS** (`Access-Control-Allow-Origin: *`, needed so any device on the LAN can reach it) — intended for trusted LAN use only. Use a firewall or VPN if you expose it to the internet; don't treat the CORS policy as a security boundary, since it isn't one here.

---
*Last reviewed against the codebase: 2026-07-28. Changed a CLI flag, an endpoint, a response shape, or a session state? Update this file — and check whether ARCHITECTURE.md § 6's condensed summary needs the same update (see CLAUDE.md § 4).*
