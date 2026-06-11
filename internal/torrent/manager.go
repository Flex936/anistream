package torrent

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"sync"
	"time"

	// Alias avoids a package-name collision: this package is also named "torrent".
	tlib "github.com/anacrolix/torrent"
)

const dataDir = "./tmp_downloads"

// Manager owns a single active torrent stream and its lifecycle.
type Manager struct {
	client *tlib.Client

	mu            sync.RWMutex
	activeTorrent *tlib.Torrent
	activeFile    *tlib.File
	cancelStream  context.CancelFunc
}

func NewManager() (*Manager, error) {
	cfg := tlib.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	cfg.NoUpload = true
	cfg.EstablishedConnsPerTorrent = 100
	cfg.HalfOpenConnsPerTorrent = 50
	cfg.TorrentPeersHighWater = 1000
	cfg.TorrentPeersLowWater = 500

	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("create torrent data dir: %w", err)
	}

	client, err := tlib.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("create torrent client: %w", err)
	}
	return &Manager{client: client}, nil
}

// Stream sets up a new torrent, waits for metadata, selects the largest file,
// and prioritises the first and last pieces for fast stream start. Any
// previously active stream is stopped first.
func (m *Manager) Stream(magnetLink string) error {
	// Cancel + clean up the old stream inside a single logical operation.
	m.Stop()

	// Recreate the data dir that Stop() deleted.
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return fmt.Errorf("recreate torrent data dir: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	m.mu.Lock()
	m.cancelStream = cancel
	m.mu.Unlock()

	t, err := m.client.AddMagnet(magnetLink)
	if err != nil {
		cancel()
		m.mu.Lock()
		m.cancelStream = nil
		m.mu.Unlock()
		return fmt.Errorf("add magnet: %w", err)
	}

	select {
	case <-t.GotInfo():
	case <-time.After(30 * time.Second):
		t.Drop()
		cancel()
		m.mu.Lock()
		m.cancelStream = nil
		m.mu.Unlock()
		return fmt.Errorf("timed out waiting for torrent metadata")
	case <-ctx.Done():
		t.Drop()
		return fmt.Errorf("stream setup cancelled")
	}

	target := largestFile(t)
	if target == nil {
		t.Drop()
		cancel()
		m.mu.Lock()
		m.cancelStream = nil
		m.mu.Unlock()
		return fmt.Errorf("no video file found in torrent")
	}

	prioritisePieces(t, target)

	m.mu.Lock()
	// Guard against a Stop() call that arrived while we were negotiating.
	if ctx.Err() != nil {
		m.mu.Unlock()
		t.Drop()
		return fmt.Errorf("stream aborted before transcoding could start")
	}
	m.activeTorrent = t
	m.activeFile = target
	m.mu.Unlock()

	return nil
}

// NewActiveFileReader returns an io.ReadSeekCloser positioned at the start of
// the active torrent file, pre-configured for responsive streaming.
// app.go uses this in the /stream HTTP handler without needing to import
// the anacrolix/torrent package directly.
func (m *Manager) NewActiveFileReader() (io.ReadSeekCloser, string, error) {
	m.mu.RLock()
	file := m.activeFile
	m.mu.RUnlock()

	if file == nil {
		return nil, "", fmt.Errorf("no active stream")
	}

	reader := file.NewReader()
	reader.SetResponsive()
	reader.SetReadahead(8 << 20) // 8 MiB lookahead
	return reader, file.DisplayPath(), nil
}

// Stop cancels the active context, drops the torrent, and deletes partial
// downloads to prevent disk bloat. Safe to call when no stream is active.
func (m *Manager) Stop() {
	m.mu.Lock()
	cancel := m.cancelStream
	t := m.activeTorrent
	m.cancelStream = nil
	m.activeTorrent = nil
	m.activeFile = nil
	m.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	if t != nil {
		log.Println("[Torrent] Dropping active torrent.")
		t.Drop()
	}

	// Safe to delete after Drop() — the client holds no more write handles.
	if err := os.RemoveAll(dataDir); err != nil {
		log.Printf("[Torrent] Warning: failed to clean data dir: %v", err)
	}
}

// Close stops the active stream and shuts down the torrent client permanently.
// Call this only during application shutdown.
func (m *Manager) Close() {
	m.Stop()
	m.client.Close()
	// Stop() already deleted the data dir; this is a belt-and-suspenders safety net.
	_ = os.RemoveAll(dataDir)
}

// --- helpers ---

func largestFile(t *tlib.Torrent) *tlib.File {
	var target *tlib.File
	var maxSize int64
	for _, f := range t.Files() {
		if f.Length() > maxSize {
			maxSize = f.Length()
			target = f
		}
	}
	return target
}

// prioritisePieces marks the first two and last two pieces of the target file
// as PriorityNow so the decoder can find headers and EOF data immediately.
func prioritisePieces(t *tlib.Torrent, f *tlib.File) {
	t.CancelPieces(0, t.NumPieces())
	pl := t.Info().PieceLength
	start := int(f.Offset() / pl)
	end := int((f.Offset() + f.Length()) / pl)

	for i := start; i < start+2 && i <= end; i++ {
		t.Piece(i).SetPriority(tlib.PiecePriorityNow)
	}
	for i := end; i > end-2 && i >= start; i-- {
		t.Piece(i).SetPriority(tlib.PiecePriorityNow)
	}
}
