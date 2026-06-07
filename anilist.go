package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
)

type NextAiringEpisode struct {
	Episode int `json:"episode"`
}

type AnimeTitle struct {
	Romaji  string `json:"romaji"`
	English string `json:"english"`
}

type AnimeCover struct {
	Large string `json:"large"`
}

type Anime struct {
	ID                int                `json:"id"`
	Title             AnimeTitle         `json:"title"`
	CoverImage        AnimeCover         `json:"coverImage"`
	Episodes          int                `json:"episodes"`
	Status            string             `json:"status"`
	Description       string             `json:"description"`
	NextAiringEpisode *NextAiringEpisode `json:"nextAiringEpisode"`
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

	cfg := LoadConfig()
	if cfg.AniListToken != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.AniListToken)
	}

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
	cfg := LoadConfig()
	bannedGenres := []string{"Hentai"}
	if cfg.FilterEcchi {
		bannedGenres = append(bannedGenres, "Ecchi")
	}

	const query = `
    query ($search: String, $bannedGenres: [String]) {
        Page(page: 1, perPage: 15) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH, isAdult: false, genre_not_in: $bannedGenres) {
                id
                title { romaji english }
                coverImage { large }
                episodes status description
				nextAiringEpisode { episode }
            }
        }
    }`
	var result AniListResponse
	variables := map[string]interface{}{
		"search":       searchQuery,
		"bannedGenres": bannedGenres,
	}

	if err := a.doGraphQL(query, variables, &result); err != nil {
		return nil, err
	}
	return result.Data.Page.Media, nil
}

func (a *App) GetTrendingAnime() ([]Anime, error) {
	cfg := LoadConfig()
	bannedGenres := []string{"Hentai"}
	if cfg.FilterEcchi {
		bannedGenres = append(bannedGenres, "Ecchi")
	}

	const query = `
    query ($bannedGenres: [String]) {
        Page(page: 1, perPage: 15) {
            media(type: ANIME, sort: TRENDING_DESC, isAdult: false, genre_not_in: $bannedGenres) {
                id
                title { romaji english }
                coverImage { large }
                episodes status description
				nextAiringEpisode { episode }
            }
        }
    }`
	var result AniListResponse
	if err := a.doGraphQL(query, map[string]interface{}{"bannedGenres": bannedGenres}, &result); err != nil {
		return nil, err
	}
	return result.Data.Page.Media, nil
}

func (a *App) GetAnimeProgress(animeID int) (int, error) {
	if !a.IsLoggedIn() {
		return 0, nil
	}

	// We must fetch the user's ID first!
	viewerID, err := a.getViewerID()
	if err != nil {
		return 0, nil
	}

	const query = `
    query ($userId: Int, $mediaId: Int) {
        MediaList(userId: $userId, mediaId: $mediaId) {
            progress
        }
    }`

	var result struct {
		Data struct {
			MediaList struct {
				Progress int `json:"progress"`
			} `json:"MediaList"`
		} `json:"data"`
	}

	err = a.doGraphQL(query, map[string]interface{}{
		"userId":  viewerID,
		"mediaId": animeID,
	}, &result)

	if err != nil {
		return 0, nil
	}

	return result.Data.MediaList.Progress, nil
}

func (a *App) UpdateAnimeProgress(animeID int, episode int) error {
	if !a.IsLoggedIn() {
		return fmt.Errorf("user is not logged in")
	}

	const query = `
    mutation ($mediaId: Int, $progress: Int) {
        SaveMediaListEntry(mediaId: $mediaId, progress: $progress) {
            id
            progress
        }
    }`

	var result interface{}
	return a.doGraphQL(query, map[string]interface{}{
		"mediaId":  animeID,
		"progress": episode,
	}, &result)
}

func (a *App) getViewerID() (int, error) {
	const query = `query { Viewer { id } }`
	var result struct {
		Data struct {
			Viewer struct {
				ID int `json:"id"`
			} `json:"Viewer"`
		} `json:"data"`
	}

	if err := a.doGraphQL(query, nil, &result); err != nil {
		return 0, err
	}
	if result.Data.Viewer.ID == 0 {
		return 0, fmt.Errorf("could not resolve viewer id")
	}
	return result.Data.Viewer.ID, nil
}
