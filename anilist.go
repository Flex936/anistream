package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
)

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

// doGraphQL is the single HTTP+JSON round-trip for all AniList queries.
// It is unexported because it is an implementation detail of this file.
func (a *App) doGraphQL(query string, variables map[string]interface{}, result interface{}) error {
	payload := GraphQLPayload{Query: query, Variables: variables}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal graphql payload: %w", err)
	}

	req, err := http.NewRequestWithContext(a.ctx, http.MethodPost, "https://graphql.anilist.co", bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("create anilist request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("network error contacting anilist: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("anilist returned status %d", resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(result)
}

func (a *App) SearchAnime(searchQuery string) ([]Anime, error) {
	const query = `
    query ($search: String) {
        Page(page: 1, perPage: 15) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
                id
                title { romaji english }
                coverImage { large }
                episodes status description
            }
        }
    }`
	var result AniListResponse
	if err := a.doGraphQL(query, map[string]interface{}{"search": searchQuery}, &result); err != nil {
		return nil, err
	}
	return result.Data.Page.Media, nil
}

func (a *App) GetTrendingAnime() ([]Anime, error) {
	const query = `
    query {
        Page(page: 1, perPage: 15) {
            media(type: ANIME, sort: TRENDING_DESC) {
                id
                title { romaji english }
                coverImage { large }
                episodes status description
            }
        }
    }`
	var result AniListResponse
	if err := a.doGraphQL(query, map[string]interface{}{}, &result); err != nil {
		return nil, err
	}
	return result.Data.Page.Media, nil
}
