package main

import (
	"encoding/hex"
	"net"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeWPA answers the control-socket commands wifiConnect sends. A network
// joins when its psk is goodPsk or it has none.
type fakeWPA struct {
	mu       sync.Mutex
	conn     *net.UnixConn
	attached net.Addr
	nets     map[string]map[string]string // id -> field -> value
	nextID   int
	saved    bool
	log      []string
}

const goodPsk = `"correct horse"`

func startFakeWPA(t *testing.T, known map[string]map[string]string) *fakeWPA {
	t.Helper()
	dir := t.TempDir()
	old := wpaCtrlDir
	wpaCtrlDir = dir
	t.Cleanup(func() { wpaCtrlDir = old })
	t.Setenv("XDG_RUNTIME_DIR", dir)

	c, err := net.ListenUnixgram("unixgram", &net.UnixAddr{Name: filepath.Join(dir, "wlan0"), Net: "unixgram"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	f := &fakeWPA{conn: c, nets: known, nextID: len(known)}
	go f.serve()
	return f
}

func (f *fakeWPA) serve() {
	buf := make([]byte, 4096)
	for {
		n, from, err := f.conn.ReadFrom(buf)
		if err != nil {
			return
		}
		f.mu.Lock()
		req := string(buf[:n])
		f.log = append(f.log, req)
		reply, event := f.handle(req, from)
		f.mu.Unlock()
		f.conn.WriteTo([]byte(reply), from)
		if event != "" && f.attached != nil {
			f.conn.WriteTo([]byte("<3>"+event), f.attached)
		}
	}
}

func (f *fakeWPA) handle(req string, from net.Addr) (reply, event string) {
	parts := strings.SplitN(req, " ", 4)
	switch parts[0] {
	case "ATTACH":
		f.attached = from
		return "OK\n", ""
	case "LIST_NETWORKS":
		var b strings.Builder
		b.WriteString("network id / ssid / bssid / flags\n")
		for id, n := range f.nets {
			ssid := n["ssid"]
			if raw, err := hex.DecodeString(ssid); err == nil {
				ssid = string(raw)
			}
			b.WriteString(id + "\t" + ssid + "\tany\t\n")
		}
		return b.String(), ""
	case "ADD_NETWORK":
		id := string(rune('0' + f.nextID))
		f.nextID++
		f.nets[id] = map[string]string{}
		return id + "\n", ""
	case "SET_NETWORK":
		f.nets[parts[1]][parts[2]] = parts[3]
		return "OK\n", ""
	case "REMOVE_NETWORK":
		delete(f.nets, parts[1])
		return "OK\n", ""
	case "SELECT_NETWORK":
		n := f.nets[parts[1]]
		if psk, ok := n["psk"]; ok && psk != goodPsk {
			return "OK\n", "CTRL-EVENT-SSID-TEMP-DISABLED id=" + parts[1] + " reason=WRONG_KEY"
		}
		return "OK\n", "CTRL-EVENT-CONNECTED - Connection to aa:bb:cc:dd:ee:ff completed"
	case "SAVE_CONFIG":
		f.saved = true
		return "OK\n", ""
	case "ENABLE_NETWORK":
		return "OK\n", ""
	}
	return "UNKNOWN COMMAND\n", ""
}

func TestWifiConnectNew(t *testing.T) {
	f := startFakeWPA(t, map[string]map[string]string{})
	if err := wifiConnect("wlan0", "café net", "correct horse"); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	n := f.nets["0"]
	if n == nil || n["ssid"] != "636166c3a9206e6574" || n["psk"] != goodPsk || !f.saved {
		t.Errorf("network = %v, saved = %v", n, f.saved)
	}
}

func TestWifiConnectWrongPasswordRemovesNetwork(t *testing.T) {
	f := startFakeWPA(t, map[string]map[string]string{})
	if err := wifiConnect("wlan0", "home", "wrong password"); err == nil {
		t.Fatal("expected a failure")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.nets) != 0 {
		t.Errorf("failed network left behind: %v", f.nets)
	}
}

func TestWifiConnectKnownKeepsNetwork(t *testing.T) {
	f := startFakeWPA(t, map[string]map[string]string{"0": {"ssid": "686f6d65", "psk": `"old password"`}})
	if err := wifiConnect("wlan0", "home", ""); err == nil {
		t.Fatal("expected the stale password to fail")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if _, ok := f.nets["0"]; !ok {
		t.Error("a known network was removed after a failed join")
	}
}

func TestWifiConnectTimeout(t *testing.T) {
	f := startFakeWPA(t, map[string]map[string]string{})
	f.mu.Lock()
	f.attached = nil
	f.mu.Unlock()
	ev, err := dialWPA("wlan0")
	if err != nil {
		t.Fatal(err)
	}
	defer ev.Close()
	if err := awaitAssociation(ev, 50*time.Millisecond); err == nil {
		t.Error("expected a timeout")
	}
}

func TestUnescapeSSID(t *testing.T) {
	cases := map[string]string{
		`plain`:       "plain",
		`caf\xc3\xa9`: "café",
		`a\"b\\c`:     `a"b\c`,
		`tab\there`:   "tab\there",
		`bad\xzz`:     `bad\xzz`,
		`trailing\`:   `trailing\`,
	}
	for in, want := range cases {
		if got := unescapeSSID(in); got != want {
			t.Errorf("unescapeSSID(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSignalFrac(t *testing.T) {
	cases := []struct {
		level int
		want  float64
	}{
		{-30, 1}, {-90, 0}, {-60, 0.5}, {-20, 1}, {-100, 0},
		{0, 0}, {40, 0.5}, {80, 1}, {120, 1},
	}
	for _, c := range cases {
		if got := signalFrac(c.level); got != c.want {
			t.Errorf("signalFrac(%d) = %v, want %v", c.level, got, c.want)
		}
	}
}

func TestMediaSpeed(t *testing.T) {
	cases := map[string]int{
		"\tmedia: Ethernet autoselect (1000baseT <full-duplex>)\n":  1000,
		"\tmedia: Ethernet autoselect (2500Base-T <full-duplex>)\n": 2500,
		"\tmedia: Ethernet 10Gbase-T <full-duplex>\n":               10000,
		"\tmedia: Ethernet autoselect\n":                            0,
	}
	for in, want := range cases {
		if got := mediaSpeed(in); got != want {
			t.Errorf("mediaSpeed(%q) = %d, want %d", in, got, want)
		}
	}
}

func TestPskValue(t *testing.T) {
	if v, err := pskValue(`pa"ss word`); err != nil || v != `"pa"ss word"` {
		t.Errorf("passphrase: %q, %v", v, err)
	}
	hexKey := "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
	if v, err := pskValue(hexKey); err != nil || v != hexKey {
		t.Errorf("hex key: %q, %v", v, err)
	}
	for _, bad := range []string{"short", "line\nbreak!", string(make([]byte, 64))} {
		if _, err := pskValue(bad); err == nil {
			t.Errorf("pskValue(%q) should fail", bad)
		}
	}
}

func TestFillNetworks(t *testing.T) {
	scan := parseScanResults("bssid / frequency / signal level / flags / ssid\n" +
		"aa:bb:cc:dd:ee:01\t2412\t40\t[WPA2-PSK-CCMP][ESS]\thome\n" +
		"aa:bb:cc:dd:ee:02\t5180\t60\t[WPA2-PSK-CCMP][ESS]\thome\n" +
		"aa:bb:cc:dd:ee:03\t2437\t70\t[ESS]\tcafe\n" +
		"aa:bb:cc:dd:ee:04\t2462\t50\t[WPA2-PSK-CCMP][ESS]\t\n")
	known := parseListNetworks("network id / ssid / bssid / flags\n0\thome\tany\t[CURRENT]\n")
	status := parseKV("bssid=aa:bb:cc:dd:ee:01\nssid=home\nwpa_state=COMPLETED\n")

	st := wifiStatus{}
	fillNetworks(&st, status, scan, known)
	if st.SSID != "home" || st.Signal != 0.5 {
		t.Errorf("link = %q at %v, want home at 0.5", st.SSID, st.Signal)
	}
	if len(st.Networks) != 2 {
		t.Fatalf("got %d networks, want 2 (hidden one skipped, home merged)", len(st.Networks))
	}
	cafe, home := st.Networks[0], st.Networks[1]
	if cafe.SSID != "cafe" || cafe.Secured || cafe.Known || cafe.Connected {
		t.Errorf("cafe = %+v", cafe)
	}
	if home.SSID != "home" || !home.Secured || !home.Known || !home.Connected || home.Signal != 0.75 {
		t.Errorf("home = %+v", home)
	}
}
