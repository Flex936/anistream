# AniStream Server

A lightweight Go binary that handles BitTorrent downloading and HTTP streaming
so thin clients (Android TV, phones, weak laptops) don't have to.

## How it fits in

```
[Flutter app on TV]  ──POST magnet──►  [AniStream Server on PC / NAS]
                     ◄──stream URL───   (anacrolix/torrent does the work)

MPV on the TV then opens the stream URL directly. HTTP range requests
(seeking) are handled server-side via http.ServeContent + torrent.Reader.
```

## Requirements

- Go 1.22 or later — https://go.dev/dl/
- The server and the TV must be on the same LAN (or connected via VPN)

## Build

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

## Run

```bash
./anistream-server
# or with custom options:
./anistream-server -port 7878 -data /mnt/media/anistream
```

| Flag    | Default                        | Description                        |
|---------|--------------------------------|------------------------------------|
| `-port` | `7878`                         | TCP port to listen on              |
| `-data` | `$TMPDIR/anistream-server`     | Directory for downloaded pieces    |

The server prints its address on startup. Copy that IP into the Flutter app's
Settings → Remote Server → Server URL field.

## Run on startup (Linux systemd)

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

| Method | Path                        | Body / Response                          |
|--------|-----------------------------|------------------------------------------|
| GET    | `/api/health`               | `{"status":"ok","version":"1.0.0"}`      |
| POST   | `/api/stream`               | `{magnet, episode_number?}` → `{session_id}` |
| GET    | `/api/stream/:id`           | `StatusResponse` (see below)             |
| POST   | `/api/stream/:id/select`    | `{file_index}` → `{ok:true}`             |
| GET    | `/api/stream/:id/video`     | HTTP range-request video stream (for MPV)|
| DELETE | `/api/stream/:id`           | 204 No Content                           |

### StatusResponse

```json
{
  "state":       "buffering",
  "status_text": "Buffering… 4.2%",
  "buffer_pct":  4.2,
  "peers":       18,
  "stream_url":  "http://192.168.1.5:7878/api/stream/abc123/video",
  "files":       null
}
```

`state` is one of `loading_metadata`, `needs_selection`, `buffering`, `ready`,
`error`. When `needs_selection`, `files` contains the list of video files in the
batch torrent for the user to choose from.

## Notes

- Idle sessions (no requests for 30 minutes) are cleaned up automatically.
- The server keeps seeding after download so the swarm stays healthy.
- No authentication — intended for trusted LAN use only. Use a firewall or
  VPN if you expose it to the internet.