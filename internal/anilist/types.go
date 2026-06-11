package anilist

// All type names are preserved from the original so that Wails-generated
// TypeScript interfaces remain compatible with the existing Svelte frontend.

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

type MediaListEntry struct {
	Progress int   `json:"progress"`
	Media    Anime `json:"media"`
}

type MediaList struct {
	Name    string           `json:"name"`
	Status  string           `json:"status"`
	Entries []MediaListEntry `json:"entries"`
}

// Internal wire types — not exported.
type gqlPayload struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}

type pageResponse struct {
	Data struct {
		Page struct {
			Media []Anime `json:"media"`
		} `json:"Page"`
	} `json:"data"`
}
