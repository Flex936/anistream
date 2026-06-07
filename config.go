package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type AppConfig struct {
	AniListToken string `json:"anilistToken"`
	Width        int    `json:"width"`
	Height       int    `json:"height"`
	FilterEcchi  bool   `json:"filterEcchi"`
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
	os.MkdirAll(appDir, os.ModePerm)
	return filepath.Join(appDir, "config.json")
}

func LoadConfig() AppConfig {
	var cfg AppConfig
	cfg.Width = 1280
	cfg.Height = 720
	cfg.FilterEcchi = true

	data, err := os.ReadFile(getConfigPath())
	if err == nil {
		json.Unmarshal(data, &cfg)
	} else if os.IsNotExist(err) {
		SaveConfig(cfg)
	}
	return cfg
}

func SaveConfig(cfg AppConfig) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(getConfigPath(), data, 0644)
}

func (a *App) GetResolution() Resolution {
	cfg := LoadConfig()
	return Resolution{
		Width:  cfg.Width,
		Height: cfg.Height,
	}
}

func (a *App) UpdateResolution(width int, height int) error {
	cfg := LoadConfig()
	cfg.Width = width
	cfg.Height = height
	return SaveConfig(cfg)
}

func (a *App) GetEcchiFilter() bool {
	cfg := LoadConfig()
	return cfg.FilterEcchi
}

func (a *App) UpdateEcchiFilter(filter bool) error {
	cfg := LoadConfig()
	cfg.FilterEcchi = filter
	return SaveConfig(cfg)
}
