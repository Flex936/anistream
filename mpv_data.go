package main

import (
	"bufio"
	"encoding/json"
	"net"
)

type MpvCommand struct {
	Command []interface{} `json:"command"`
}

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

// Responses from mpv
type FloatResponse struct {
	Data float64 `json:"data"`
}

type TrackResponse struct {
	Data []MpvTrack `json:"data"`
}

type ChapterResponse struct {
	Data []MpvChapter `json:"data"`
}

// --- Structs for your Svelte Frontend ---
type FrontendPayload struct {
	Duration    float64      `json:"duration"`
	AudioTracks []MpvTrack   `json:"audio_tracks"`
	Subtitles   []MpvTrack   `json:"subtitles"`
	Chapters    []MpvChapter `json:"chapters"`
}

func sendCommand(conn net.Conn, cmd []interface{}) {
	req := MpvCommand{Command: cmd}
	jsonBytes, _ := json.Marshal(req)
	// mpv requires a newline character at the end of every JSON command
	conn.Write(append(jsonBytes, '\n'))
}

func getFloatProperty(conn net.Conn, reader *bufio.Reader, prop string) float64 {
	sendCommand(conn, []interface{}{"get_property", prop})
	line, _ := reader.ReadBytes('\n')

	var res FloatResponse
	json.Unmarshal(line, &res)
	return res.Data
}

func getTracks(conn net.Conn, reader *bufio.Reader) []MpvTrack {
	sendCommand(conn, []interface{}{"get_property", "track-list"})
	line, _ := reader.ReadBytes('\n')

	var res TrackResponse
	json.Unmarshal(line, &res)
	return res.Data
}

func getChapters(conn net.Conn, reader *bufio.Reader) []MpvChapter {
	sendCommand(conn, []interface{}{"get_property", "chapter-list"})
	line, _ := reader.ReadBytes('\n')

	var res ChapterResponse
	json.Unmarshal(line, &res)
	return res.Data
}
