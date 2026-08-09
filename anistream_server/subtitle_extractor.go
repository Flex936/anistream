package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/asticode/go-astisub"
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

// SubtitleFormat is the wire/output format ExtractSubtitleTrack
// produces. Added alongside native TTML/ASS parsing on the Flutter side
// (see native_subtitle_parser.dart) — the server now hands back more
// than just WebVTT text.
type SubtitleFormat string

const (
	// FormatWebVTT is the original, always-transcoded-via-ffmpeg
	// behavior, consumed by video_player's Dart-side ClosedCaptionFile
	// mechanism. Stays the default for callers that don't specify a
	// format (see main.go's serveSubtitleTrack), so anything that
	// predates this change keeps working unchanged.
	FormatWebVTT SubtitleFormat = "vtt"

	// FormatASS extracts the track's ORIGINAL bytes via stream copy — no
	// re-encode. Only valid when the source track's own codec is already
	// ass/ssa, true for the overwhelming majority of fansub releases.
	// Consumed by Media3's SsaParser on the Android side.
	FormatASS SubtitleFormat = "ass"

	// FormatTTML converts the extracted subtitle to TTML with
	// go-astisub — NOT ffmpeg. ffmpeg has no reliable TTML *encoder*
	// (its subtitle encoder list covers ass/ssa, srt, and webvtt, but
	// not ttml); astisub reads the extracted ASS directly in Go and
	// writes real TTML instead. Consumed by Media3's TtmlParser.
	// Requires `go get github.com/asticode/go-astisub` — not otherwise a
	// dependency of this server; see README.md's Requirements section.
	FormatTTML SubtitleFormat = "ttml"
)

// IsNativeCodec reports whether f can be served as a stream-copy (no
// re-encode) extraction of a track whose ffprobe-reported codec is
// codecName. FormatASS requires the source to already BE ass/ssa —
// forcing a copy against, say, a PGS bitmap track would silently produce
// a corrupt/empty .ass file, not a valid one.
func (f SubtitleFormat) IsNativeCodec(codecName string) bool {
	c := strings.ToLower(codecName)
	return f == FormatASS && (c == "ass" || c == "ssa")
}

// ExtractSubtitleTrack shells out to ffmpeg to pull the subtitle stream
// at streamIndex (an absolute container stream index, as returned by
// ProbeSubtitleTracks) out of sourcePath and writes it to destPath in
// the requested format.
//
//   - FormatWebVTT: ffmpeg re-encodes to WebVTT (unchanged from before —
//     the only format-conversion path that still goes through ffmpeg).
//     This intentionally does not attempt to preserve ASS styling —
//     verified directly that override tags like \pos and \move are
//     discarded cleanly rather than leaking into the output.
//   - FormatASS: ffmpeg stream-copies the track's own bytes untouched.
//     Caller (see main.go's serveSubtitleTrack) must have already
//     confirmed IsNativeCodec — this function does not re-validate
//     against ffprobe itself, to avoid a second probe round-trip on
//     every request.
//   - FormatTTML: extracts the same stream-copied bytes as FormatASS
//     into a scratch file, then converts ASS -> TTML with go-astisub.
//     ffmpeg is only used for the extraction step, never for the TTML
//     conversion itself.
func ExtractSubtitleTrack(ctx context.Context, sourcePath string, streamIndex int, destPath string, format SubtitleFormat) error {
	switch format {
	case FormatWebVTT:
		return extractViaFFmpeg(ctx, sourcePath, streamIndex, destPath, "webvtt")

	case FormatASS:
		return extractViaFFmpeg(ctx, sourcePath, streamIndex, destPath, "copy")

	case FormatTTML:
		// ffmpeg infers its output muxer from destPath's extension, the
		// same mechanism the direct FormatASS case above already relies
		// on successfully. The scratch file must genuinely END in
		// ".ass" for that inference to pick the right muxer — a
		// filename ending in ".tmp" (e.g. destPath + ".ass.tmp", tried
		// first and confirmed broken: ffmpeg reports "Unable to choose
		// an output format" because .tmp is the last, and therefore the
		// only, extension it looks at) fails for exactly that reason.
		scratchPath := destPath + ".scratch.ass"
		if err := extractViaFFmpeg(ctx, sourcePath, streamIndex, scratchPath, "copy"); err != nil {
			return fmt.Errorf("extracting source ass for ttml conversion: %w", err)
		}
		defer os.Remove(scratchPath)
		return convertASSFileToTTML(scratchPath, destPath)

	default:
		return fmt.Errorf("unsupported subtitle format: %q", format)
	}
}

// extractViaFFmpeg runs the actual ffmpeg subprocess. codec is ffmpeg's
// -c:s value: "webvtt" to transcode, "copy" to stream-copy the track's
// original bytes untouched.
func extractViaFFmpeg(ctx context.Context, sourcePath string, streamIndex int, destPath, codec string) error {
	cmd := exec.CommandContext(ctx, "ffmpeg",
		"-y",
		"-loglevel", "warning",
		"-i", sourcePath,
		"-map", fmt.Sprintf("0:%d", streamIndex),
		"-c:s", codec,
		destPath,
	)

	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg extraction failed: %w (output: %s)", err, out)
	}

	return nil
}

// convertASSFileToTTML reads an .ass file and writes it back out as
// TTML, entirely in Go — see FormatTTML's doc comment above for why
// this isn't an ffmpeg step.
func convertASSFileToTTML(assPath, destPath string) error {
	f, err := os.Open(assPath)
	if err != nil {
		return fmt.Errorf("opening extracted ass file: %w", err)
	}
	defer f.Close()

	subs, err := astisub.ReadFromSSA(f)
	if err != nil {
		return fmt.Errorf("parsing ass content: %w", err)
	}

	out, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("creating ttml output file: %w", err)
	}
	defer out.Close()

	if err := subs.WriteToTTML(out); err != nil {
		return fmt.Errorf("writing ttml: %w", err)
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
