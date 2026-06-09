package main

import (
	"fmt"
	"log"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/mmcdole/gofeed"
)

// Globals: Pre-compile regexes ONCE on startup
var (
	whitespaceRegex = regexp.MustCompile(`\s+`)
	seasonRegex     = regexp.MustCompile(`(?i)(?:season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s+season|(?:part|cour)\s*(\d+))`)
	epRegex1        = regexp.MustCompile(`(?i)(?:e|ep|episode)\s*(\d+)`)
	epRegex2        = regexp.MustCompile(`\s+-\s+(\d+)(?:v\d)?\s+`)
	epRegex3        = regexp.MustCompile(`\s+(0\d+)\s+`)
	batchRegex      = regexp.MustCompile(`\d{2,}\s*[-~]\s*\d{2,}`)

	// Catches colons, exclamation marks, question marks, and quotes
	punctRegex = regexp.MustCompile(`[:!?'",]`)
)

// TorrentResult represents the data sent back to Svelte
type TorrentResult struct {
	Title      string  `json:"title"`
	MagnetLink string  `json:"magnetLink"`
	Seeders    string  `json:"seeders"`
	Size       string  `json:"size"`
	Score      float64 `json:"score"`
}

func extractSeason(title string) int {
	matches := seasonRegex.FindStringSubmatch(title)
	for i := 1; i < len(matches); i++ {
		if matches[i] != "" {
			s, _ := strconv.Atoi(matches[i])
			return s
		}
	}
	return 1
}

func extractEpisode(title string) int {
	for _, re := range []*regexp.Regexp{epRegex1, epRegex2, epRegex3} {
		if m := re.FindStringSubmatch(title); len(m) > 1 {
			ep, _ := strconv.Atoi(m[1])
			return ep
		}
	}
	return -1
}

func (a *App) GetEpisodeTorrents(animeTitle string, episodeNumber int) ([]TorrentResult, error) {
	epStr := fmt.Sprintf("%02d", episodeNumber)

	// Remove special characters that break Nyaa's search
	safeTitle := punctRegex.ReplaceAllString(animeTitle, " ")
	safeTitle = strings.TrimSpace(whitespaceRegex.ReplaceAllString(safeTitle, " "))

	// Try standard TV Show search with the episode number appended
	searchQuery := fmt.Sprintf("%s %s", safeTitle, epStr)
	results, err := a.searchAndScoreNyaa(searchQuery, animeTitle, episodeNumber, false)

	// he Movie Fallback Trap
	// If the standard search fails to find anything, AND we are looking for the first episode,
	// it is highly likely that this is a Movie, Film, or one-off OVA.
	if (err != nil || len(results) == 0) && episodeNumber == 1 {
		log.Printf("[SCRAPER] No standard episodes found for '%s'. Attempting Movie/Fallback search...", safeTitle)
		results, err = a.searchAndScoreNyaa(safeTitle, animeTitle, episodeNumber, true)
	}

	if err != nil {
		return nil, err
	}
	if len(results) == 0 {
		return nil, fmt.Errorf("no torrents found for %s episode %s", animeTitle, epStr)
	}

	return results, nil
}

// Extracted search logic to allow for clean fallback attempts
func (a *App) searchAndScoreNyaa(searchQuery string, animeTitle string, episodeNumber int, isMovieFallback bool) ([]TorrentResult, error) {
	encodedQuery := url.QueryEscape(searchQuery)
	feedURL := fmt.Sprintf("https://nyaa.si/?page=rss&q=%s&c=1_2&f=0", encodedQuery)

	log.Printf("[SCRAPER] Searching Nyaa for: '%s'", searchQuery)

	fp := gofeed.NewParser()
	fp.Client = a.httpClient

	feed, err := fp.ParseURL(feedURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse nyaa rss feed (it may be down or rate-limiting): %w", err)
	}

	if len(feed.Items) == 0 {
		return nil, nil // Return nil instead of an error so the fallback logic can catch it cleanly
	}

	queryTitleLow := strings.ToLower(animeTitle)
	targetSeason := extractSeason(queryTitleLow)
	epStr := fmt.Sprintf("%02d", episodeNumber)

	// Determine if we should allow movie tags to bypass penalties
	isMovieQuery := isMovieFallback || strings.Contains(queryTitleLow, "movie") || strings.Contains(queryTitleLow, "film") || strings.Contains(queryTitleLow, "gekijouban")

	var results []TorrentResult

	for _, item := range feed.Items {
		score := 100.0
		titleLow := strings.ToLower(item.Title)
		torrentSeason := extractSeason(titleLow)

		// Dynamic season filter
		if targetSeason != torrentSeason {
			score -= 100
		} else {
			score += 100
		}

		// Final Season filter
		targetHasFinal := strings.Contains(queryTitleLow, "final season")
		torrentHasFinal := strings.Contains(titleLow, "final season")

		if !targetHasFinal && torrentHasFinal {
			score -= 100
		} else if targetHasFinal && torrentHasFinal {
			score += 100
		}

		// Episode filter
		torrentEp := extractEpisode(titleLow)
		if !isMovieFallback {
			// Strict TV checking
			if torrentEp != -1 && torrentEp != episodeNumber {
				continue
			}
		} else {
			// If it's a movie fallback, we allow items with NO episode number (-1) or episode 1.
			if torrentEp != -1 && torrentEp != 1 {
				continue
			}
		}

		// Penalties: Spin-offs/OVAs/Movies/Batches
		if !strings.Contains(queryTitleLow, "ova") && strings.Contains(titleLow, "ova") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "ona") && strings.Contains(titleLow, "ona") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "oad") && strings.Contains(titleLow, "oad") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "special") && strings.Contains(titleLow, "special") {
			score -= 100
		}

		// The Movie Trap: Adjusting penalties/boosts for films
		if !isMovieQuery && strings.Contains(titleLow, "movie") {
			score -= 100
		} else if isMovieQuery && (strings.Contains(titleLow, "movie") || strings.Contains(titleLow, "gekijouban") || strings.Contains(titleLow, "film")) {
			score += 50
		}

		if strings.Contains(titleLow, "[batch]") || strings.Contains(titleLow, "(batch)") {
			score -= 150
		}
		if batchRegex.MatchString(titleLow) {
			score -= 150
		}

		// Boost: Episodic formatting (Only for TV shows)
		if !isMovieFallback {
			if strings.Contains(titleLow, fmt.Sprintf("- %s", epStr)) || strings.Contains(titleLow, fmt.Sprintf(" %s ", epStr)) {
				score += 20
			}
		}

		// Boost: Trusted groups
		if strings.Contains(titleLow, "subsplease") || strings.Contains(titleLow, "erai-raws") || strings.Contains(titleLow, "horriblesubs") {
			score += 30
		}

		// Boost: Resolution
		if strings.Contains(titleLow, "1080p") {
			score += 20
		} else if strings.Contains(titleLow, "720p") {
			score += 10
		}

		// Boost: Next-Gen Video Codecs
		if strings.Contains(titleLow, "av1") {
			score += 30
		} else if strings.Contains(titleLow, "hevc") || strings.Contains(titleLow, "x265") || strings.Contains(titleLow, "h.265") {
			score += 20
		} else if strings.Contains(titleLow, "avc") || strings.Contains(titleLow, "x264") || strings.Contains(titleLow, "h.264") {
			score += 5
		}

		// Boost: Premium Upgrades (Color & Audio)
		if strings.Contains(titleLow, "10bit") || strings.Contains(titleLow, "10-bit") {
			score += 15
		}
		if strings.Contains(titleLow, "opus") {
			score += 10
		}

		// Boost: Source Material
		if strings.Contains(titleLow, "web-dl") || strings.Contains(titleLow, "webdl") {
			score += 10
		} else if strings.Contains(titleLow, "webrip") {
			score += 5
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
				seedCount, err := strconv.Atoi(seeders)
				if err != nil {
					seedCount = 0
				}
				score += float64(seedCount) * 0.1
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

	sort.Slice(results, func(i, j int) bool {
		return results[i].Score > results[j].Score
	})

	return results, nil
}
