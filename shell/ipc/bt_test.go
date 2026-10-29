package main

import (
	"strings"
	"testing"
	"time"
)

// Captured from hccontrol on FreeBSD 15.1 with an MT7925 adapter.
const (
	btNodeList = "Name            ID       Num hooks\nubt0hci         00000007         3\n"
	btConnList = "Remote BD_ADDR    Handle Type Mode Role Encrypt Pending Queue State\n" +
		"44:5e:cd:73:95:06     51  ACL    0 MAST     P2P       1     0 OPEN\n" +
		"00:11:22:33:44:55     52  ACL    0 MAST    NONE       0     0 W4_CONN_COMPLETE\n"
	btInquiry = "Inquiry result, num_responses=2\n" +
		"Inquiry result #0\n\tBD_ADDR: 44:5E:CD:73:95:06\n\tPage Scan Rep. Mode: 0x1\n" +
		"\tPage Scan Period Mode: 00\n\tPage Scan Mode: 00\n\tClass: 24:04:04\n\tClock offset: 0x78ef\n" +
		"Inquiry result #1\n\tBD_ADDR: 00:11:22:33:44:55\n\tClass: 00:05:40\n" +
		"Inquiry complete. Status: No error [00]\n"
	btHostsFile = "# BD_ADDR\tName [ alias0 ... ]\n" +
		"# 00:11:22:33:44:55\tphone\n" +
		"44:5e:cd:73:95:06\tBlackShark_V3_Pro_Xbox_BT bs\n"
)

func TestParseBtNodes(t *testing.T) {
	if got := parseBtNodes(btNodeList); got != "ubt0hci" {
		t.Fatalf("node = %q", got)
	}
	if got := parseBtNodes("Name            ID       Num hooks\n"); got != "" {
		t.Fatalf("empty list gave %q", got)
	}
}

func TestParseBtLinks(t *testing.T) {
	got := parseBtLinks(btConnList)
	if !got["44:5e:cd:73:95:06"] || len(got) != 1 {
		t.Fatalf("links = %v, want only the open one", got)
	}
}

func TestParseBtHosts(t *testing.T) {
	got := parseBtHosts(btHostsFile)
	if len(got) != 1 || got["44:5e:cd:73:95:06"] != "BlackShark V3 Pro Xbox BT" {
		t.Fatalf("hosts = %v", got)
	}
}

func TestParseBtInquiry(t *testing.T) {
	got := parseBtInquiry(btInquiry)
	if got["44:5e:cd:73:95:06"] != 0x240404 || got["00:11:22:33:44:55"] != 0x000540 {
		t.Fatalf("inquiry = %#v", got)
	}
}

func TestBtKindAndIcon(t *testing.T) {
	for _, c := range []struct {
		class uint32
		kind  string
		icon  string
	}{
		{0x240404, "audio", "audio-headset"},  // wearable headset
		{0x240414, "audio", "audio-speakers"}, // loudspeaker
		{0x000540, "input", "input-keyboard"},
		{0x002580, "input", "input-mouse"},
		{0x002508, "input", "input-gaming"}, // gamepad
		{0x5a020c, "phone", "phone"},
		{0x000000, "", "bluetooth"},
	} {
		k := btKindForClass(c.class)
		if k != c.kind || btIcon(k, c.class) != c.icon {
			t.Errorf("class %06x: got %q %q, want %q %q", c.class, k, btIcon(k, c.class), c.kind, c.icon)
		}
	}
	// SDP alone says audio without a class; that reads as a headset.
	if got := btIcon("audio", 0); got != "audio-headset" {
		t.Errorf("classless audio icon = %q", got)
	}
}

func TestParseBtServices(t *testing.T) {
	sink := "Service Class ID List:\n\tAudio Sink (0x110b)\n"
	hid := "Service Class ID List:\n\tHuman Interface Device (0x1124)\n"
	if parseBtServices(sink) != "audio" || parseBtServices(hid) != "input" || parseBtServices("") != "" {
		t.Fatal("service kinds wrong")
	}
}

func TestBtProfile(t *testing.T) {
	// ryoku-priv derives the same name in shell; keep the two in step.
	if got := btProfile("44:5e:cd:73:95:06"); got != "bt739506" {
		t.Fatalf("profile = %q", got)
	}
	if !btProfileRe.MatchString("bt739506") || btProfileRe.MatchString("bt") {
		t.Fatal("profile pattern wrong")
	}
}

func TestBuildBtDevices(t *testing.T) {
	now := time.Unix(10_000, 0)
	paired := map[string]string{"44:5e:cd:73:95:06": "Headset", "aa:aa:aa:aa:aa:aa": "Keyboard"}
	links := map[string]bool{"aa:aa:aa:aa:aa:aa": true}
	seen := map[string]btSeen{
		"44:5e:cd:73:95:06": {Kind: "audio"},
		"00:11:22:33:44:55": {Name: "Fresh", Class: 0x000540, Seen: now.Unix() - 30},
		"66:66:66:66:66:66": {Name: "Stale", Seen: now.Unix() - 600},
	}
	got := buildBtDevices(paired, links, seen, now)
	var names []string
	for _, d := range got {
		names = append(names, d.Name)
	}
	if strings.Join(names, ",") != "Keyboard,Headset,Fresh" {
		t.Fatalf("order = %v", names)
	}
	if !got[0].Connected || got[1].Icon != "audio-headset" || got[2].Paired || got[2].Icon != "input-keyboard" {
		t.Fatalf("devices = %+v", got)
	}
}

func TestBtSinkProps(t *testing.T) {
	got := btSinkProps("ryoku-bt739506", `Head "set"`, "/dev/dsp.bt739506")
	if !strings.Contains(got, `node.description="Head \"set\""`) ||
		!strings.Contains(got, `api.freebsd-oss.dsp-path="/dev/dsp.bt739506"`) {
		t.Fatalf("props = %s", got)
	}
}
