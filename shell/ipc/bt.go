package main

// bt is the Bluetooth backend for the QML surfaces (bar icon, Link, the
// Bluetooth popout, the launcher's device cards, the Hub's Bluetooth tab),
// on FreeBSD's own stack: hccontrol for the adapter, links and scans,
// sdpcontrol to learn what a device offers, and ryoku-priv for everything
// that writes root's config (pairing, virtual_oss audio, bthidd input).
// It runs in the client process, like wifi, so the Hub can use it too.
//
//	ryoku-shell bt status           one JSON line: adapter and devices
//	ryoku-shell bt watch            a JSON line now and on every change
//	ryoku-shell bt scan             a ten-second inquiry, names included
//	ryoku-shell bt pair <addr>      remember the device, then connect it
//	ryoku-shell bt connect <addr>
//	ryoku-shell bt disconnect <addr>
//	ryoku-shell bt forget <addr>
//	ryoku-shell bt power on|off
//
// A device is paired when /etc/bluetooth/hosts names it: ryoku-priv writes
// that line together with the hcsecd.conf block that does the pairing.
// Connecting means starting whichever service carries the device: a
// virtual_oss profile for audio, bthidd for keyboards and mice. Those
// outlive a reboot, so a paired headset comes back on its own when it is
// switched on, and watch keeps a PipeWire sink for every running profile.

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// sigZero probes whether a process exists without signalling it.
const sigZero = syscall.Signal(0)

// Variables so the tests can point them at fixtures.
var (
	btHostsPath = "/etc/bluetooth/hosts"
	btOffPath   = "/var/run/ryoku-bt.off"
	btDevGlob   = "/dev/dsp.bt*"
)

type btDevice struct {
	Address   string `json:"address"`
	Name      string `json:"name"`
	Paired    bool   `json:"paired"`
	Connected bool   `json:"connected"`
	// Kind is "audio", "input", "phone", "computer" or "", from the class
	// of device a scan saw or the services SDP listed.
	Kind string `json:"kind"`
	// Icon is a freedesktop device icon name, the vocabulary the surfaces
	// already map to glyphs and art.
	Icon string `json:"icon"`
}

type btStatus struct {
	// Present is whether there is an adapter, Enabled whether its driver
	// is attached (ryoku-priv bt power off detaches it).
	Present     bool       `json:"present"`
	Enabled     bool       `json:"enabled"`
	Discovering bool       `json:"discovering"`
	Address     string     `json:"address"`
	Devices     []btDevice `json:"devices"`
}

// btSeen is what a scan or an SDP query learned about one device, kept in
// the cache so a paired device keeps its icon while it is out of range.
type btSeen struct {
	Name  string `json:"name,omitempty"`
	Class uint32 `json:"class,omitempty"`
	Kind  string `json:"kind,omitempty"`
	// Seen is when a scan last found it, for listing unpaired devices.
	Seen int64 `json:"seen,omitempty"`
}

var (
	btAddrRe    = regexp.MustCompile(`^[0-9a-f]{2}(:[0-9a-f]{2}){5}$`)
	btProfileRe = regexp.MustCompile(`^bt[0-9a-f]{6}$`)
)

func runBt(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: ryoku-shell bt <status|watch|scan|pair|connect|disconnect|forget <addr>|power on|off>")
		return 2
	}
	var err error
	switch args[0] {
	case "status":
		var b []byte
		if b, err = json.Marshal(readBtStatus()); err == nil {
			fmt.Println(string(b))
		}
	case "watch":
		err = watchBt()
	case "scan":
		err = btScan()
	case "pair", "connect", "disconnect", "forget":
		if len(args) != 2 {
			err = fmt.Errorf("%s needs an address", args[0])
			break
		}
		addr := strings.ToLower(args[1])
		if !btAddrRe.MatchString(addr) {
			err = fmt.Errorf("not a Bluetooth address: %s", args[1])
			break
		}
		switch args[0] {
		case "pair":
			err = btPair(addr)
		case "connect":
			err = btConnect(addr)
		case "disconnect":
			err = btDisconnect(addr)
		case "forget":
			err = btPriv("forget", addr)
		}
	case "power":
		if len(args) != 2 || (args[1] != "on" && args[1] != "off") {
			err = errors.New("power needs on or off")
			break
		}
		err = btPriv("power", args[1])
	default:
		err = fmt.Errorf("unknown bt command %q", args[0])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ryoku-shell bt:", err)
		return 1
	}
	return 0
}

func btPriv(args ...string) error {
	out, err := privCmd(append([]string{"bt"}, args...)...).CombinedOutput()
	return privErr(out, err)
}

// ---- state ------------------------------------------------------------------

func btCacheDir() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return d
	}
	return filepath.Join(os.TempDir(), fmt.Sprintf("ryoku-%d", os.Getuid()))
}

// The seen cache lives in the user's cache dir so icons survive a reboot;
// the scan lock is runtime state.
func btSeenPath() string {
	d, err := os.UserCacheDir()
	if err != nil {
		d = btCacheDir()
	}
	return filepath.Join(d, "ryoku", "bt-seen.json")
}

func btScanLock() string { return filepath.Join(btCacheDir(), "ryoku-bt-scan.pid") }

func loadBtSeen() map[string]btSeen {
	m := map[string]btSeen{}
	if b, err := os.ReadFile(btSeenPath()); err == nil {
		_ = json.Unmarshal(b, &m)
	}
	return m
}

func saveBtSeen(m map[string]btSeen) error {
	p := btSeenPath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

func updateBtSeen(addr string, f func(*btSeen)) {
	m := loadBtSeen()
	s := m[addr]
	f(&s)
	m[addr] = s
	_ = saveBtSeen(m)
}

// parseBtHosts reads hosts(5)-style lines, address then name and aliases,
// into address -> display name. Underscores stand in for spaces there.
func parseBtHosts(s string) map[string]string {
	m := map[string]string{}
	for _, line := range strings.Split(s, "\n") {
		if i := strings.IndexByte(line, '#'); i >= 0 {
			line = line[:i]
		}
		f := strings.Fields(line)
		if len(f) < 2 || !btAddrRe.MatchString(strings.ToLower(f[0])) {
			continue
		}
		m[strings.ToLower(f[0])] = strings.ReplaceAll(f[1], "_", " ")
	}
	return m
}

// parseBtNodes takes the first HCI node from `hccontrol read_node_list`.
func parseBtNodes(s string) string {
	for _, line := range strings.Split(s, "\n") {
		f := strings.Fields(line)
		if len(f) > 0 && strings.HasSuffix(f[0], "hci") {
			return f[0]
		}
	}
	return ""
}

// parseBtLinks takes the open ACL links from `hccontrol -N
// read_connection_list`.
func parseBtLinks(s string) map[string]bool {
	m := map[string]bool{}
	for _, line := range strings.Split(s, "\n") {
		f := strings.Fields(line)
		if len(f) >= 9 && btAddrRe.MatchString(strings.ToLower(f[0])) &&
			f[2] == "ACL" && f[len(f)-1] == "OPEN" {
			m[strings.ToLower(f[0])] = true
		}
	}
	return m
}

// btKindForClass reads the major device class out of a class of device.
func btKindForClass(c uint32) string {
	switch (c >> 8) & 0x1f {
	case 1:
		return "computer"
	case 2:
		return "phone"
	case 4:
		return "audio"
	case 5:
		return "input"
	}
	return ""
}

// btIcon picks a freedesktop icon name, the minor class telling a
// keyboard from a mouse and headphones from a speaker.
func btIcon(kind string, c uint32) string {
	minor := (c >> 2) & 0x3f
	switch kind {
	case "audio":
		switch minor {
		case 1, 2, 6:
			return "audio-headset"
		case 5, 7:
			return "audio-speakers"
		}
		if c == 0 {
			return "audio-headset"
		}
		return "audio-card"
	case "input":
		switch {
		case minor&0x30 == 0x10:
			return "input-keyboard"
		case minor&0x30 == 0x20:
			return "input-mouse"
		case minor&0x0f == 1 || minor&0x0f == 2:
			return "input-gaming"
		}
		return "input-keyboard"
	case "phone":
		return "phone"
	case "computer":
		return "computer"
	}
	return "bluetooth"
}

func btNode() string {
	out, err := exec.Command("hccontrol", "read_node_list").Output()
	if err != nil {
		return ""
	}
	return parseBtNodes(string(out))
}

func btScanning() bool {
	b, err := os.ReadFile(btScanLock())
	if err != nil {
		return false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return false
	}
	p, err := os.FindProcess(pid)
	return err == nil && p.Signal(sigZero) == nil
}

// btSeenWindow is how long an unpaired device a scan found stays listed.
const btSeenWindow = 2 * time.Minute

func readBtStatus() btStatus {
	st := btStatus{Devices: []btDevice{}}
	node := btNode()
	_, offErr := os.Stat(btOffPath)
	st.Present = node != "" || offErr == nil
	st.Enabled = node != ""
	if !st.Enabled {
		return st
	}
	st.Discovering = btScanning()
	if out, err := exec.Command("hccontrol", "-N", "-n", node, "read_bd_addr").Output(); err == nil {
		st.Address = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(string(out)), "BD_ADDR:")))
	}
	links := map[string]bool{}
	if out, err := exec.Command("hccontrol", "-N", "-n", node, "read_connection_list").Output(); err == nil {
		links = parseBtLinks(string(out))
	}
	hosts := ""
	if b, err := os.ReadFile(btHostsPath); err == nil {
		hosts = string(b)
	}
	st.Devices = buildBtDevices(parseBtHosts(hosts), links, loadBtSeen(), time.Now())
	return st
}

// buildBtDevices lists every paired device, then the unpaired ones a recent
// scan found: connected first, then by name.
func buildBtDevices(paired map[string]string, links map[string]bool, seen map[string]btSeen, now time.Time) []btDevice {
	devs := []btDevice{}
	add := func(addr, name string, isPaired bool) {
		s := seen[addr]
		if name == "" {
			name = s.Name
		}
		kind := s.Kind
		if kind == "" {
			kind = btKindForClass(s.Class)
		}
		devs = append(devs, btDevice{
			Address:   addr,
			Name:      name,
			Paired:    isPaired,
			Connected: links[addr],
			Kind:      kind,
			Icon:      btIcon(kind, s.Class),
		})
	}
	for addr, name := range paired {
		add(addr, name, true)
	}
	for addr, s := range seen {
		if _, ok := paired[addr]; ok {
			continue
		}
		if s.Seen > 0 && now.Sub(time.Unix(s.Seen, 0)) < btSeenWindow {
			add(addr, "", false)
		}
	}
	sort.SliceStable(devs, func(i, j int) bool {
		if devs[i].Connected != devs[j].Connected {
			return devs[i].Connected
		}
		if devs[i].Paired != devs[j].Paired {
			return devs[i].Paired
		}
		return strings.ToLower(devs[i].Name) < strings.ToLower(devs[j].Name)
	})
	return devs
}

// ---- watch ------------------------------------------------------------------

// watchBt prints the status on start and on every change. hccontrol has no
// event stream for an unprivileged reader, so it polls: quickly while a
// scan runs, every few seconds otherwise. Each pass also keeps PipeWire's
// sinks in step with the running virtual_oss profiles.
func watchBt() error {
	last := ""
	out := bufio.NewWriter(os.Stdout)
	asked := map[string]bool{}
	for {
		st := readBtStatus()
		if btLearnKinds(st, asked) {
			st = readBtStatus()
		}
		syncBtSinks(st)
		b, err := json.Marshal(st)
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
		if st.Discovering {
			time.Sleep(time.Second)
		} else {
			time.Sleep(3 * time.Second)
		}
	}
}

// btLearnKinds asks each connected device of unknown kind over SDP, once
// per watch, so a device paired outside ryoku still gets its icon.
func btLearnKinds(st btStatus, asked map[string]bool) bool {
	learned := false
	for _, d := range st.Devices {
		if !d.Connected || d.Kind != "" || asked[d.Address] {
			continue
		}
		asked[d.Address] = true
		out, err := exec.Command("sdpcontrol", "-a", d.Address, "browse").Output()
		if err != nil {
			continue
		}
		if kind := parseBtServices(string(out)); kind != "" {
			updateBtSeen(d.Address, func(s *btSeen) { s.Kind = kind })
			learned = true
		}
	}
	return learned
}

// ---- scan -------------------------------------------------------------------

// parseBtInquiry pulls each result's address and class of device out of
// `hccontrol -N inquiry`, whose class line reads "Class: 24:04:04", most
// significant byte first.
func parseBtInquiry(s string) map[string]uint32 {
	m := map[string]uint32{}
	cur := ""
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "BD_ADDR:"):
			cur = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(line, "BD_ADDR:")))
			if btAddrRe.MatchString(cur) {
				if _, ok := m[cur]; !ok {
					m[cur] = 0
				}
			} else {
				cur = ""
			}
		case strings.HasPrefix(line, "Class:") && cur != "":
			v := strings.ReplaceAll(strings.TrimSpace(strings.TrimPrefix(line, "Class:")), ":", "")
			v = strings.TrimPrefix(v, "0x")
			if c, err := strconv.ParseUint(v, 16, 32); err == nil {
				m[cur] = uint32(c)
			}
		}
	}
	return m
}

func btScan() error {
	node := btNode()
	if node == "" {
		return errors.New("no Bluetooth adapter")
	}
	if btScanning() {
		return nil
	}
	lock := btScanLock()
	if err := os.MkdirAll(filepath.Dir(lock), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(lock, []byte(strconv.Itoa(os.Getpid())), 0o644); err != nil {
		return err
	}
	defer os.Remove(lock)

	out, err := exec.Command("hccontrol", "-N", "-n", node, "inquiry").CombinedOutput()
	if err != nil {
		return privErr(out, err)
	}
	found := parseBtInquiry(string(out))
	now := time.Now().Unix()
	m := loadBtSeen()
	for addr, class := range found {
		s := m[addr]
		s.Seen = now
		if class != 0 {
			s.Class = class
		}
		m[addr] = s
	}
	// show the addresses at once, then fill in names one by one: a name
	// request can take seconds per device.
	if err := saveBtSeen(m); err != nil {
		return err
	}
	for addr := range found {
		if name := btRemoteName(node, addr); name != "" {
			updateBtSeen(addr, func(s *btSeen) { s.Name = name })
		}
	}
	return nil
}

func btRemoteName(node, addr string) string {
	out, err := exec.Command("hccontrol", "-N", "-n", node, "remote_name_request", addr).Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		if v, ok := strings.CutPrefix(strings.TrimSpace(line), "Name:"); ok {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// ---- connect ----------------------------------------------------------------

// parseBtServices reads `sdpcontrol browse` for the services ryoku can
// carry: HID (0x1124) and an A2DP sink (0x110b).
func parseBtServices(s string) string {
	switch {
	case strings.Contains(s, "(0x1124)"):
		return "input"
	case strings.Contains(s, "(0x110b)"):
		return "audio"
	}
	return ""
}

func btPair(addr string) error {
	name := loadBtSeen()[addr].Name
	if name == "" {
		if node := btNode(); node != "" {
			name = btRemoteName(node, addr)
		}
	}
	if err := btPriv("pair", addr, name); err != nil {
		return err
	}
	// hcsecd answers the PIN request the first real connection raises, so
	// pairing finishes on the connect.
	return btConnect(addr)
}

func btConnect(addr string) error {
	out, err := exec.Command("sdpcontrol", "-a", addr, "browse").CombinedOutput()
	if err != nil {
		return fmt.Errorf("the device did not answer; is it on and in pairing mode? (%s)", strings.TrimSpace(string(out)))
	}
	kind := parseBtServices(string(out))
	if kind != "" {
		updateBtSeen(addr, func(s *btSeen) { s.Kind = kind })
	}
	switch kind {
	case "audio":
		return btPriv("audio", "on", addr)
	case "input":
		return btPriv("hid", "on", addr)
	}
	return errors.New("this device offers neither audio playback nor input, the two kinds FreeBSD can carry")
}

// btDisconnect stops whichever service carries the device. Both are
// idempotent in ryoku-priv; this only skips the one it plainly isn't.
func btDisconnect(addr string) error {
	if btProfileActive(btProfile(addr)) {
		return btPriv("audio", "off", addr)
	}
	return btPriv("hid", "off", addr)
}

// btProfile matches ryoku-priv's bt_profile: "bt" and the last six digits.
func btProfile(addr string) string {
	h := strings.ReplaceAll(addr, ":", "")
	return "bt" + h[len(h)-6:]
}

func btProfileActive(p string) bool {
	out, err := exec.Command("sysrc", "-n", "virtual_oss_configs").Output()
	if err != nil {
		return false
	}
	for _, f := range strings.Fields(string(out)) {
		if f == p {
			return true
		}
	}
	return false
}

// ---- PipeWire ---------------------------------------------------------------

// PipeWire's OSS scan only lists kernel pcm devices, so each virtual_oss
// device (/dev/dsp.btXXXXXX) gets a sink declared by hand. The sink is
// named after the profile.
func syncBtSinks(st btStatus) {
	if _, err := exec.LookPath("pw-cli"); err != nil {
		return
	}
	devs, _ := filepath.Glob(btDevGlob)
	want := btWantedSinks(devs, st)
	have := btSinks()
	names := map[string]string{}
	for _, d := range st.Devices {
		names["ryoku-"+btProfile(d.Address)] = d.Name
	}
	for node, path := range want {
		if have[node] {
			continue
		}
		desc := names[node]
		if desc == "" {
			desc = "Bluetooth audio"
		}
		if exec.Command("pw-cli", "create-node", "adapter", btSinkProps(node, desc, path)).Run() == nil {
			btSwitchTo(node)
		}
	}
	for node := range have {
		if _, ok := want[node]; !ok {
			_ = exec.Command("pw-cli", "destroy", node).Run()
		}
	}
}

// btWantedSinks maps sink names to virtual_oss devices, for the headsets
// that are connected. The profile, and so its device, stays up while the
// headset is off, and a sink left behind would keep WirePlumber choosing
// it as the default output.
func btWantedSinks(devs []string, st btStatus) map[string]string {
	connected := map[string]bool{}
	for _, d := range st.Devices {
		if d.Connected {
			connected[btProfile(d.Address)] = true
		}
	}
	want := map[string]string{}
	for _, d := range devs {
		p := strings.TrimPrefix(filepath.Base(d), "dsp.")
		if btProfileRe.MatchString(p) && connected[p] {
			want["ryoku-"+p] = d
		}
	}
	return want
}

// btSwitchTo makes a headset that just connected the default output, as
// other desktops do. When it disconnects its sink goes away and
// WirePlumber falls back to the output chosen before it. The new node
// takes a moment to register, so it retries briefly.
func btSwitchTo(node string) {
	for i := 0; i < 10; i++ {
		if exec.Command("pactl", "set-default-sink", node).Run() == nil {
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func btSinkProps(node, desc, path string) string {
	q := func(s string) string { b, _ := json.Marshal(s); return string(b) }
	return fmt.Sprintf("{ factory.name=freebsd-oss.sink node.name=%s node.description=%s "+
		"media.class=Audio/Sink api.freebsd-oss.dsp-path=%s object.linger=true }",
		q(node), q(desc), q(path))
}

// btSinks lists the sinks this backend made, from `pactl list short sinks`.
func btSinks() map[string]bool {
	m := map[string]bool{}
	out, err := exec.Command("pactl", "list", "short", "sinks").Output()
	if err != nil {
		return m
	}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 && strings.HasPrefix(f[1], "ryoku-bt") {
			m[f[1]] = true
		}
	}
	return m
}
