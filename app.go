package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os/exec"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/dexterlb/mpvipc"
	"github.com/mmcdole/gofeed"
)

// ==========================================
// 1. APP CORE & INITIALIZATION
// ==========================================

// App struct holds the application state and torrent engine
type App struct {
	ctx       context.Context
	mpvCmd    *exec.Cmd
	mpvClient *mpvipc.Connection
	mpvMutex  sync.Mutex
	mpvStdout io.ReadCloser
	clients   map[chan []byte]bool
	clientsMu sync.Mutex
}

// NewApp creates a new App application struct and boots the background services
func NewApp() *App {
	initTorrentEngine() // Initialize global torrent engine

	app := &App{}

	// Start the local HTTP streaming server in the background
	go func() {
		http.HandleFunc("/stream", app.streamHandler)
		http.HandleFunc("/mpv-frame-stream", app.mpvFrameStreamHandler)
		http.ListenAndServe(":8080", nil)
	}()

	return app
}

// startup is called when the app starts. The context is saved so we can call runtime methods.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	if err := a.initMpv(); err != nil {
		log.Printf("[MPV] Failed to initialize mpv: %v", err)
	}
}

func (a *App) shutdown(ctx context.Context) {
	a.mpvMutex.Lock()
	defer a.mpvMutex.Unlock()

	if a.mpvClient != nil {
		a.mpvClient.Close()
	}

	if a.mpvCmd != nil && a.mpvCmd.Process != nil {
		log.Println("[MPV] Terminating background video player process...")
		_ = a.mpvCmd.Process.Kill()
	}
}

// ==========================================
// 2. ANILIST METADATA ENGINE (DISCOVERY)
// ==========================================

// Flattened the nested structs to fix Wails type-generation panics
type AnimeTitle struct {
	Romaji  string `json:"romaji"`
	English string `json:"english"`
}

type AnimeCover struct {
	Large string `json:"large"`
}

type Anime struct {
	ID          int        `json:"id"`
	Title       AnimeTitle `json:"title"`
	CoverImage  AnimeCover `json:"coverImage"`
	Episodes    int        `json:"episodes"`
	Status      string     `json:"status"`
	Description string     `json:"description"`
}

type AniListResponse struct {
	Data struct {
		Page struct {
			Media []Anime `json:"media"`
		} `json:"Page"`
	} `json:"data"`
}

type GraphQLPayload struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}

// SearchAnime queries the AniList GraphQL API and returns a list of anime.
func (a *App) SearchAnime(searchQuery string) ([]Anime, error) {
	query := `
	query ($search: String) {
		Page(page: 1, perPage: 15) {
			media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
				id
				title {
					romaji
					english
				}
				coverImage {
					large
				}
				episodes
				status
				description
			}
		}
	}`

	payload := GraphQLPayload{
		Query: query,
		Variables: map[string]interface{}{
			"search": searchQuery,
		},
	}

	jsonBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal graphql payload: %w", err)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("POST", "https://graphql.anilist.co", bytes.NewBuffer(jsonBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create http request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("network error contacting anilist: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("anilist api returned status: %d", resp.StatusCode)
	}

	var aniResponse AniListResponse
	if err := json.NewDecoder(resp.Body).Decode(&aniResponse); err != nil {
		return nil, fmt.Errorf("failed to decode anilist response: %w", err)
	}

	return aniResponse.Data.Page.Media, nil
}

// ==========================================
// 3. NYAA.SI RSS SCRAPER (EPISODE LOCATOR)
// ==========================================

// TorrentResult represents the data sent back to Svelte
type TorrentResult struct {
	Title      string  `json:"title"`
	MagnetLink string  `json:"magnetLink"`
	Seeders    string  `json:"seeders"`
	Size       string  `json:"size"`
	Score      float64 `json:"score"`
}

// GetEpisodeTorrents searches Nyaa.si, scores every torrent dynamically, and returns a sorted list.
func (a *App) GetEpisodeTorrents(animeTitle string, episodeNumber int) ([]TorrentResult, error) {
	epStr := fmt.Sprintf("%02d", episodeNumber)

	searchQuery := fmt.Sprintf("%s %s 1080p", animeTitle, epStr)
	encodedQuery := url.QueryEscape(searchQuery)
	feedURL := fmt.Sprintf("https://nyaa.si/?page=rss&q=%s&c=1_2&f=0", encodedQuery)

	log.Printf("[SCRAPER] Searching Nyaa for: '%s'", searchQuery)

	fp := gofeed.NewParser()
	feed, err := fp.ParseURL(feedURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse nyaa rss feed: %w", err)
	}

	if len(feed.Items) == 0 {
		return nil, fmt.Errorf("no torrents found for %s episode %s", animeTitle, epStr)
	}

	// Helper function: Extracts the season number from a string
	extractSeason := func(title string) int {
		re := regexp.MustCompile(`(?i)(?:season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s+season|(?:part|cour)\s*(\d+))`)
		matches := re.FindStringSubmatch(title)
		if len(matches) > 0 {
			for i := 1; i < len(matches); i++ {
				if matches[i] != "" {
					s, _ := strconv.Atoi(matches[i])
					return s
				}
			}
		}
		return 1 // If no explicit season is mentioned, assume Season 1
	}

	queryTitleLow := strings.ToLower(animeTitle)
	targetSeason := extractSeason(queryTitleLow)

	var results []TorrentResult

	for _, item := range feed.Items {
		score := 100.0
		titleLow := strings.ToLower(item.Title)
		torrentSeason := extractSeason(titleLow)

		// 1. DYNAMIC SEASON MATCHER (Your requested algorithm upgrade!)
		if targetSeason != torrentSeason {
			score -= 100 // Penalty for wrong season
		} else {
			score += 50 // Massive boost for correctly matching the season!
		}

		// 2. PENALTIES: Spin-offs/OVAs/Movies
		if !strings.Contains(queryTitleLow, "vigilante") && strings.Contains(titleLow, "vigilante") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "ova") && strings.Contains(titleLow, "ova") {
			score -= 100
		} else if !strings.Contains(queryTitleLow, "ona") && strings.Contains(titleLow, "ona") {
			score -= 100
		} else if !strings.Contains(queryTitleLow, "oad") && strings.Contains(titleLow, "oad") {
			score -= 100
		} else if !strings.Contains(queryTitleLow, "movie") && strings.Contains(titleLow, "movie") {
			score -= 100
		} else if !strings.Contains(queryTitleLow, "special") && strings.Contains(titleLow, "special") {
			score -= 100
		}

		// 3. BOOSTS: Episodic formatting
		if strings.Contains(titleLow, fmt.Sprintf("- %s", epStr)) || strings.Contains(titleLow, fmt.Sprintf(" %s ", epStr)) {
			score += 20
		}

		// 4. BOOSTS: Trusted groups
		if strings.Contains(titleLow, "subsplease") || strings.Contains(titleLow, "erai-raws") || strings.Contains(titleLow, "horriblesubs") {
			score += 30
		}

		// Extract Metadata
		seeders := "Unknown"
		size := "Unknown"
		infoHash := ""

		if nyaaExt, ok := item.Extensions["nyaa"]; ok {
			if hashNode, exists := nyaaExt["infoHash"]; exists && len(hashNode) > 0 {
				infoHash = hashNode[0].Value
			}
			if seedNode, exists := nyaaExt["seeders"]; exists && len(seedNode) > 0 {
				seeders = seedNode[0].Value

				// Convert seeder string to int
				seedCount, err := strconv.Atoi(seeders)
				if err != nil {
					log.Printf("[SCRAPER] Failed to parse seeders: %v", err)
					seedCount = 0
				}

				// 5. BOOSTS: Seeder amount (descending)
				score += float64(seedCount) * 0.2
			}
			if sizeNode, exists := nyaaExt["size"]; exists && len(sizeNode) > 0 {
				size = sizeNode[0].Value
			}
		}

		if infoHash != "" {
			magnetLink := fmt.Sprintf("magnet:?xt=urn:btih:%s&dn=%s", infoHash, url.QueryEscape(item.Title))

			trackers := []string{
				"http://nyaa.tracker.wf:7777/announce",
				"udp://tracker.opentrackr.org:1337/announce",
				"udp://exodus.desync.com:6969/announce",
			}
			for _, tr := range trackers {
				magnetLink += fmt.Sprintf("&tr=%s", url.QueryEscape(tr))
			}

			results = append(results, TorrentResult{
				Title:      item.Title,
				MagnetLink: magnetLink,
				Seeders:    seeders,
				Size:       size,
				Score:      score,
			})
		}
	}

	// Sort the slice by Score (Highest to Lowest)
	sort.Slice(results, func(i, j int) bool {
		return results[i].Score > results[j].Score
	})

	return results, nil
}

// ==========================================
// 4. TORRENT STREAMING ENGINE (PLAYBACK)
// ==========================================

// StreamTorrent takes a magnet link, finds the video file, and starts downloading
func (a *App) StreamTorrent(magnetLink string) (string, error) {
	streamURL, err := internalStreamTorrent(magnetLink)
	if err != nil {
		return "", err
	}

	a.mpvMutex.Lock()
	defer a.mpvMutex.Unlock()

	// Clean up any previously running player instances cleanly
	if a.mpvClient != nil {
		a.mpvClient.Close()
		a.mpvClient = nil
	}
	if a.mpvCmd != nil && a.mpvCmd.Process != nil {
		_ = a.mpvCmd.Process.Kill()
		_ = a.mpvCmd.Wait()
	}
	if a.mpvStdout != nil {
		a.mpvStdout.Close()
		a.mpvStdout = nil
	}

	ipcSocket := "/tmp/wails-mpv.sock"
	if runtime.GOOS == "windows" {
		ipcSocket = `\\.\pipe\wails-mpv-pipe`
	}

	// Launch MPV headlessly, encoding playback directly into standard output as MJPEG
	a.mpvCmd = exec.Command("mpv",
		streamURL,
		"--o=-",               // Target stdout instead of a native window context
		"--of=mjpeg",          // Set container envelope format to MJPEG
		"--ovc=mjpeg",         // Set video encoding codec
		"--ovcopts=strict=-2", // Bypass strict compliance rules for non-standard full-range YUV in MJPEG
		"--sub-auto=all",      // Automatically bundle available subtitle files
		fmt.Sprintf("--input-ipc-server=%s", ipcSocket),
	)

	stdout, err := a.mpvCmd.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("failed to open video stdout stream pipe: %w", err)
	}
	a.mpvStdout = stdout

	if err := a.mpvCmd.Start(); err != nil {
		return "", fmt.Errorf("failed to start headless mpv transcoder: %w", err)
	}

	// Spin off broadcaster to handle frame reading and client dissemination
	go a.startFrameBroadcaster(stdout)

	// Give the operating system time to initialize the IPC pipe channel
	time.Sleep(600 * time.Millisecond)

	client := mpvipc.NewConnection(ipcSocket)
	if err := client.Open(); err != nil {
		log.Printf("[MPV] Note: Control IPC unattached, commands unavailable: %v", err)
	} else {
		a.mpvClient = client
	}

	// Return the static local stream URL context to signal Svelte to mount the canvas
	return "http://localhost:8080/mpv-frame-stream", nil
}

// streamHandler feeds the downloading torrent bytes to the Svelte video player
func (a *App) streamHandler(w http.ResponseWriter, r *http.Request) {
	internalStreamHandler(w, r)
}
func (a *App) initMpv() error {
	a.mpvMutex.Lock()
	defer a.mpvMutex.Unlock()

	// 1. Establish platform-safe socket naming conventions
	ipcSocket := "/tmp/wails-mpv.sock"
	if runtime.GOOS == "windows" {
		ipcSocket = `\\.\pipe\wails-mpv-pipe`
	}

	log.Printf("[MPV] Launching background player instance targeting: %s", ipcSocket)

	// 2. Start mpv as a headless slave process
	// Adjust flags like '--vo=null' depending on your canvas vs native window setup strategy
	a.mpvCmd = exec.Command("mpv",
		"--idle",
		fmt.Sprintf("--input-ipc-server=%s", ipcSocket),
		"--vo=gpu", // Use hardware-accelerated native window rendering
	)

	if err := a.mpvCmd.Start(); err != nil {
		return fmt.Errorf("could not launch mpv process: %w", err)
	}

	// 3. Briefly pause to let the operating system spin up the socket descriptor
	time.Sleep(600 * time.Millisecond)

	// 4. Dial into the newly initialized IPC line
	client := mpvipc.NewConnection(ipcSocket)
	if err := client.Open(); err != nil {
		_ = a.mpvCmd.Process.Kill()
		return fmt.Errorf("failed to bind connection onto mpv IPC line: %w", err)
	}

	a.mpvClient = client
	log.Println("[MPV] IPC pipeline established successfully.")

	// 5. Spin off an asynchronous consumer routine to monitor playback events
	go a.listenToMpvEvents()

	return nil
}

func (a *App) listenToMpvEvents() {
	events, stopListening := a.mpvClient.NewEventListener()
	defer close(stopListening)

	log.Println("[MPV] Listening for internal runtime player updates...")

	for event := range events {
		// Log important lifecycle transitions or pipe them straight down to Svelte
		if event.Name != "tick" {
			log.Printf("[MPV Event] Received event token: %s", event.Name)
			// Example: forward event directly to frontend
			// wailsRuntime.EventsEmit(a.ctx, "mpv-state-change", event)
		}
	}
}

func (a *App) startFrameBroadcaster(stdout io.ReadCloser) {
	buf := make([]byte, 8192)
	var frameBuffer []byte

	for {
		n, err := stdout.Read(buf)
		if err != nil {
			break
		}
		frameBuffer = append(frameBuffer, buf[:n]...)

		for {
			// Locate JPEG SOI (Start of Image) token marker
			start := bytes.Index(frameBuffer, []byte{0xFF, 0xD8})
			if start == -1 {
				if len(frameBuffer) > 0 {
					frameBuffer = frameBuffer[len(frameBuffer)-1:]
				}
				break
			}

			// Locate JPEG EOI (End of Image) token marker
			end := bytes.Index(frameBuffer[start:], []byte{0xFF, 0xD9})
			if end == -1 {
				if start > 0 {
					frameBuffer = frameBuffer[start:]
				}
				break
			}

			actualEnd := start + end + 2
			jpegData := frameBuffer[start:actualEnd]

			// Broadcast frame to all active client channels
			a.broadcastFrame(jpegData)

			frameBuffer = frameBuffer[actualEnd:] // Shift remaining data forward
		}
	}
	stdout.Close()
}

func (a *App) broadcastFrame(jpegData []byte) {
	a.clientsMu.Lock()
	defer a.clientsMu.Unlock()
	for clientChan := range a.clients {
		select {
		case clientChan <- jpegData:
		default:
			// Non-blocking: drop frame if the client is too slow to read
		}
	}
}

func (a *App) mpvFrameStreamHandler(w http.ResponseWriter, r *http.Request) {
	// Configure stream headers for live image delivery
	w.Header().Set("Content-Type", "multipart/x-mixed-replace; boundary=frame")
	w.Header().Set("Cache-Control", "no-cache, private")
	w.Header().Set("Connection", "keep-alive")

	frameChan := make(chan []byte, 10)

	// Register client channel
	a.clientsMu.Lock()
	if a.clients == nil {
		a.clients = make(map[chan []byte]bool)
	}
	a.clients[frameChan] = true
	a.clientsMu.Unlock()

	defer func() {
		a.clientsMu.Lock()
		delete(a.clients, frameChan)
		a.clientsMu.Unlock()
	}()

	for {
		select {
		case <-r.Context().Done():
			return
		case jpegData, ok := <-frameChan:
			if !ok {
				return
			}
			// Package frame into standard multipart chunk structure
			_, err := fmt.Fprintf(w, "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n", len(jpegData))
			if err != nil {
				return
			}
			if _, err = w.Write(jpegData); err != nil {
				return
			}
			if _, err = fmt.Fprintf(w, "\r\n"); err != nil {
				return
			}
			w.(http.Flusher).Flush()
		}
	}
}
