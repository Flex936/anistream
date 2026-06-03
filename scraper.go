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

	// Compiled ONCE before the loop for performance
	batchRangePattern := regexp.MustCompile(`\d{2,}\s*[-~]\s*\d{2,}`)

	for _, item := range feed.Items {
		score := 100.0
		titleLow := strings.ToLower(item.Title)
		torrentSeason := extractSeason(titleLow)

		// 1. DYNAMIC SEASON MATCHER
		if targetSeason != torrentSeason {
			continue
		} else {
			score += 50
		}

		// 2. PENALTIES: Spin-offs/OVAs/Movies/Batches
		if !strings.Contains(queryTitleLow, "ova") && strings.Contains(titleLow, "ova") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "ona") && strings.Contains(titleLow, "ona") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "oad") && strings.Contains(titleLow, "oad") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "movie") && strings.Contains(titleLow, "movie") {
			score -= 100
		}
		if !strings.Contains(queryTitleLow, "special") && strings.Contains(titleLow, "special") {
			score -= 100
		}
		if strings.Contains(titleLow, "[batch]") || strings.Contains(titleLow, "(batch)") {
			score -= 150
		}
		if batchRangePattern.MatchString(titleLow) {
			score -= 150
		}

		// 3. BOOSTS: Episodic formatting
		if strings.Contains(titleLow, fmt.Sprintf("- %s", epStr)) || strings.Contains(titleLow, fmt.Sprintf(" %s ", epStr)) {
			score += 20
		}

		// 4. BOOSTS: Trusted groups
		if strings.Contains(titleLow, "subsplease") || strings.Contains(titleLow, "erai-raws") || strings.Contains(titleLow, "horriblesubs") {
			score += 30
		}

		// 5. BOOSTS: Quality
		if strings.Contains(titleLow, "1080p") {
			score += 20
		} else if strings.Contains(titleLow, "720p") {
			score += 10
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
					seedCount = 0
				}

				// 6. BOOSTS: Seeder amount
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

	// Sort the slice by Score (Highest to Lowest)
	sort.Slice(results, func(i, j int) bool {
		return results[i].Score > results[j].Score
	})

	return results, nil
}
