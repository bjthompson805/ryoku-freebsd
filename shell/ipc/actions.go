package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// shellDir (RYOKU_SHELL_DIR): run components straight out of a repo checkout
// (qs -p <dir>/quickshell/<name>) instead of an installed config under
// ~/.config. empty in a deployed setup.
var shellDir = os.Getenv("RYOKU_SHELL_DIR")

// qsSelect: qs config selector for a component. by repo path in dev, by config
// name when deployed.
func qsSelect(name string) []string {
	if shellDir != "" {
		return []string{"-p", filepath.Join(shellDir, "quickshell", name)}
	}
	return []string{"-c", name}
}

// ipcCall: invoke a Quickshell IpcHandler function. component may have just
// been started, so it retries briefly until the instance answers.
func ipcCall(config, target, fn, arg string) string {
	argv := append(qsSelect(config), "ipc", "call", target, fn)
	if arg != "" {
		argv = append(argv, arg)
	}
	var out []byte
	var err error
	for i := 0; i < 10; i++ {
		out, err = exec.Command("qs", argv...).CombinedOutput()
		if err == nil {
			return "ok"
		}
		time.Sleep(150 * time.Millisecond)
	}
	msg := strings.TrimSpace(string(out))
	if msg == "" {
		msg = err.Error()
	}
	return "err qs ipc " + config + "/" + fn + ": " + msg
}

// ipcCallN = ipcCall for IpcHandler functions that take more than one arg
// (e.g. pluginPopout(mon, id)). empty trailing args still go positionally.
func ipcCallN(config, target, fn string, args ...string) string {
	argv := append(qsSelect(config), "ipc", "call", target, fn)
	argv = append(argv, args...)
	var out []byte
	var err error
	for i := 0; i < 10; i++ {
		out, err = exec.Command("qs", argv...).CombinedOutput()
		if err == nil {
			return "ok"
		}
		time.Sleep(150 * time.Millisecond)
	}
	msg := strings.TrimSpace(string(out))
	if msg == "" {
		msg = err.Error()
	}
	return "err qs ipc " + config + "/" + fn + ": " + msg
}

// pillSockPath: the pill's command socket. The pill (a persistent Quickshell
// component) serves it; the daemon writes a surface command here to skip the
// `qs ipc call` subprocess on the keybind hot path.
func pillSockPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = "/tmp"
	}
	return filepath.Join(dir, "ryoku-pill.sock")
}

// pillSocketCall writes one command line to the pill socket and reports whether
// the pill acknowledged with "ok". A miss (socket down, pill restarting, an
// unknown command) returns false so the caller falls back to the qs client.
func pillSocketCall(line string) bool {
	conn, err := net.DialTimeout("unix", pillSockPath(), 200*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(time.Second))
	if _, err := fmt.Fprintln(conn, line); err != nil {
		return false
	}
	buf := make([]byte, 16)
	n, _ := conn.Read(buf)
	return strings.TrimSpace(string(buf[:n])) == "ok"
}

// pillIpc invokes a pill IpcHandler function, preferring the command socket and
// falling back to the qs client when it is unreachable. Empty args drop out of
// the socket line; the qs fallback keeps the same positional argv.
func pillIpc(fn string, args ...string) string {
	line := fn
	for _, a := range args {
		if a != "" {
			line += " " + a
		}
	}
	if pillSocketCall(line) {
		return "ok"
	}
	return ipcCallN("pill", "pill", fn, args...)
}

// queryActiveMonitor reads the focused monitor fresh from hyprctl. The daemon's
// cached d.activeMonitor() is the keybind hot path; this is the cold fallback
// and the one-shot seed the event watcher uses on connect.
func queryActiveMonitor() string {
	out, err := exec.Command("hyprctl", "activeworkspace", "-j").Output()
	if err != nil {
		return ""
	}
	var w struct {
		Monitor string `json:"monitor"`
	}
	if json.Unmarshal(out, &w) != nil {
		return ""
	}
	return w.Monitor
}

// lockMarker is the file qylock's lock_shell.qml touches once the compositor
// confirms every output is covered by a lock surface (WlSessionLock.secure)
// and removes again on unlock. lockSession blocks on it so hypridle's
// before_sleep_cmd keeps logind's sleep delay-inhibitor held until the screen
// is really locked; returning early suspends with the desktop still in the
// framebuffer, visible for a beat on resume.
func lockMarker() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = "/tmp"
	}
	return filepath.Join(dir, "qylock.locked")
}

// lockWait bounds the wait for the compositor-confirmed lock. It stays under
// logind's 5s InhibitDelayMaxSec so a locker that never confirms (a qylock
// predating the marker, a wedged Quickshell) delays suspend, never blocks it.
var lockWait = 3 * time.Second

// lockSession locks the screen with qylock, the in-session lock Ryoku ships.
// the shell has no lock of its own. It returns once the compositor has
// confirmed the lock (the marker), or after lockWait.
func lockSession() string {
	marker := lockMarker()
	if !pgrepRunning("quickshell.*quickshell-lockscreen.*/lock_shell.qml") {
		// no live locker: a marker on disk is a leftover of a killed one and
		// must not fake "locked" below.
		_ = os.Remove(marker)
		lock := filepath.Join(os.Getenv("HOME"), ".local", "share", "quickshell-lockscreen", "lock.sh")
		cmd := exec.Command(lock)
		if err := cmd.Start(); err != nil {
			return "err lock: " + err.Error()
		}
		// reap at unlock; Release() would leave one zombie per lock cycle.
		go func() { _ = cmd.Wait() }()
	}
	deadline := time.Now().Add(lockWait)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(marker); err == nil {
			return "ok"
		}
		time.Sleep(50 * time.Millisecond)
	}
	return "ok"
}

// voxtypeRecord starts or stops dictation on a running Voxtype daemon (the
// Super+` tap). Absent, this is a no-op and the voice surface stays a plain mic
// meter. verb is "start" or "stop".
func voxtypeRecord(verb string) {
	if _, err := exec.LookPath("voxtype"); err != nil {
		return
	}
	// reap the short-lived record client in the background so it does not linger
	// as a zombie; voxtypeRecord fires once per tap (start on show, stop on hide).
	cmd := exec.Command("voxtype", "record", verb)
	if err := cmd.Start(); err != nil {
		return
	}
	go func() { _ = cmd.Wait() }()
}

// dictationReady reports whether a Super+` tap can actually dictate: a Voxtype
// daemon is running. When it can't, the pill shows an
// "off" note instead of a listening wave that would capture nothing.
func dictationReady() bool {
	return exec.Command("pgrep", "-x", "voxtype").Run() == nil
}

// startCliphist starts the wl-paste watchers that feed clipboard history, once.
func startCliphist() {
	for _, kind := range []string{"text", "image"} {
		pattern := "wl-paste --type " + kind + " --watch cliphist"
		if pgrepRunning(pattern) {
			continue
		}
		cmd := exec.Command("wl-paste", "--type", kind, "--watch", "cliphist", "store")
		_ = cmd.Start()
		if cmd.Process != nil {
			_ = cmd.Process.Release()
		}
	}
}

func pgrepRunning(pattern string) bool {
	return exec.Command("pgrep", "-f", pattern).Run() == nil
}

// lockKeyState reads Caps/Num Lock off Hyprland's main keyboard. FreeBSD has
// no LED classdevs to watch, so the lock-key binds ask for it on release.
func lockKeyState() (caps, num bool, err error) {
	out, err := exec.Command("hyprctl", "devices", "-j").Output()
	if err != nil {
		return false, false, err
	}
	var devs struct {
		Keyboards []struct {
			Main     bool `json:"main"`
			CapsLock bool `json:"capsLock"`
			NumLock  bool `json:"numLock"`
		} `json:"keyboards"`
	}
	if err := json.Unmarshal(out, &devs); err != nil {
		return false, false, err
	}
	for _, k := range devs.Keyboards {
		if k.Main {
			return k.CapsLock, k.NumLock, nil
		}
	}
	return false, false, fmt.Errorf("no main keyboard")
}

// backlightProbe reads the panel's current brightness % from backlight(8).
func backlightProbe() (int, error) {
	out, err := exec.Command("backlight", "-q").Output()
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(out)))
}

// backlightAdjust steps the panel brightness by 5% (dir "up"/"down"), floored
// at 5 so a key repeat never blacks out the screen, and returns the new %.
func backlightAdjust(dir string) (string, error) {
	cur, err := backlightProbe()
	if err != nil {
		return "", err
	}
	next := cur + 5
	if dir == "down" {
		next = cur - 5
	}
	if next < 5 {
		next = 5
	}
	if next > 100 {
		next = 100
	}
	if err := exec.Command("backlight", strconv.Itoa(next)).Run(); err != nil {
		return "", err
	}
	return strconv.Itoa(next), nil
}

func stateDir() string {
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return d
	}
	return filepath.Join(os.Getenv("HOME"), ".local", "state")
}
