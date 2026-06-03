package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/mmcdole/gofeed"
)

// ==========================================
// 1. APP CORE & INITIALIZATION
// ==========================================

// App struct holds the application state and torrent engine
type App struct {
	ctx           context.Context
	torrentClient *torrent.Client
	activeFile    *torrent.File
}

// NewApp creates a new App application struct and boots the background services
func NewApp() *App {
	// Initialize the torrent client
	clientConfig := torrent.NewDefaultClientConfig()
	clientConfig.DataDir = "./tmp_downloads" // Temporarily store video chunks here
	client, _ := torrent.NewClient(clientConfig)

	app := &App{
		torrentClient: client,
	}

	// Start the local HTTP streaming server in the background
	go func() {
		http.HandleFunc("/stream", app.streamHandler)
		http.ListenAndServe(":8080", nil)
	}()

	return app
}

// startup is called when the app starts. The context is saved so we can call runtime methods.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
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

type TorrentResult struct {
	Title      string `json:"title"`
	MagnetLink string `json:"magnetLink"`
	Seeders    string `json:"seeders"`
	Size       string `json:"size"`
}

// GetEpisodeMagnet searches Nyaa.si and uses a smart Regex extraction heuristic to score episodes
func (a *App) GetEpisodeMagnet(animeTitle string, episodeNumber int) (*TorrentResult, error) {
	epStr := fmt.Sprintf("%02d", episodeNumber)

	searchQuery := fmt.Sprintf("%s %s", animeTitle, epStr)
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

	// Helper function: Extracts the season number from a string, safely ignoring regular numbers.
	extractSeason := func(title string) int {
		// Matches: "Season 2", "S2", "2nd Season", "Part 2"
		re := regexp.MustCompile(`(?i)(?:season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s+season|(?:part|cour)\s*(\d+))`)
		matches := re.FindStringSubmatch(title)
		if len(matches) > 0 {
			for i := 1; i < len(matches); i++ {
				if matches[i] != "" {
					var s int
					fmt.Sscanf(matches[i], "%d", &s)
					return s
				}
			}
		}
		return 0 // If no explicit season is mentioned, assume nothing
	}

	// --- SMART SCORING ALGORITHM ---
	var bestItem *gofeed.Item
	var highestScore int = -1

	queryTitleLow := strings.ToLower(animeTitle)
	targetSeason := extractSeason(queryTitleLow)

	log.Printf("[SCRAPER] Inferred Target Season: %d", targetSeason)

	for _, item := range feed.Items {
		score := 100
		titleLow := strings.ToLower(item.Title)
		torrentSeason := extractSeason(titleLow)

		// 1. DYNAMIC SEASON MATCHER
		if targetSeason != torrentSeason {
			score -= 100 // Heavy penalty for wrong season
		} else {
			score += 50 // Massive boost for correctly matching the season
		}

		// 2. PENALTIES: Spin-offs/OVAs/Movies
		if !strings.Contains(queryTitleLow, "vigilante") && strings.Contains(titleLow, "vigilante") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "ova") && strings.Contains(titleLow, "ova") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "ona") && strings.Contains(titleLow, "ona") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "movie") && strings.Contains(titleLow, "movie") {
			score -= 100
		}

		// 3. BOOSTS: Prioritize standard episodic formatting (e.g., "- 01")
		if strings.Contains(titleLow, fmt.Sprintf("- %s", epStr)) || strings.Contains(titleLow, fmt.Sprintf(" %s ", epStr)) {
			score += 20
		}

		// 4. BOOSTS: Prioritize trusted, high-quality release groups
		/* if strings.Contains(titleLow, "subsplease") || strings.Contains(titleLow, "erai-raws") || strings.Contains(titleLow, "horriblesubs") {
			score += 30
		} */

		// 5. Check quality preference (1080p -> 720p)
		if !strings.Contains(titleLow, "1080p") && !strings.Contains(titleLow, "720p") {
			score -= 20
		} else if strings.Contains(titleLow, "720p") {
			score -= 10
		}

		// 6. Check if we are on the final season and if the torrent is the final season
		if strings.Contains(titleLow, "final season") {
			score -= 100
		}

		// Log the individual score for debugging
		log.Printf("  -> [Score: %3d] (Season %d) %s", score, torrentSeason, item.Title)

		if score > highestScore {
			highestScore = score
			bestItem = item
		}
	}

	if bestItem == nil || highestScore <= 0 {
		return nil, fmt.Errorf("found torrents, but none matched the exact criteria for %s", animeTitle)
	}
	// -------------------------------

	log.Printf("[WINNER] Selected: %s (Score: %d)", bestItem.Title, highestScore)

	seeders := "Unknown"
	size := "Unknown"
	infoHash := ""

	if nyaaExt, ok := bestItem.Extensions["nyaa"]; ok {
		if hashNode, exists := nyaaExt["infoHash"]; exists && len(hashNode) > 0 {
			infoHash = hashNode[0].Value
		}
		if seedNode, exists := nyaaExt["seeders"]; exists && len(seedNode) > 0 {
			seeders = seedNode[0].Value
		}
		if sizeNode, exists := nyaaExt["size"]; exists && len(sizeNode) > 0 {
			size = sizeNode[0].Value
		}
	}

	if infoHash == "" {
		return nil, fmt.Errorf("no infoHash found in nyaa feed for %s", animeTitle)
	}

	magnetLink := fmt.Sprintf("magnet:?xt=urn:btih:%s&dn=%s", infoHash, url.QueryEscape(bestItem.Title))

	trackers := []string{
		"http://nyaa.tracker.wf:7777/announce",
		"udp://open.stealth.si:80/announce",
		"udp://tracker.opentrackr.org:1337/announce",
		"udp://exodus.desync.com:6969/announce",
		"udp://tracker.torrent.eu.org:451/announce",
	}
	for _, tr := range trackers {
		magnetLink += fmt.Sprintf("&tr=%s", url.QueryEscape(tr))
	}

	result := &TorrentResult{
		Title:      bestItem.Title,
		MagnetLink: magnetLink,
		Seeders:    seeders,
		Size:       size,
	}

	return result, nil
}

// ==========================================
// 4. TORRENT STREAMING ENGINE (PLAYBACK)
// ==========================================

// StreamTorrent takes a magnet link, finds the video file, and starts downloading
func (a *App) StreamTorrent(magnetLink string) (string, error) {
	t, err := a.torrentClient.AddMagnet(magnetLink)
	if err != nil {
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

	// Wait for the P2P swarm to send us the metadata, with a timeout
	select {
	case <-t.GotInfo():
		// metadata received, proceed
	case <-time.After(30 * time.Second):
		t.Drop()
		return "", fmt.Errorf("timed out waiting for torrent metadata — no peers responded")
	}

	var targetFile *torrent.File
	var maxSize int64
	for _, f := range t.Files() {
		if f.Length() > maxSize {
			maxSize = f.Length()
			targetFile = f
		}
	}

	if targetFile == nil {
		return "", fmt.Errorf("no valid video file found in torrent")
	}

	a.activeFile = targetFile
	targetFile.Download()

	return "http://localhost:8080/stream", nil
}

// streamHandler feeds the downloading torrent bytes to the Svelte video player
func (a *App) streamHandler(w http.ResponseWriter, r *http.Request) {
	if a.activeFile == nil {
		http.Error(w, "No active stream", http.StatusNotFound)
		return
	}

	reader := a.activeFile.NewReader()
	reader.SetResponsive()
	defer reader.Close()

	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeContent(w, r, a.activeFile.DisplayPath(), time.Time{}, reader)
}
