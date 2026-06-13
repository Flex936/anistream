package mpv

import (
	"bufio"
	"encoding/json"
	"net"
)

// ipcCmd is the wire format for every MPV JSON IPC command.
type ipcCmd struct {
	Command []interface{} `json:"command"`
}

// MpvTrack and MpvChapter keep their original names so that Wails-generated
// TypeScript interfaces remain unchanged and the Svelte frontend requires no edits.
type MpvTrack struct {
	ID       int    `json:"id"`
	Type     string `json:"type"`
	Lang     string `json:"lang"`
	Title    string `json:"title"`
	Default  bool   `json:"default"`
	Selected bool   `json:"selected"`
}

type MpvChapter struct {
	Title string  `json:"title"`
	Time  float64 `json:"time"`
}

// FrontendPayload carries the complete live playback state polled from MPV.
// TimePos, Paused, Volume, and Muted are new additions required by the glass UI
// — the old HLS architecture derived these from the HTML <video> element instead.
type FrontendPayload struct {
	Duration    float64      `json:"duration"`
	TimePos     float64      `json:"time_pos"` // current playback position in seconds
	Paused      bool         `json:"paused"`
	Volume      float64      `json:"volume"` // 0–100 (MPV's native scale)
	Muted       bool         `json:"muted"`
	AudioTracks []MpvTrack   `json:"audio_tracks"`
	Subtitles   []MpvTrack   `json:"subtitles"`
	Chapters    []MpvChapter `json:"chapters"`
}

// ── Internal wire response types ─────────────────────────────────────────────

type floatResp struct {
	Data float64 `json:"data"`
}
type boolResp struct {
	Data bool `json:"data"`
}
type trackResp struct {
	Data []MpvTrack `json:"data"`
}
type chapterResp struct {
	Data []MpvChapter `json:"data"`
}

// ── Low-level property readers ────────────────────────────────────────────────
// Each function sends one IPC request and reads the response on conn.
// They must be called sequentially on the same connection because the socket
// is a simple line-oriented request/response protocol.

// SendCommand serialises cmd as a newline-terminated JSON IPC command and
// writes it to conn. Exported so app.go can implement SendMpvCommand.
func SendCommand(conn net.Conn, cmd []interface{}) {
	req := ipcCmd{Command: cmd}
	b, _ := json.Marshal(req)
	_, _ = conn.Write(append(b, '\n'))
}

func getFloatProperty(conn net.Conn, r *bufio.Reader, prop string) float64 {
	SendCommand(conn, []interface{}{"get_property", prop})
	line, _ := r.ReadBytes('\n')
	var res floatResp
	_ = json.Unmarshal(line, &res)
	return res.Data
}

func getBoolProperty(conn net.Conn, r *bufio.Reader, prop string) bool {
	SendCommand(conn, []interface{}{"get_property", prop})
	line, _ := r.ReadBytes('\n')
	var res boolResp
	_ = json.Unmarshal(line, &res)
	return res.Data
}

func getTracks(conn net.Conn, r *bufio.Reader) []MpvTrack {
	SendCommand(conn, []interface{}{"get_property", "track-list"})
	line, _ := r.ReadBytes('\n')
	var res trackResp
	_ = json.Unmarshal(line, &res)
	return res.Data
}

func getChapters(conn net.Conn, r *bufio.Reader) []MpvChapter {
	SendCommand(conn, []interface{}{"get_property", "chapter-list"})
	line, _ := r.ReadBytes('\n')
	var res chapterResp
	_ = json.Unmarshal(line, &res)
	return res.Data
}
