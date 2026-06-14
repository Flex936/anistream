package anilist

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

const apiURL = "https://graphql.anilist.co"

// Client wraps AniList's GraphQL API. All methods are safe for concurrent use.
type Client struct {
	http *http.Client

	mu       sync.RWMutex
	token    string
	viewerID int
}

func NewClient(httpClient *http.Client, token string) *Client {
	return &Client{http: httpClient, token: token}
}

// SetToken updates the bearer token and resets the cached viewer ID.
func (c *Client) SetToken(token string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.token = token
	c.viewerID = 0
}

// ClearToken removes the bearer token and resets all auth state.
func (c *Client) ClearToken() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.token = ""
	c.viewerID = 0
}

// IsLoggedIn reports whether a bearer token is currently set.
func (c *Client) IsLoggedIn() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.token != ""
}

func (c *Client) GetSeason() (string, int) {
	now := time.Now()
	month := now.Month()
	year := now.Year()
	switch {
	case month >= 1 && month <= 3:
		return "WINTER", year
	case month >= 4 && month <= 6:
		return "SPRING", year
	case month >= 7 && month <= 9:
		return "SUMMER", year
	default:
		return "FALL", year
	}
}

func (c *Client) Search(ctx context.Context, query string, filterEcchi bool) ([]Anime, error) {
	const gql = `
	query ($search: String, $bannedGenres: [String]) {
		Page(page: 1, perPage: 15) {
			media(search: $search, type: ANIME, sort: SEARCH_MATCH,
			      isAdult: false, genre_not_in: $bannedGenres,
			      status_not: NOT_YET_RELEASED) {
				id title { romaji english } coverImage { large }
				episodes status description nextAiringEpisode { episode airingAt }
			}
		}
	}`
	var out pageResponse
	err := c.do(ctx, gql, map[string]interface{}{
		"search":       query,
		"bannedGenres": blockedGenres(filterEcchi),
	}, &out)
	return out.Data.Page.Media, err
}

func (c *Client) Trending(ctx context.Context, filterEcchi bool) ([]Anime, error) {
	const gql = `
	query ($bannedGenres: [String]) {
		Page(page: 1, perPage: 15) {
			media(type: ANIME, sort: TRENDING_DESC,
			      isAdult: false, genre_not_in: $bannedGenres,
			      status_not: NOT_YET_RELEASED) {
				id title { romaji english } coverImage { large }
				episodes status description nextAiringEpisode { episode airingAt }
			}
		}
	}`
	var out pageResponse
	err := c.do(ctx, gql, map[string]interface{}{"bannedGenres": blockedGenres(filterEcchi)}, &out)
	return out.Data.Page.Media, err
}

func (c *Client) Seasonal(ctx context.Context, filterEcchi bool) ([]Anime, error) {
	const gql = `
    query GetCurrentlyAiring($page: Int, $perPage: Int = 50, $bannedGenres: [String], $currentSeason: MediaSeason, $currentYear: Int) {

        Page(page: $page, perPage: $perPage) {
            media(
                type: ANIME, 
                season: $currentSeason, 
                seasonYear: $currentYear,
                sort: TRENDING_DESC, 
                countryOfOrigin: "JP",
                isAdult: false, 
                format_not_in: [SPECIAL, OVA, ONA, MOVIE],
                genre_not_in: $bannedGenres
            ) {
              id 
              title { romaji english } 
              status
              episodes 
              nextAiringEpisode { episode timeUntilAiring airingAt } 
              coverImage { large }
            }
        }
    }`

	var out pageResponse
	currentSeason, currentYear := c.GetSeason()

	variables := map[string]interface{}{
		"bannedGenres":  blockedGenres(filterEcchi),
		"currentSeason": currentSeason,
		"currentYear":   currentYear,
	}

	err := c.do(ctx, gql, variables, &out)
	return out.Data.Page.Media, err
}

func (c *Client) Progress(ctx context.Context, animeID int) (int, error) {
	if !c.IsLoggedIn() {
		return 0, nil
	}
	viewerID, err := c.resolveViewerID(ctx)
	if err != nil {
		return 0, nil // non-fatal for unauthenticated callers
	}
	const gql = `
	query ($userId: Int, $mediaId: Int) {
		MediaList(userId: $userId, mediaId: $mediaId) { progress }
	}`
	var out struct {
		Data struct {
			MediaList struct {
				Progress int `json:"progress"`
			} `json:"MediaList"`
		} `json:"data"`
	}
	if err := c.do(ctx, gql, map[string]interface{}{
		"userId": viewerID, "mediaId": animeID,
	}, &out); err != nil {
		return 0, nil
	}
	return out.Data.MediaList.Progress, nil
}

func (c *Client) UpdateProgress(ctx context.Context, animeID, episode int) error {
	if !c.IsLoggedIn() {
		return fmt.Errorf("not logged in")
	}
	const gql = `
	mutation ($mediaId: Int, $progress: Int) {
		SaveMediaListEntry(mediaId: $mediaId, progress: $progress) { id progress }
	}`
	var out interface{}
	return c.do(ctx, gql, map[string]interface{}{
		"mediaId": animeID, "progress": episode,
	}, &out)
}

func (c *Client) Watchlist(ctx context.Context) ([]MediaList, error) {
	if !c.IsLoggedIn() {
		return nil, fmt.Errorf("not logged in")
	}
	viewerID, err := c.resolveViewerID(ctx)
	if err != nil {
		return nil, err
	}
	const gql = `
	query ($userId: Int) {
		MediaListCollection(userId: $userId, type: ANIME,
		                    status_in: [CURRENT, PLANNING]) {
			lists {
				name status
				entries {
					progress
					media {
						id title { romaji english } coverImage { large }
						episodes status description nextAiringEpisode { episode airingAt }
					}
				}
			}
		}
	}`
	var out struct {
		Data struct {
			MediaListCollection struct {
				Lists []MediaList `json:"lists"`
			} `json:"MediaListCollection"`
		} `json:"data"`
	}
	err = c.do(ctx, gql, map[string]interface{}{"userId": viewerID}, &out)
	return out.Data.MediaListCollection.Lists, err
}

// resolveViewerID returns the cached viewer ID or fetches it from the API.
func (c *Client) resolveViewerID(ctx context.Context) (int, error) {
	c.mu.RLock()
	id := c.viewerID
	c.mu.RUnlock()
	if id != 0 {
		return id, nil
	}

	const gql = `query { Viewer { id } }`
	var out struct {
		Data struct {
			Viewer struct {
				ID int `json:"id"`
			} `json:"Viewer"`
		} `json:"data"`
	}
	if err := c.do(ctx, gql, nil, &out); err != nil {
		return 0, err
	}
	if out.Data.Viewer.ID == 0 {
		return 0, fmt.Errorf("could not resolve AniList viewer id")
	}
	c.mu.Lock()
	c.viewerID = out.Data.Viewer.ID
	c.mu.Unlock()
	return out.Data.Viewer.ID, nil
}

// do executes a single GraphQL request and JSON-decodes the response into result.
func (c *Client) do(ctx context.Context, query string, variables map[string]interface{}, result interface{}) error {
	body, err := json.Marshal(gqlPayload{Query: query, Variables: variables})
	if err != nil {
		return fmt.Errorf("marshal gql payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build anilist request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	c.mu.RLock()
	token := c.token
	c.mu.RUnlock()
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("anilist network error: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("anilist returned HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(result)
}

func blockedGenres(filterEcchi bool) []string {
	genres := []string{"Hentai"}
	if filterEcchi {
		genres = append(genres, "Ecchi")
	}
	return genres
}
