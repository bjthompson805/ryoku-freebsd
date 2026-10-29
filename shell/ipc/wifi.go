package main

// wifi is the network backend for the QML surfaces (bar icon, Link, the
// network popout, the Hub's Wi-Fi tab), on FreeBSD's wpa_supplicant. It talks
// to the control socket directly, as wpa_cli does, so a password never sits
// in a process argument list. The socket is reachable by wheel through
// ctrl_interface_group in /etc/wpa_supplicant.conf, which install.sh sets up.
// It runs in the client process, not the daemon, so the Hub can use it too.
//
//	ryoku-shell wifi status          one JSON line: radio, link, networks
//	ryoku-shell wifi watch           a JSON line now and on every change
//	ryoku-shell wifi scan
//	ryoku-shell wifi connect [-p] <ssid>
//	                                 -p reads the password from stdin
//	ryoku-shell wifi disconnect
//	ryoku-shell wifi radio on|off    ifconfig up/down, through ryoku-priv

import (
	"bufio"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

const privPath = "/usr/local/libexec/ryoku-priv"

// wpaCtrlDir is a variable so the tests can stand up a fake supplicant.
var wpaCtrlDir = "/var/run/wpa_supplicant"

type wifiNet struct {
	SSID      string  `json:"ssid"`
	Signal    float64 `json:"signal"`
	Secured   bool    `json:"secured"`
	Known     bool    `json:"known"`
	Connected bool    `json:"connected"`
}

type wifiStatus struct {
	// Iface is the first wlan interface, "" when there is none.
	Iface string `json:"iface"`
	// Radio is whether that interface is up.
	Radio bool `json:"radio"`
	// Route is the default route's interface, Wired is set when that is not
	// Wi-Fi, with Speed in Mb/s (0 when the media line names none).
	Route    string    `json:"route"`
	Wired    bool      `json:"wired"`
	Speed    int       `json:"speed"`
	SSID     string    `json:"ssid"`
	Signal   float64   `json:"signal"`
	Networks []wifiNet `json:"networks"`
}

func runWifi(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: ryoku-shell wifi <status|watch|scan|connect [-p] <ssid>|disconnect|radio on|off>")
		return 2
	}
	var err error
	switch args[0] {
	case "status":
		err = printStatus()
	case "watch":
		err = watchWifi()
	case "scan":
		err = wpaOneShot("SCAN")
	case "disconnect":
		err = wpaOneShot("DISCONNECT")
	case "connect":
		withPw := len(args) > 1 && args[1] == "-p"
		if withPw {
			args = args[1:]
		}
		if len(args) != 2 || args[1] == "" {
			err = errors.New("connect needs an ssid")
			break
		}
		pw := ""
		if withPw {
			line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
			pw = strings.TrimRight(line, "\r\n")
		}
		err = wifiConnect(wlanIface(), args[1], pw)
	case "radio":
		if len(args) != 2 || (args[1] != "on" && args[1] != "off") {
			err = errors.New("radio needs on or off")
			break
		}
		err = privCmd("wifi", args[1]).Run()
	default:
		err = fmt.Errorf("unknown wifi command %q", args[0])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-shell wifi:", err)
		return 1
	}
	return 0
}

// privCmd runs ryoku-priv through whichever of doas or sudo is installed;
// install.sh grants that one file without a password for either.
func privCmd(args ...string) *exec.Cmd {
	if _, err := exec.LookPath("doas"); err == nil {
		return exec.Command("doas", append([]string{"-n", privPath}, args...)...)
	}
	return exec.Command("sudo", append([]string{"-n", privPath}, args...)...)
}

// ---- control socket ---------------------------------------------------------

var wpaSeq atomic.Int64

type wpaConn struct {
	c     *net.UnixConn
	local string
}

// dialWPA opens a datagram socket to the interface's control socket. The
// supplicant replies to our bound address, so it needs a path of its own.
func dialWPA(iface string) (*wpaConn, error) {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	local := filepath.Join(dir, fmt.Sprintf("ryoku-wpa-%d-%d", os.Getpid(), wpaSeq.Add(1)))
	_ = os.Remove(local)
	c, err := net.DialUnix("unixgram",
		&net.UnixAddr{Name: local, Net: "unixgram"},
		&net.UnixAddr{Name: filepath.Join(wpaCtrlDir, iface), Net: "unixgram"})
	if err != nil {
		return nil, fmt.Errorf("wpa_supplicant not reachable on %s: %w", iface, err)
	}
	return &wpaConn{c: c, local: local}, nil
}

func (w *wpaConn) Close() {
	w.c.Close()
	os.Remove(w.local)
}

// cmd sends one request and returns its reply, skipping any unsolicited
// event ("<N>...") an attached socket receives in between.
func (w *wpaConn) cmd(req string) (string, error) {
	_ = w.c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := w.c.Write([]byte(req)); err != nil {
		return "", err
	}
	buf := make([]byte, 65536)
	for {
		n, err := w.c.Read(buf)
		if err != nil {
			return "", err
		}
		if n > 0 && buf[0] == '<' {
			continue
		}
		return string(buf[:n]), nil
	}
}

// ok sends a request whose only good answer is OK.
func (w *wpaConn) ok(req string) error {
	r, err := w.cmd(req)
	if err != nil {
		return err
	}
	if strings.TrimSpace(r) != "OK" {
		return fmt.Errorf("%s: %s", strings.Fields(req)[0], strings.TrimSpace(r))
	}
	return nil
}

// event waits for the next unsolicited message on an attached socket.
func (w *wpaConn) event(deadline time.Time) (string, error) {
	_ = w.c.SetDeadline(deadline)
	buf := make([]byte, 4096)
	n, err := w.c.Read(buf)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(buf[:n])), nil
}

func wpaOneShot(req string) error {
	iface := wlanIface()
	if iface == "" {
		return errors.New("no Wi-Fi interface")
	}
	w, err := dialWPA(iface)
	if err != nil {
		return err
	}
	defer w.Close()
	return w.ok(req)
}

// ---- parsing ----------------------------------------------------------------

type bss struct {
	bssid, ssid string
	level       int
	flags       string
}

// parseScanResults reads SCAN_RESULTS: a header line, then
// "bssid / frequency / signal level / flags / ssid" rows, tab separated.
func parseScanResults(s string) []bss {
	var out []bss
	for i, line := range strings.Split(s, "\n") {
		f := strings.SplitN(line, "\t", 5)
		if i == 0 || len(f) < 5 {
			continue
		}
		lvl, _ := strconv.Atoi(f[2])
		out = append(out, bss{bssid: f[0], level: lvl, flags: f[3], ssid: unescapeSSID(f[4])})
	}
	return out
}

// parseListNetworks maps each configured SSID to its network id, from
// LIST_NETWORKS rows "id / ssid / bssid / flags".
func parseListNetworks(s string) map[string]string {
	out := map[string]string{}
	for i, line := range strings.Split(s, "\n") {
		f := strings.Split(line, "\t")
		if i == 0 || len(f) < 2 {
			continue
		}
		out[unescapeSSID(f[1])] = f[0]
	}
	return out
}

// parseKV reads STATUS's key=value lines.
func parseKV(s string) map[string]string {
	out := map[string]string{}
	for _, line := range strings.Split(s, "\n") {
		if k, v, ok := strings.Cut(line, "="); ok {
			out[k] = v
		}
	}
	return out
}

// unescapeSSID undoes wpa_supplicant's printf_encode: \\, \", \e, \n, \r, \t
// and \xNN.
func unescapeSSID(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' || i+1 >= len(s) {
			b.WriteByte(s[i])
			continue
		}
		i++
		switch s[i] {
		case 'n':
			b.WriteByte('\n')
		case 'r':
			b.WriteByte('\r')
		case 't':
			b.WriteByte('\t')
		case 'e':
			b.WriteByte(0x1b)
		case 'x':
			if i+2 < len(s) {
				if v, err := strconv.ParseUint(s[i+1:i+3], 16, 8); err == nil {
					b.WriteByte(byte(v))
					i += 2
					continue
				}
			}
			b.WriteString(`\x`)
		default:
			b.WriteByte(s[i])
		}
	}
	return b.String()
}

// signalFrac maps a scan level to 0..1. A negative level is dBm (-90 to -30);
// FreeBSD's driver reports net80211's RSSI instead, the signal over the noise
// floor in half dB, where 80 (40 dB) is excellent.
func signalFrac(level int) float64 {
	var f float64
	if level < 0 {
		f = float64(level+90) / 60
	} else {
		f = float64(level) / 80
	}
	return max(0, min(1, f))
}

func securedFlags(flags string) bool {
	for _, k := range []string{"WPA", "RSN", "WEP", "SAE", "EAP"} {
		if strings.Contains(flags, k) {
			return true
		}
	}
	return false
}

var mediaSpeedRE = regexp.MustCompile(`media:.*?(\d+)(G?)[Bb]ase`)

// mediaSpeed reads the link speed in Mb/s from ifconfig's media line.
func mediaSpeed(ifconfigOut string) int {
	m := mediaSpeedRE.FindStringSubmatch(ifconfigOut)
	if m == nil {
		return 0
	}
	n, _ := strconv.Atoi(m[1])
	if m[2] == "G" {
		n *= 1000
	}
	return n
}

// ---- status -----------------------------------------------------------------

func wlanIface() string {
	ifs, _ := net.Interfaces()
	var names []string
	for _, i := range ifs {
		if strings.HasPrefix(i.Name, "wlan") {
			names = append(names, i.Name)
		}
	}
	sort.Strings(names)
	if len(names) == 0 {
		return ""
	}
	return names[0]
}

func defaultRouteIface() string {
	out, err := exec.Command("route", "-n", "get", "default").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		if k, v, ok := strings.Cut(strings.TrimSpace(line), ":"); ok && k == "interface" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// routeInfo is the part of the status that only changes with the routing
// table, so watch recomputes it on routing messages rather than every tick.
type routeInfo struct {
	iface string
	speed int
}

func readRoute() routeInfo {
	r := routeInfo{iface: defaultRouteIface()}
	if r.iface != "" && !strings.HasPrefix(r.iface, "wlan") {
		if out, err := exec.Command("ifconfig", r.iface).Output(); err == nil {
			r.speed = mediaSpeed(string(out))
		}
	}
	return r
}

func readStatus(r routeInfo) wifiStatus {
	st := wifiStatus{Route: r.iface, Networks: []wifiNet{}}
	st.Wired = r.iface != "" && !strings.HasPrefix(r.iface, "wlan")
	if st.Wired {
		st.Speed = r.speed
	}
	st.Iface = wlanIface()
	if st.Iface == "" {
		return st
	}
	if i, err := net.InterfaceByName(st.Iface); err == nil {
		st.Radio = i.Flags&net.FlagUp != 0
	}
	w, err := dialWPA(st.Iface)
	if err != nil {
		return st
	}
	defer w.Close()
	status, _ := w.cmd("STATUS")
	scan, _ := w.cmd("SCAN_RESULTS")
	list, _ := w.cmd("LIST_NETWORKS")
	fillNetworks(&st, parseKV(status), parseScanResults(scan), parseListNetworks(list))
	return st
}

// fillNetworks folds the supplicant's replies into the status: one row per
// SSID at its strongest access point, strongest first, hidden ones skipped.
func fillNetworks(st *wifiStatus, status map[string]string, scan []bss, known map[string]string) {
	if status["wpa_state"] == "COMPLETED" {
		st.SSID = unescapeSSID(status["ssid"])
	}
	best := map[string]int{}
	for _, b := range scan {
		if b.ssid == "" {
			continue
		}
		sig := signalFrac(b.level)
		if st.SSID != "" && strings.EqualFold(b.bssid, status["bssid"]) {
			st.Signal = sig
		}
		if i, ok := best[b.ssid]; ok {
			if sig > st.Networks[i].Signal {
				st.Networks[i].Signal = sig
			}
			continue
		}
		_, isKnown := known[b.ssid]
		best[b.ssid] = len(st.Networks)
		st.Networks = append(st.Networks, wifiNet{
			SSID:      b.ssid,
			Signal:    sig,
			Secured:   securedFlags(b.flags),
			Known:     isKnown,
			Connected: b.ssid == st.SSID,
		})
	}
	sort.SliceStable(st.Networks, func(i, j int) bool { return st.Networks[i].Signal > st.Networks[j].Signal })
}

func printStatus() error {
	b, err := json.Marshal(readStatus(readRoute()))
	if err != nil {
		return err
	}
	fmt.Println(string(b))
	return nil
}

// watchWifi prints the status on start and again whenever it changes. The
// routing socket wakes it on link and route changes, the supplicant's event
// stream on scans and association, and a slow tick catches signal drift.
func watchWifi() error {
	wake := make(chan struct{}, 1)
	poke := func() {
		select {
		case wake <- struct{}{}:
		default:
		}
	}
	routeWake := make(chan struct{}, 1)

	go func() {
		fd, err := syscall.Socket(syscall.AF_ROUTE, syscall.SOCK_RAW, syscall.AF_UNSPEC)
		if err != nil {
			return
		}
		buf := make([]byte, 4096)
		for {
			if _, err := syscall.Read(fd, buf); err != nil {
				return
			}
			select {
			case routeWake <- struct{}{}:
			default:
			}
			poke()
		}
	}()

	go func() {
		for {
			iface := wlanIface()
			if iface != "" {
				if w, err := dialWPA(iface); err == nil {
					if w.ok("ATTACH") == nil {
						for {
							if _, err := w.event(time.Now().Add(time.Minute)); err != nil {
								var ne net.Error
								if errors.As(err, &ne) && ne.Timeout() {
									continue
								}
								break
							}
							poke()
						}
					}
					w.Close()
				}
			}
			time.Sleep(10 * time.Second)
		}
	}()

	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	route := readRoute()
	last := ""
	out := bufio.NewWriter(os.Stdout)
	for {
		b, err := json.Marshal(readStatus(route))
		if err != nil {
			return err
		}
		if s := string(b); s != last {
			last = s
			fmt.Fprintln(out, s)
			if err := out.Flush(); err != nil {
				return err
			}
		}
		select {
		case <-wake:
		case <-tick.C:
		}
		// let a burst of routing or supplicant messages settle into one read.
		time.Sleep(150 * time.Millisecond)
		select {
		case <-routeWake:
			route = readRoute()
		default:
		}
	}
}

// ---- connect ----------------------------------------------------------------

// pskValue renders a password for SET_NETWORK psk: a quoted passphrase of
// 8 to 63 printable ASCII characters, or a raw 64-digit hex key.
func pskValue(pw string) (string, error) {
	if len(pw) == 64 {
		if _, err := hex.DecodeString(pw); err == nil {
			return pw, nil
		}
	}
	if len(pw) < 8 || len(pw) > 63 {
		return "", errors.New("a WPA password is 8 to 63 characters")
	}
	for i := 0; i < len(pw); i++ {
		if pw[i] < 0x20 || pw[i] > 0x7e {
			return "", errors.New("a WPA password is printable ASCII")
		}
	}
	return `"` + pw + `"`, nil
}

// wifiConnect joins ssid, adding a network for it unless one is configured,
// and waits for the association. A new network that fails is removed again,
// so a wrong password does not leave it looking known. SELECT_NETWORK
// disables every other network, so they are re-enabled either way before the
// config is saved.
func wifiConnect(iface, ssid, pw string) error {
	if iface == "" {
		return errors.New("no Wi-Fi interface")
	}
	w, err := dialWPA(iface)
	if err != nil {
		return err
	}
	defer w.Close()
	ev, err := dialWPA(iface)
	if err != nil {
		return err
	}
	defer ev.Close()
	if err := ev.ok("ATTACH"); err != nil {
		return err
	}

	list, err := w.cmd("LIST_NETWORKS")
	if err != nil {
		return err
	}
	id, known := parseListNetworks(list)[ssid]
	if !known {
		r, err := w.cmd("ADD_NETWORK")
		if err != nil {
			return err
		}
		id = strings.TrimSpace(r)
		if _, err := strconv.Atoi(id); err != nil {
			return fmt.Errorf("ADD_NETWORK: %s", id)
		}
		if err := w.ok("SET_NETWORK " + id + " ssid " + hex.EncodeToString([]byte(ssid))); err != nil {
			w.ok("REMOVE_NETWORK " + id)
			return err
		}
		if pw == "" {
			err = w.ok("SET_NETWORK " + id + " key_mgmt NONE")
		}
		if err != nil {
			w.ok("REMOVE_NETWORK " + id)
			return err
		}
	}
	if pw != "" {
		v, err := pskValue(pw)
		if err == nil {
			err = w.ok("SET_NETWORK " + id + " psk " + v)
		}
		if err != nil {
			if !known {
				w.ok("REMOVE_NETWORK " + id)
			}
			return err
		}
	}
	if err := w.ok("SELECT_NETWORK " + id); err != nil {
		return err
	}

	joinErr := awaitAssociation(ev, 30*time.Second)
	if joinErr != nil && !known {
		w.ok("REMOVE_NETWORK " + id)
	}
	w.ok("ENABLE_NETWORK all")
	w.ok("SAVE_CONFIG")
	return joinErr
}

// awaitAssociation reads supplicant events until the link is up or an
// attempt is rejected.
func awaitAssociation(ev *wpaConn, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		msg, err := ev.event(deadline)
		if err != nil {
			return errors.New("timed out joining the network")
		}
		switch {
		case strings.Contains(msg, "CTRL-EVENT-CONNECTED"):
			return nil
		case strings.Contains(msg, "WRONG_KEY"),
			strings.Contains(msg, "CTRL-EVENT-SSID-TEMP-DISABLED"),
			strings.Contains(msg, "CTRL-EVENT-ASSOC-REJECT"),
			strings.Contains(msg, "CTRL-EVENT-AUTH-REJECT"):
			return errors.New("could not join: " + msg)
		}
	}
}
