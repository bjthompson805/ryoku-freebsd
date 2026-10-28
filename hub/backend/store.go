package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// ryoku-hub owns network + disk for the store, so the shell side never fetches
// anything itself. source = the ryoku-extras repo, raw GitHub;
// RYOKU_EXTRAS_BASE overrides it (a fork, or a local tree under test).
//
//	ryoku-hub extras plugincatalog     fetch + merge the plugin catalogue, JSON
//	ryoku-hub extras plugin <id>       install a plugin, print its path
//	ryoku-hub extras pluginremove <id> remove an installed plugin
const defaultExtrasBase = "https://raw.githubusercontent.com/neur0map/ryoku-extras/main"

func extrasBase() string {
	if b := os.Getenv("RYOKU_EXTRAS_BASE"); b != "" {
		return strings.TrimRight(b, "/")
	}
	return defaultExtrasBase
}

func extrasCacheDir() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(base, "ryoku", "extras")
}

type pluginRegistryEntry struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Tagline     string   `json:"tagline,omitempty"`
	Description string   `json:"description,omitempty"`
	Author      string   `json:"author,omitempty"`
	Official    bool     `json:"official,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Icon        string   `json:"icon,omitempty"`
	Screenshots []string `json:"screenshots,omitempty"`
	Preview     string   `json:"preview,omitempty"`
	Hosts       []string `json:"hosts,omitempty"`
	Path        string   `json:"path,omitempty"`
	Version     string   `json:"version,omitempty"`
}

type pluginRegistry struct {
	Version int                   `json:"version"`
	Plugins []pluginRegistryEntry `json:"plugins"`
}

// catalogPlugin = one plugin as the Hub draws it: registry metadata enriched
// from the plugin's manifest.json, with screenshot/preview asset paths
// resolved to absolute URLs the Hub can fetch directly.
type catalogPlugin struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Tagline     string   `json:"tagline,omitempty"`
	Description string   `json:"description,omitempty"`
	Author      string   `json:"author,omitempty"`
	Official    bool     `json:"official,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Icon        string   `json:"icon,omitempty"`
	Screenshots []string `json:"screenshots,omitempty"`
	Preview     string   `json:"preview,omitempty"`
	Hosts       []string `json:"hosts,omitempty"`
	Path        string   `json:"path"`
	Version     string   `json:"version,omitempty"`
}

func runExtras(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("extras needs plugin|pluginremove|plugincatalog")
	}
	switch args[0] {
	case "plugin":
		if len(args) < 2 {
			return fmt.Errorf("extras plugin needs a name")
		}
		p, err := ensurePlugin(args[1])
		if err != nil {
			return err
		}
		fmt.Println(p)
		return nil
	case "pluginremove":
		if len(args) < 2 {
			return fmt.Errorf("extras pluginremove needs a name")
		}
		return removePlugin(args[1])
	case "plugincatalog":
		cat, err := buildPluginCatalog()
		if err != nil {
			return err
		}
		b, err := json.Marshal(cat)
		if err != nil {
			return err
		}
		fmt.Println(string(b))
		return nil
	default:
		return fmt.Errorf("extras needs plugin|pluginremove|plugincatalog")
	}
}

var extrasClient = &http.Client{Timeout: 12 * time.Second}

func fetch(url string) ([]byte, error) {
	// bust the GitHub raw (Fastly) CDN. plain URL can keep serving a pre-push
	// copy of the catalogue for minutes, so a Hub refresh just looks broken:
	// re-fetch, still get the stale registry.json. unique query param is the
	// only buster that actually works (raw ignores it for content but keys
	// its cache on it); the no-cache header is belt + braces.
	sep := "?"
	if strings.Contains(url, "?") {
		sep = "&"
	}
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("%s%s_=%d", url, sep, time.Now().UnixNano()), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Cache-Control", "no-cache")
	resp, err := extrasClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 4<<20))
}

func writeCache(rel string, data []byte) {
	p := filepath.Join(extrasCacheDir(), rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return
	}
	tmp, err := os.CreateTemp(filepath.Dir(p), ".tmp-*")
	if err != nil {
		return
	}
	name := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(name)
		return
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return
	}
	os.Rename(name, p)
}

// fetchOrCache: live bytes (and cache them), or the last cached copy when the
// network is gone. catalogue still renders offline.
func fetchOrCache(rel string) ([]byte, error) {
	if b, err := fetch(extrasBase() + "/" + rel); err == nil {
		writeCache(rel, b)
		return b, nil
	}
	if b, err := os.ReadFile(filepath.Join(extrasCacheDir(), rel)); err == nil {
		return b, nil
	}
	return nil, fmt.Errorf("cannot fetch or find cached %s", rel)
}

func buildPluginCatalog() (map[string][]catalogPlugin, error) {
	raw, err := fetchOrCache("plugins/registry.json")
	if err != nil {
		return nil, err
	}
	var reg pluginRegistry
	if err := json.Unmarshal(raw, &reg); err != nil {
		return nil, fmt.Errorf("plugins/registry.json: %w", err)
	}

	out := make([]catalogPlugin, 0, len(reg.Plugins))
	for _, e := range reg.Plugins {
		path := e.Path
		if path == "" {
			path = "plugins/" + e.ID
		}
		cp := catalogPlugin{
			ID:          e.ID,
			Name:        e.Name,
			Tagline:     e.Tagline,
			Description: e.Description,
			Author:      e.Author,
			Official:    e.Official,
			Tags:        e.Tags,
			Icon:        e.Icon,
			Screenshots: e.Screenshots,
			Preview:     e.Preview,
			Hosts:       e.Hosts,
			Path:        path,
			Version:     e.Version,
		}
		// best-effort manifest enrichment, same shape as buildCatalog folding
		// bundle.json into the registry entry: only fill what the registry
		// omitted, so a curated registry always wins.
		if b, err := fetchOrCache(path + "/manifest.json"); err == nil {
			var man struct {
				Name        string   `json:"name"`
				Description string   `json:"description"`
				Hosts       []string `json:"hosts"`
				Tags        []string `json:"tags"`
				Version     string   `json:"version"`
			}
			if json.Unmarshal(b, &man) == nil {
				if cp.Name == "" {
					cp.Name = man.Name
				}
				if cp.Description == "" {
					cp.Description = man.Description
				}
				if len(cp.Hosts) == 0 {
					cp.Hosts = man.Hosts
				}
				if len(cp.Tags) == 0 {
					cp.Tags = man.Tags
				}
				if cp.Version == "" {
					cp.Version = man.Version
				}
			}
		}
		// relative asset paths under plugins/<id>/ -> absolute URLs. anything
		// already http(s):// passes through.
		resolve := func(p string) string {
			if p == "" {
				return ""
			}
			if strings.HasPrefix(p, "http://") || strings.HasPrefix(p, "https://") {
				return p
			}
			return extrasBase() + "/" + path + "/" + strings.TrimLeft(p, "/")
		}
		cp.Preview = resolve(cp.Preview)
		if len(cp.Screenshots) > 0 {
			shots := make([]string, len(cp.Screenshots))
			for i, s := range cp.Screenshots {
				shots[i] = resolve(s)
			}
			cp.Screenshots = shots
		}
		out = append(out, cp)
	}
	return map[string][]catalogPlugin{"plugins": out}, nil
}

// ensureInstaller: pull a fresh copy of installers/<name>.sh into the cache
// and return its path. offline -> fall back to whatever is cached.
// pluginDataDir: where an installed plugin's source lives. shell runtime and
// Settings both read it. mirrors plugin_dir() in ryoku-extras-install.
func pluginDataDir(id string) string {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".local", "share")
	}
	return filepath.Join(base, "ryoku", "plugins", id)
}

// removePlugin nukes an installed plugin from the data dir. symlink-safe:
// a dev plugin is often a symlink into a checkout, so the symlink itself
// is unlinked (os.Remove), never recursed into so we don't eat the source
// tree it points at. a real install gets RemoveAll.
func removePlugin(id string) error {
	if id == "" {
		return fmt.Errorf("plugin id required")
	}
	// drop the plugin's plugins.json entry (placement + settings) so its config
	// disappears with it; the data-dir removal below is the real uninstall.
	_ = exec.Command("ryoku-plugins-place", id, "forget").Run()
	dir := pluginDataDir(id)
	fi, err := os.Lstat(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // already gone, nothing to do
		}
		return err
	}
	if fi.Mode()&os.ModeSymlink != 0 {
		return os.Remove(dir) // unlink the symlink, never touch the target
	}
	return os.RemoveAll(dir)
}

// ensurePlugin pulls a plugin's full source tree from the catalogue
// (plugins/<id>/) into the data dir, returns that dir. reads the manifest
// to know which files to grab (entryPoints + commands + files). README and
// the preview are cosmetic and skip on a miss; everything the manifest names
// IS the plugin, so a failed fetch aborts the install, and manifest.json
// lands last so an aborted run never looks installed.
func ensurePlugin(id string) (string, error) {
	rel := "plugins/" + id
	manRaw, err := fetch(extrasBase() + "/" + rel + "/manifest.json")
	if err != nil {
		return "", fmt.Errorf("plugin %q not found in the catalogue: %w", id, err)
	}
	var man struct {
		EntryPoints map[string]string `json:"entryPoints"`
		Commands    []string          `json:"commands"`
		Files       []string          `json:"files"`
	}
	if err := json.Unmarshal(manRaw, &man); err != nil {
		return "", fmt.Errorf("plugin %q manifest: %w", id, err)
	}

	dst := pluginDataDir(id)
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return "", err
	}
	write := func(name string, data []byte, mode os.FileMode) error {
		return atomicWrite(filepath.Join(dst, filepath.Clean(name)), data, mode)
	}

	optional := map[string]bool{"README.md": true, "assets/preview.gif": true}
	files := []string{"README.md", "assets/preview.gif"}
	for _, f := range man.EntryPoints {
		files = append(files, f)
	}
	for _, c := range man.Commands {
		files = append(files, c)
	}
	files = append(files, man.Files...)
	for _, f := range files {
		b, err := fetch(extrasBase() + "/" + rel + "/" + f)
		if err != nil {
			if optional[f] {
				continue
			}
			return "", fmt.Errorf("plugin %q: could not fetch %s: %w", id, f, err)
		}
		mode := os.FileMode(0o644)
		if strings.HasPrefix(f, "bin/") {
			mode = 0o755
		}
		if err := write(f, b, mode); err != nil {
			return "", err
		}
	}
	if err := write("manifest.json", manRaw, 0o644); err != nil {
		return "", err
	}
	// seed the plugin's preset block into plugins.json so its settings exist in
	// the right place the moment it lands (forgotten again on uninstall).
	_ = exec.Command("ryoku-plugins-place", id, "seed").Run()
	return dst, nil
}
