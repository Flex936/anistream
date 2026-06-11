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

type MediaListEntry struct {
	Progress int   `json:"progress"`
	Media    Anime `json:"media"`
}

type MediaList struct {
	Name    string           `json:"name"`
	Status  string           `json:"status"`
	Entries []MediaListEntry `json:"entries"`
}

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

	a.mu.RLock()
	token := a.aniListToken
	a.mu.RUnlock()
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
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

func getBannedGenres() []string {
	cfg := LoadConfig()
	genres := []string{"Hentai"}
	if cfg.FilterEcchi {
		genres = append(genres, "Ecchi")
	}
	return genres
}

func (a *App) SearchAnime(searchQuery string) ([]Anime, error) {
	bannedGenres := getBannedGenres()

	const query = `
    query ($search: String, $bannedGenres: [String]) {
        Page(page: 1, perPage: 15) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH, isAdult: false, genre_not_in: $bannedGenres, status_not: NOT_YET_RELEASED) {
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
	bannedGenres := getBannedGenres()

	const query = `
    query ($bannedGenres: [String]) {
        Page(page: 1, perPage: 15) {
            media(type: ANIME, sort: TRENDING_DESC, isAdult: false, genre_not_in: $bannedGenres, status_not: NOT_YET_RELEASED) {
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
	a.mu.RLock()
	id := a.viewerID
	a.mu.RUnlock()
	if id != 0 {
		return id, nil
	}

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

	a.mu.Lock()
	a.viewerID = result.Data.Viewer.ID
	a.mu.Unlock()
	return result.Data.Viewer.ID, nil
}

func (a *App) GetUserWatchlist() ([]MediaList, error) {
	if !a.IsLoggedIn() {
		return nil, fmt.Errorf("user is not logged in")
	}

	viewerID, err := a.getViewerID()
	if err != nil {
		return nil, err
	}

	// We query the MediaListCollection, grouping by status, specifically requesting CURRENT and PLANNING
	const query = `
    query ($userId: Int) {
        MediaListCollection(userId: $userId, type: ANIME, status_in: [CURRENT, PLANNING]) {
            lists {
                name
                status
                entries {
                    progress
                    media {
                        id
                        title { romaji english }
                        coverImage { large }
                        episodes
                        status
                        description
                        nextAiringEpisode { episode }
                    }
                }
            }
        }
    }`

	var result struct {
		Data struct {
			MediaListCollection struct {
				Lists []MediaList `json:"lists"`
			} `json:"MediaListCollection"`
		} `json:"data"`
	}

	err = a.doGraphQL(query, map[string]interface{}{"userId": viewerID}, &result)
	if err != nil {
		return nil, err
	}

	return result.Data.MediaListCollection.Lists, nil
}
