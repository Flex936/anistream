package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
)

// SubtitleTrack describes one subtitle stream found inside a media file.
// StreamIndex is the absolute container stream index (as ffprobe reports
// it) — pass it straight back into ExtractSubtitleTrack's streamIndex
// parameter to pull that exact track.
type SubtitleTrack struct {
	StreamIndex int    `json:"streamIndex"`
	Codec       string `json:"codec"` // e.g. "ass", "subrip", "hdmv_pgs_subtitle"
	Language    string `json:"language,omitempty"`
	Title       string `json:"title,omitempty"`
}

// ffprobeStream/ffprobeOutput mirror only the fields this file reads out
// of ffprobe's JSON. A wrong tag here fails silently — an empty/zero
// value, not a compile or parse error.
type ffprobeStream struct {
	Index     int    `json:"index"`
	CodecName string `json:"codec_name"`
	CodecType string `json:"codec_type"`
	Tags      struct {
		Language string `json:"language"`
		Title    string `json:"title"`
	} `json:"tags"`
}

type ffprobeOutput struct {
	Streams []ffprobeStream `json:"streams"`
}

// ProbeSubtitleTracks shells out to ffprobe and returns every subtitle
// stream found in path. Returns an empty (non-nil) slice, not an error,
// if the file simply has no subtitle tracks — that's a normal outcome
// for some releases, not a failure.
//
// path must be something ffprobe can open directly. For a torrent
// session that's still downloading, only call this once enough of the
// file is available for ffprobe to read the container's own index —
// unlike video, which your sequential-piece-prioritization already keeps
// the front of available, subtitle data isn't guaranteed to be reachable
// until much more of the file has arrived.
func ProbeSubtitleTracks(ctx context.Context, path string) ([]SubtitleTrack, error) {
	cmd := exec.CommandContext(ctx, "ffprobe",
		"-v", "quiet",
		"-print_format", "json",
		"-show_streams",
		path,
	)

	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("ffprobe failed: %w", err)
	}

	var parsed ffprobeOutput
	if err := json.Unmarshal(out, &parsed); err != nil {
		return nil, fmt.Errorf("failed to parse ffprobe output: %w", err)
	}

	tracks := make([]SubtitleTrack, 0)
	for _, s := range parsed.Streams {
		if s.CodecType != "subtitle" {
			continue
		}
		tracks = append(tracks, SubtitleTrack{
			StreamIndex: s.Index,
			Codec:       s.CodecName,
			Language:    s.Tags.Language,
			Title:       s.Tags.Title,
		})
	}

	return tracks, nil
}

// ExtractSubtitleTrack shells out to ffmpeg to pull the subtitle stream
// at streamIndex (an absolute container stream index, as returned by
// ProbeSubtitleTracks) out of sourcePath, converting it to WebVTT at
// destPath. WebVTT specifically because that's what Flutter's
// video_player.VideoPlayerController accepts via its closedCaptionFile
// parameter.
//
// This intentionally does not attempt to preserve ASS styling — verified
// directly (see package doc comment) that override tags like \pos and
// \move are discarded cleanly rather than leaking into the output.
func ExtractSubtitleTrack(ctx context.Context, sourcePath string, streamIndex int, destPath string) error {
	cmd := exec.CommandContext(ctx, "ffmpeg",
		"-y",
		"-loglevel", "warning",
		"-i", sourcePath,
		"-map", fmt.Sprintf("0:%d", streamIndex),
		"-c:s", "webvtt",
		destPath,
	)

	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg extraction failed: %w (output: %s)", err, out)
	}

	return nil
}

// FFmpegAvailable reports whether ffmpeg and ffprobe are both reachable
// on PATH. The server is meant to run on "any PC, NAS, or Raspberry Pi"
// per the README — neither tool is guaranteed to be installed. Call this
// once at startup (or lazily before the first extraction attempt) and
// degrade to "no subtitles available" rather than failing every request
// if it's false.
func FFmpegAvailable() bool {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return false
	}
	if _, err := exec.LookPath("ffprobe"); err != nil {
		return false
	}
	return true
}
