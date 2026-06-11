package main

import (
	"encoding/json"
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
	cfg.EnableAV1 = false
	cfg.EnableOpus = false
	cfg.Upscaling = ""
	cfg.UpscaleResolution.Height = 1920
	cfg.UpscaleResolution.Width = 1080

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

func (a *App) GetTranscoder() string {
	cfg := LoadConfig()
	if cfg.Encoder == "" {
		return "libx264"
	}
	return cfg.Encoder
}

func (a *App) UpdateTranscoder(encoder string) error {
	cfg := LoadConfig()
	cfg.Encoder = encoder
	return SaveConfig(cfg)
}

func (a *App) GetAV1Enabled() bool {
	cfg := LoadConfig()
	return cfg.EnableAV1
}

func (a *App) UpdateAV1Enabled(enabled bool) error {
	cfg := LoadConfig()
	cfg.EnableAV1 = enabled
	return SaveConfig(cfg)
}

func (a *App) GetOpusEnabled() bool {
	cfg := LoadConfig()
	return cfg.EnableOpus
}

func (a *App) UpdateOpusEnabled(enabled bool) error {
	cfg := LoadConfig()
	cfg.EnableOpus = enabled
	return SaveConfig(cfg)
}

func (a *App) UpdateUpscaleMethod(Upscaling string) error {
	cfg := LoadConfig()
	cfg.Upscaling = Upscaling
	return SaveConfig(cfg)
}

func (a *App) GetUpscaleMethod() string {
	cfg := LoadConfig()
	return cfg.Upscaling
}

func (a *App) UpdateUpscaleResolution(Resolution Resolution) error {
	cfg := LoadConfig()
	cfg.UpscaleResolution.Height = Resolution.Height
	cfg.UpscaleResolution.Width = Resolution.Width
	return SaveConfig(cfg)
}

func (a *App) GetUpscaleResolution() Resolution {
	cfg := LoadConfig()
	return cfg.UpscaleResolution
}
