// Package openlistlib exposes the upstream OpenList driver/server to Android.
// It is copied INTO the pinned OpenList module by build_openlist_aar.sh so that
// upstream internal/ imports remain legal. All drivers are imported unchanged.
package openlistlib

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/OpenListTeam/OpenList/v4/cmd/flags"
	_ "github.com/OpenListTeam/OpenList/v4/drivers"
	"github.com/OpenListTeam/OpenList/v4/internal/bootstrap"
	"github.com/OpenListTeam/OpenList/v4/internal/db"
	"github.com/OpenListTeam/OpenList/v4/internal/model"
	"github.com/OpenListTeam/OpenList/v4/internal/op"
	"gorm.io/gorm"
)

var mu sync.Mutex
var initialized bool
var bootstrapped bool
var active bool

// prepareConfig enforces loopback on EVERY start (including after users edit
// config.json through another route); it never resets storage mounts or tokens.
func prepareConfig(dir string) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	name := filepath.Join(dir, "config.json")
	conf := map[string]interface{}{}
	if b, err := os.ReadFile(name); err == nil {
		if err := json.Unmarshal(b, &conf); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	conf["force"] = true // disallow OPENLIST_* environment overrides
	conf["scheme"] = map[string]interface{}{
		"address": "127.0.0.1", "http_port": 5244, "https_port": -1,
		"force_https": false, "enable_h3": false,
	}
	conf["s3"] = map[string]interface{}{"enable": false}
	conf["ftp"] = map[string]interface{}{"enable": false}
	conf["sftp"] = map[string]interface{}{"enable": false}
	conf["mcp"] = map[string]interface{}{"enable": false}
	conf["cors"] = map[string]interface{}{
		"allow_origins": []string{"http://127.0.0.1:5244"},
		"allow_methods": []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PROPFIND", "HEAD"},
		"allow_headers": []string{"Authorization", "Content-Type", "Depth", "Range"},
	}
	b, err := json.MarshalIndent(conf, "", "  ")
	if err != nil {
		return err
	}
	tmp := name + ".new"
	if err := os.WriteFile(tmp, b, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, name)
}

// Init is performed ONCE per Android process. Stop/Start only control listeners.
func Init(dir, adminPassword string) error {
	mu.Lock()
	defer mu.Unlock()
	if initialized {
		return nil
	}
	if len(adminPassword) < 24 {
		return errors.New("admin password too short")
	}
	if err := prepareConfig(dir); err != nil {
		return err
	}
	if !bootstrapped {
		flags.DataDir = dir
		flags.ConfigPath = filepath.Join(dir, "config.json")
		flags.LogStd = false
		bootstrap.Init()
		bootstrapped = true
	}
	// v4.2.9 leaves fresh installs without an admin for its Web setup wizard.
	// Provision the embedded edition directly, without the environment-based
	// bootstrap path that prints the initial password to stdout. Never reset an
	// existing admin, including when an older install has no marker file.
	_, err := op.GetAdmin()
	if errors.Is(err, gorm.ErrRecordNotFound) {
		admin := &model.User{
			Username:   "admin",
			Role:       model.ADMIN,
			BasePath:   "/",
			Authn:      "[]",
			Permission: 0x71FF,
		}
		admin.SetPassword(adminPassword)
		if err := op.CreateUser(admin); err != nil {
			return fmt.Errorf("create OpenList administrator: %w", err)
		}
	} else if err != nil {
		return fmt.Errorf("read OpenList administrator: %w", err)
	}
	marker := filepath.Join(dir, ".sylphy_admin_initialized")
	if _, err := os.Stat(marker); os.IsNotExist(err) {
		if err := os.WriteFile(marker, []byte("1\n"), 0600); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	initialized = true
	return nil
}

func Start() error {
	mu.Lock()
	defer mu.Unlock()
	if !initialized {
		return errors.New("OpenList is not initialized")
	}
	if active {
		return nil
	}
	bootstrap.Start()
	active = true
	return nil
}

func Stop() error {
	mu.Lock()
	defer mu.Unlock()
	if !active {
		return nil
	}
	bootstrap.Shutdown(5 * time.Second)
	active = false
	if handle := db.GetDb(); handle != nil {
		if sqlDB, err := handle.DB(); err == nil {
			if _, err = sqlDB.Exec("PRAGMA wal_checkpoint(TRUNCATE)"); err != nil {
				return err
			}
		}
	}
	return nil
}

func Running() bool {
	mu.Lock()
	defer mu.Unlock()
	return active && bootstrap.IsRunning("http")
}
