package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// AppConfig holds all user settings
type AppConfig struct {
	AniListToken string `json:"anilistToken"`
	Width        int    `json:"width"`
	Height       int    `json:"height"`
}

// getConfigPath automatically finds the correct OS app data folder
func getConfigPath() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = "." // Fallback to current directory
	}
	appDir := filepath.Join(configDir, "AniStream")
	os.MkdirAll(appDir, os.ModePerm)
	return filepath.Join(appDir, "config.json")
}

// LoadConfig reads the JSON file, or returns defaults if it doesn't exist
func LoadConfig() AppConfig {
	var cfg AppConfig
	// Default starting settings
	cfg.Width = 1280
	cfg.Height = 720

	data, err := os.ReadFile(getConfigPath())
	if err == nil {
		json.Unmarshal(data, &cfg)
	}
	return cfg
}

// SaveConfig writes the struct back to disk
func SaveConfig(cfg AppConfig) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(getConfigPath(), data, 0644)
}
