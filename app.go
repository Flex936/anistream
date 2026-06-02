package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// App struct
type App struct {
	ctx context.Context
}

// --- AniList Data Structures ---

// Anime represents the data we want to send to Svelte
type Anime struct {
	ID    int `json:"id"`
	Title struct {
		Romaji  string `json:"romaji"`
		English string `json:"english"`
	} `json:"title"`
	CoverImage struct {
		Large string `json:"large"`
	} `json:"coverImage"`
	Episodes    int    `json:"episodes"`
	Status      string `json:"status"`
	Description string `json:"description"`
}

// AniListResponse maps the deeply nested GraphQL response
type AniListResponse struct {
	Data struct {
		Page struct {
			Media []Anime `json:"media"`
		} `json:"Page"`
	} `json:"data"`
}

// GraphQLPayload represents the POST body sent to AniList
type GraphQLPayload struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// Greet returns a greeting for the given name
func (a *App) Greet(name string) string {
	return fmt.Sprintf("Hello %s, It's show time!", name)
}

// SearchAnime queries the AniList GraphQL API and returns a list of anime.
// Wails automatically converts this to a TypeScript Promise for Svelte.
func (a *App) SearchAnime(searchQuery string) ([]Anime, error) {
	// 1. The exact GraphQL query we want to run
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

	// 2. Prepare the JSON payload
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

	// 3. Create the HTTP request with a 10-second timeout
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("POST", "https://graphql.anilist.co", bytes.NewBuffer(jsonBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create http request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	// 4. Execute the request
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("network error contacting anilist: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("anilist api returned status: %d", resp.StatusCode)
	}

	// 5. Decode the JSON response directly into our Go structs
	var aniResponse AniListResponse
	if err := json.NewDecoder(resp.Body).Decode(&aniResponse); err != nil {
		return nil, fmt.Errorf("failed to decode anilist response: %w", err)
	}

	// 6. Return just the array of Anime (Svelte doesn't need the nested GraphQL junk)
	return aniResponse.Data.Page.Media, nil
}
