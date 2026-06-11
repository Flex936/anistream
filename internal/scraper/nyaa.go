package scraper

import (
	"fmt"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/mmcdole/gofeed"
)

// Pre-compiled once at startup — never pay regex compilation cost per request.
var (
	whitespaceRe = regexp.MustCompile(`\s+`)
	seasonRe     = regexp.MustCompile(`(?i)(?:season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s+season|(?:part|cour)\s*(\d+))`)
	epRe1        = regexp.MustCompile(`(?i)(?:e|ep|episode)\s*(\d+)`)
	epRe2        = regexp.MustCompile(`\s+-\s+(\d+)(?:v\d)?\s+`)
	epRe3        = regexp.MustCompile(`\s+(0\d+)\s+`)
	batchRe      = regexp.MustCompile(`\d{2,}\s*[-~]\s*\d{2,}`)
	punctRe      = regexp.MustCompile(`[:!?'",]`)
)

// TorrentResult is the data sent to the Svelte frontend.
type TorrentResult struct {
	Title      string  `json:"title"`
	MagnetLink string  `json:"magnetLink"`
	Seeders    string  `json:"seeders"`
	Size       string  `json:"size"`
	Score      float64 `json:"score"`
}

// Client wraps Nyaa RSS search with scoring logic.
type Client struct {
	http *http.Client
}

func NewClient(httpClient *http.Client) *Client {
	return &Client{http: httpClient}
}

func (c *Client) GetEpisodeTorrents(animeTitle string, episodeNumber int) ([]TorrentResult, error) {
	epStr := fmt.Sprintf("%02d", episodeNumber)
	safeTitle := strings.TrimSpace(whitespaceRe.ReplaceAllString(
		punctRe.ReplaceAllString(animeTitle, " "), " "))

	results, err := c.searchAndScore(safeTitle+" "+epStr, animeTitle, episodeNumber, false)

	// Movie / OVA fallback: if nothing was found for episode 1, the title is
	// probably a film with no episode numbering.
	if (err != nil || len(results) == 0) && episodeNumber == 1 {
		log.Printf("[Scraper] No TV results for '%s'; trying movie/OVA fallback.", safeTitle)
		results, err = c.searchAndScore(safeTitle, animeTitle, episodeNumber, true)
	}
	if err != nil {
		return nil, err
	}
	if len(results) == 0 {
		return nil, fmt.Errorf("no torrents found for %s episode %s", animeTitle, epStr)
	}
	return results, nil
}

func (c *Client) searchAndScore(
	searchQuery, animeTitle string,
	episodeNumber int,
	isMovieFallback bool,
) ([]TorrentResult, error) {
	feedURL := fmt.Sprintf("https://nyaa.si/?page=rss&q=%s&c=1_2&f=0", url.QueryEscape(searchQuery))
	log.Printf("[Scraper] Nyaa query: %q", searchQuery)

	fp := gofeed.NewParser()
	fp.Client = c.http
	feed, err := fp.ParseURL(feedURL)
	if err != nil {
		return nil, fmt.Errorf("nyaa RSS error: %w", err)
	}
	if len(feed.Items) == 0 {
		return nil, nil // caller handles the empty case
	}

	titleLow := strings.ToLower(animeTitle)
	targetSeason := extractSeason(titleLow)
	epStr := fmt.Sprintf("%02d", episodeNumber)
	isMovieQuery := isMovieFallback ||
		strings.Contains(titleLow, "movie") ||
		strings.Contains(titleLow, "film") ||
		strings.Contains(titleLow, "gekijouban")

	var results []TorrentResult
	for _, item := range feed.Items {
		if r, ok := scoreItem(item, animeTitle, episodeNumber, epStr, targetSeason, isMovieFallback, isMovieQuery); ok {
			results = append(results, r)
		}
	}

	sort.Slice(results, func(i, j int) bool { return results[i].Score > results[j].Score })
	return results, nil
}

func scoreItem(
	item *gofeed.Item,
	animeTitle string,
	episodeNumber int,
	epStr string,
	targetSeason int,
	isMovieFallback, isMovieQuery bool,
) (TorrentResult, bool) {
	score := 100.0
	tl := strings.ToLower(item.Title) // torrent title, lowered
	ql := strings.ToLower(animeTitle) // query title, lowered

	// --- Season matching ---
	if extractSeason(tl) == targetSeason {
		score += 100
	} else {
		score -= 100
	}

	// "Final Season" must match in both or neither.
	hasFinal := strings.Contains(ql, "final season")
	torrentFinal := strings.Contains(tl, "final season")
	switch {
	case hasFinal && torrentFinal:
		score += 100
	case !hasFinal && torrentFinal:
		score -= 100
	}

	// --- Episode filter ---
	torrentEp := extractEpisode(tl)
	if !isMovieFallback {
		if torrentEp != -1 && torrentEp != episodeNumber {
			return TorrentResult{}, false
		}
	} else {
		if torrentEp != -1 && torrentEp != 1 {
			return TorrentResult{}, false
		}
	}

	// --- Type penalties (only apply when query doesn't already mention the type) ---
	for _, tag := range []string{"ova", "ona", "oad", "special"} {
		if !strings.Contains(ql, tag) && strings.Contains(tl, tag) {
			score -= 100
		}
	}

	if !isMovieQuery && strings.Contains(tl, "movie") {
		score -= 100
	} else if isMovieQuery && (strings.Contains(tl, "movie") ||
		strings.Contains(tl, "gekijouban") || strings.Contains(tl, "film")) {
		score += 50
	}

	if strings.Contains(tl, "[batch]") || strings.Contains(tl, "(batch)") || batchRe.MatchString(tl) {
		score -= 150
	}

	// --- Positive signals ---
	if !isMovieFallback && (strings.Contains(tl, "- "+epStr) || strings.Contains(tl, " "+epStr+" ")) {
		score += 20
	}
	if strings.Contains(tl, "subsplease") || strings.Contains(tl, "erai-raws") || strings.Contains(tl, "horriblesubs") {
		score += 30
	}
	if strings.Contains(tl, "1080p") {
		score += 20
	} else if strings.Contains(tl, "720p") {
		score += 10
	}

	switch {
	case strings.Contains(tl, "av1"):
		score += 30
	case strings.Contains(tl, "hevc"), strings.Contains(tl, "x265"), strings.Contains(tl, "h.265"):
		score += 20
	case strings.Contains(tl, "avc"), strings.Contains(tl, "x264"), strings.Contains(tl, "h.264"):
		score += 5
	}

	if strings.Contains(tl, "10bit") || strings.Contains(tl, "10-bit") {
		score += 15
	}
	if strings.Contains(tl, "opus") {
		score += 10
	}
	if strings.Contains(tl, "web-dl") || strings.Contains(tl, "webdl") {
		score += 10
	} else if strings.Contains(tl, "webrip") {
		score += 5
	}

	// --- Extract Nyaa extension metadata ---
	infoHash, seeders, size := extractNyaaMeta(item)
	if infoHash == "" {
		return TorrentResult{}, false
	}

	seedCount, _ := strconv.Atoi(seeders)
	if seedCount == 0 {
		return TorrentResult{}, false // unseeded — skip immediately
	}
	score += float64(seedCount) * 0.1

	return TorrentResult{
		Title:      item.Title,
		MagnetLink: buildMagnet(infoHash, item.Title),
		Seeders:    seeders,
		Size:       size,
		Score:      score,
	}, true
}

func extractNyaaMeta(item *gofeed.Item) (infoHash, seeders, size string) {
	seeders = "Unknown"
	size = "Unknown"

	nyaaExt, ok := item.Extensions["nyaa"]
	if !ok {
		return
	}

	if v := nyaaExt["infoHash"]; len(v) > 0 {
		infoHash = v[0].Value
	}
	if v := nyaaExt["seeders"]; len(v) > 0 {
		seeders = v[0].Value
	}
	if v := nyaaExt["size"]; len(v) > 0 {
		size = v[0].Value
	}
	return
}

func buildMagnet(infoHash, title string) string {
	link := fmt.Sprintf("magnet:?xt=urn:btih:%s&dn=%s", infoHash, url.QueryEscape(title))
	for _, tr := range []string{
		"http://nyaa.tracker.wf:7777/announce",
		"udp://tracker.opentrackr.org:1337/announce",
		"udp://exodus.desync.com:6969/announce",
	} {
		link += "&tr=" + url.QueryEscape(tr)
	}
	return link
}

func extractSeason(title string) int {
	m := seasonRe.FindStringSubmatch(title)
	for i := 1; i < len(m); i++ {
		if m[i] != "" {
			s, _ := strconv.Atoi(m[i])
			return s
		}
	}
	return 1
}

func extractEpisode(title string) int {
	for _, re := range []*regexp.Regexp{epRe1, epRe2, epRe3} {
		if m := re.FindStringSubmatch(title); len(m) > 1 {
			ep, _ := strconv.Atoi(m[1])
			return ep
		}
	}
	return -1
}
