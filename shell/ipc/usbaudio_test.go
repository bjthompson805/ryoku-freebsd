package main

import "testing"

func ossNode(index int, name, parent string, monitor bool) pulseNode {
	p := map[string]string{"device.api": "freebsd-oss", "api.freebsd-oss.pcm-parent": parent}
	if monitor {
		p["device.class"] = "monitor"
	}
	return pulseNode{Index: index, Name: name, Properties: p}
}

func TestParseSinkEvent(t *testing.T) {
	cases := []struct {
		in    string
		ok    bool
		index int
		added bool
	}{
		{"Event 'new' on sink #566", true, 566, true},
		{"Event 'change' on sink #566", true, 566, false},
		{"Event 'remove' on sink #12", true, 12, false},
		{"Event 'new' on sink-input #90", false, 0, false},
		{"Event 'change' on source #566", false, 0, false},
		{"Event 'new' on client #1726", false, 0, false},
		{"garbage", false, 0, false},
	}
	for _, c := range cases {
		e, ok := parseSinkEvent(c.in)
		if ok != c.ok || e.index != c.index || e.added != c.added {
			t.Errorf("parseSinkEvent(%q) = %+v, %v", c.in, e, ok)
		}
	}
}

func TestParsePulseNodes(t *testing.T) {
	in := `[{"index":566,"name":"pcm5.play","properties":{"device.api":"freebsd-oss",
		"api.freebsd-oss.pcm-parent":"uaudio0","object.id":"153"}}]`
	ns := parsePulseNodes([]byte(in))
	if len(ns) != 1 || !ns[0].isUSB() || ns[0].Properties["object.id"] != "153" {
		t.Fatalf("parsePulseNodes = %+v", ns)
	}
	if parsePulseNodes([]byte("not json")) != nil {
		t.Fatal("bad json must yield nothing")
	}
}

func TestPickUSBDefaults(t *testing.T) {
	sinks := []pulseNode{
		ossNode(48, "pcm3.play", "hdaa1", false),
		ossNode(566, "pcm5.play", "uaudio0", false),
		ossNode(568, "pcm6.play", "uaudio0", false),
	}
	sources := []pulseNode{
		ossNode(48, "pcm3.play.monitor", "hdaa1", true),
		ossNode(49, "pcm3.rec", "hdaa1", false),
		ossNode(566, "pcm5.play.monitor", "uaudio0", true),
		ossNode(567, "pcm5.rec", "uaudio0", false),
		ossNode(568, "pcm6.play.monitor", "uaudio0", true),
	}

	// the dongle's chat pcm arriving first still picks the output paired
	// with the microphone.
	if s, r := pickUSBDefaults([]int{568, 566}, sinks, sources); s != "pcm5.play" || r != "pcm5.rec" {
		t.Errorf("headset: got %q, %q", s, r)
	}
	// a sink that is not USB never switches.
	if s, r := pickUSBDefaults([]int{48}, sinks, sources); s != "" || r != "" {
		t.Errorf("internal: got %q, %q", s, r)
	}
	// nothing added, nothing to do.
	if s, r := pickUSBDefaults(nil, sinks, sources); s != "" || r != "" {
		t.Errorf("none: got %q, %q", s, r)
	}
	// playback-only USB device: its sink, no source.
	dac := []pulseNode{ossNode(700, "pcm7.play", "uaudio1", false)}
	if s, r := pickUSBDefaults([]int{700}, dac, sources); s != "pcm7.play" || r != "" {
		t.Errorf("dac: got %q, %q", s, r)
	}
}

func TestMasterVolumeTarget(t *testing.T) {
	dump := func(vol, ch, soft string) []byte {
		return []byte(`[{"id":153,"info":{"params":{"Props":[{"volume":` + vol + `,"channelVolumes":` + ch +
			`,"softVolumes":` + soft + `},{"latencyOffsetNsec":0}]}}}]`)
	}
	cases := []struct {
		name, vol, ch, soft, want string
	}{
		{"volume changed", "1.0", "[0.024389,0.024389]", "[1.0,1.0]", "{ volume: 0.024389 }"},
		{"already mirrored (else it loops)", "0.024389", "[0.024389,0.024389]", "[1.0,1.0]", ""},
		{"loudest channel", "1.0", "[0.1,0.3]", "[1.0,1.0]", "{ volume: 0.300000 }"},
		{"old soft mirror cleared", "1.0", "[0.125,0.125]", "[0.125,0.125]",
			"{ volume: 0.125000, softVolumes: [ 1.0, 1.0 ] }"},
		{"old soft mirror, master right", "0.125", "[0.125,0.125]", "[0.125,0.125]",
			"{ volume: 0.125000, softVolumes: [ 1.0, 1.0 ] }"},
	}
	for _, c := range cases {
		if got := masterVolumeTarget(dump(c.vol, c.ch, c.soft)); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
	if got := masterVolumeTarget([]byte(`[{"info":{"params":{}}}]`)); got != "" {
		t.Errorf("no props: got %q", got)
	}
	if got := masterVolumeTarget([]byte("[]")); got != "" {
		t.Errorf("empty dump: got %q", got)
	}
}
