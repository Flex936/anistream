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
	"sort"
	"strconv"
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

				// 5. BOOSTS: Seeder amount
				score += float64(seedCount) * 0.2
				if seedCount == 0 {
					continue
				}
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
