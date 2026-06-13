package config

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
)

type AppConfig struct {
	AniListToken      string     `json:"anilistToken"`
	Width             int        `json:"width"`
	Height            int        `json:"height"`
	FilterEcchi       bool       `json:"filterEcchi"`
	Encoder           string     `json:"encoder"`
	EnableAV1         bool       `json:"enableAV1"`
	EnableOpus        bool       `json:"enableOpus"`
	Upscaling         string     `json:"upscaling"`
	UpscaleResolution Resolution `json:"upscaleResolution"`
	DownloadDir       string     `json:"downloadDir"`
}

type Resolution struct {
	Width  int `json:"width"`
	Height int `json:"height"`
}

func getConfigPath() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = "."
	}
	appDir := filepath.Join(configDir, "AniStream")
	_ = os.MkdirAll(appDir, os.ModePerm)
	return filepath.Join(appDir, "config.json")
}

// Load reads the config from disk. On a missing file the defaults are written
// out so the user starts with a known-good baseline. On a corrupt file a
// warning is logged and the in-memory defaults are returned.
func Load() AppConfig {
	cfg := AppConfig{
		Width:       1280,
		Height:      720,
		FilterEcchi: true,
		Upscaling:   "",
		UpscaleResolution: Resolution{
			Width:  1920,
			Height: 1080,
		},
		DownloadDir: "./tmp_downloads",
	}

	data, err := os.ReadFile(getConfigPath())
	if os.IsNotExist(err) {
		_ = Save(cfg)
		return cfg
	}
	if err != nil {
		log.Printf("[Config] Could not read config file: %v", err)
		return cfg
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		log.Printf("[Config] Config file is malformed, using defaults: %v", err)
		return cfg
	}
	return cfg
}

func Save(cfg AppConfig) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(getConfigPath(), data, 0644)
}
