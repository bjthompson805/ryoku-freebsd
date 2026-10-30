package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// usbaudio keeps USB headsets usable under PipeWire's OSS backend. Two gaps:
//
//   - WirePlumber holds on to the configured default output, so a headset
//     plugged in later sits unused until it is picked by hand. Other desktops
//     switch to it, so a newly added USB sink (and its microphone) becomes
//     the default, as btSwitchTo does for Bluetooth.
//   - The OSS plugin drives sink volume through the uaudio feature unit, and
//     some dongles ignore it: the slider moves, the loudness does not. For
//     those the sink's volume is mirrored into the node's master volume,
//     which PipeWire applies to the samples. Not the per-channel software
//     volumes: the plugin resets those to full on every volume change, and
//     mirroring into them blasted full volume until the mirror caught up. The
//     master is left alone, so between a change and its mirror the old level
//     plays on. Mute needs no help: the plugin already sets the software mute.

// usbSoftVolume lists the USB audio devices, as "vendor:product", that
// ignore the feature unit's volume. They expect the host to scale the audio
// itself; the headset's volume wheel arrives as HID volume keys.
var usbSoftVolume = map[string]bool{
	"0x1532:0x0a4e": true, // Razer BlackShark V3 Pro (Xbox dongle)
}

// pulseNode is the part of a `pactl -f json list sinks|sources` entry used here.
type pulseNode struct {
	Index      int               `json:"index"`
	Name       string            `json:"name"`
	Properties map[string]string `json:"properties"`
}

func (n pulseNode) parent() string { return n.Properties["api.freebsd-oss.pcm-parent"] }

func (n pulseNode) isUSB() bool {
	return n.Properties["device.api"] == "freebsd-oss" && strings.HasPrefix(n.parent(), "uaudio")
}

func parsePulseNodes(b []byte) []pulseNode {
	var ns []pulseNode
	if json.Unmarshal(b, &ns) != nil {
		return nil
	}
	return ns
}

func pulseList(kind string) []pulseNode {
	out, err := exec.Command("pactl", "-f", "json", "list", kind).Output()
	if err != nil {
		return nil
	}
	return parsePulseNodes(out)
}

// pickUSBDefaults chooses the output and input to switch to for the USB
// sinks just added. A dongle can offer more than one playback pcm (game and
// chat); the one paired with a microphone (pcmN.play beside pcmN.rec) is the
// headset's main output. Empty strings mean nothing to switch.
func pickUSBDefaults(added []int, sinks, sources []pulseNode) (sink, source string) {
	fresh := map[int]bool{}
	for _, i := range added {
		fresh[i] = true
	}
	parent := ""
	for _, s := range sinks {
		if fresh[s.Index] && s.isUSB() {
			parent = s.parent()
			break
		}
	}
	if parent == "" {
		return "", ""
	}
	recs := map[string]bool{}
	for _, s := range sources {
		if s.isUSB() && s.parent() == parent && s.Properties["device.class"] != "monitor" {
			recs[s.Name] = true
			if source == "" {
				source = s.Name
			}
		}
	}
	for _, s := range sinks {
		if !s.isUSB() || s.parent() != parent {
			continue
		}
		if rec := strings.TrimSuffix(s.Name, ".play") + ".rec"; recs[rec] {
			return s.Name, rec
		}
		if sink == "" {
			sink = s.Name
		}
	}
	return sink, source
}

// usbID reads "vendor:product" for a uaudio unit from its pnpinfo.
func usbID(parent string) string {
	unit := strings.TrimPrefix(parent, "uaudio")
	out, err := exec.Command("sysctl", "-n", "dev.uaudio."+unit+".%pnpinfo").Output()
	if err != nil {
		return ""
	}
	var vendor, product string
	for _, f := range strings.Fields(string(out)) {
		if v, ok := strings.CutPrefix(f, "vendor="); ok {
			vendor = v
		} else if v, ok := strings.CutPrefix(f, "product="); ok {
			product = v
		}
	}
	if vendor == "" || product == "" {
		return ""
	}
	return strings.ToLower(vendor + ":" + product)
}

// masterVolumeTarget reads a `pw-dump <id>` of a sink and returns the Props
// pod that carries its volume in the master volume, or "" when it already
// does. The master is one value, so it takes the loudest channel. Software
// volumes left by an older mirror are put back to full. The guard matters:
// setting Props raises another sink change event.
func masterVolumeTarget(b []byte) string {
	var objs []struct {
		Info struct {
			Params struct {
				Props []struct {
					Volume         *float64  `json:"volume"`
					ChannelVolumes []float64 `json:"channelVolumes"`
					SoftVolumes    []float64 `json:"softVolumes"`
				} `json:"Props"`
			} `json:"params"`
		} `json:"info"`
	}
	if json.Unmarshal(b, &objs) != nil || len(objs) == 0 {
		return ""
	}
	for _, p := range objs[0].Info.Params.Props {
		if len(p.ChannelVolumes) == 0 || p.Volume == nil {
			continue
		}
		want := 0.0
		for _, v := range p.ChannelVolumes {
			want = math.Max(want, v)
		}
		full := true
		for _, v := range p.SoftVolumes {
			if math.Abs(v-1) > 1e-4 {
				full = false
			}
		}
		if full && math.Abs(*p.Volume-want) <= 1e-4 {
			return ""
		}
		w := strconv.FormatFloat(want, 'f', 6, 64)
		if full {
			return fmt.Sprintf("{ volume: %s }", w)
		}
		ones := strings.TrimSuffix(strings.Repeat("1.0, ", len(p.SoftVolumes)), ", ")
		return fmt.Sprintf("{ volume: %s, softVolumes: [ %s ] }", w, ones)
	}
	return ""
}

// syncUSBAudio switches to a USB headset among the sinks just added, then
// mirrors volume into the master for the dongles that need it.
func syncUSBAudio(added []int) {
	sinks := pulseList("sinks")
	if len(added) > 0 {
		sink, source := pickUSBDefaults(added, sinks, pulseList("sources"))
		if sink != "" {
			_ = exec.Command("pactl", "set-default-sink", sink).Run()
		}
		if source != "" {
			_ = exec.Command("pactl", "set-default-source", source).Run()
		}
	}
	ids := map[string]string{}
	for _, s := range sinks {
		if !s.isUSB() {
			continue
		}
		p := s.parent()
		if _, ok := ids[p]; !ok {
			ids[p] = usbID(p)
		}
		obj := s.Properties["object.id"]
		if !usbSoftVolume[ids[p]] || obj == "" {
			continue
		}
		out, err := exec.Command("pw-dump", obj).Output()
		if err != nil {
			continue
		}
		if pod := masterVolumeTarget(out); pod != "" {
			_ = exec.Command("pw-cli", "set-param", obj, "Props", pod).Run()
		}
	}
}

// sinkEvent is one `pactl subscribe` line about a sink.
type sinkEvent struct {
	index int
	added bool
}

// parseSinkEvent reads "Event 'new' on sink #566".
func parseSinkEvent(line string) (sinkEvent, bool) {
	i := strings.Index(line, " on sink #")
	if i < 0 || !strings.HasPrefix(line, "Event '") {
		return sinkEvent{}, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(line[i+len(" on sink #"):]))
	if err != nil {
		return sinkEvent{}, false
	}
	return sinkEvent{index: n, added: strings.HasPrefix(line, "Event 'new'")}, true
}

// watchUSBAudio handles sink events from watchAudio's subscriber. Events come
// in bursts (a dongle adds several nodes; a held volume key fires dozens), so
// each burst is handled once after it settles. The settle is short: the new
// level waits on it. It runs once at start to cover a
// volume set while the daemon was down.
func (d *daemon) watchUSBAudio(events <-chan sinkEvent) {
	const (
		settle     = 40 * time.Millisecond
		plugSettle = 300 * time.Millisecond
	)
	syncUSBAudio(nil)
	for {
		var added []int
		select {
		case <-d.quit:
			return
		case e := <-events:
			if e.added {
				added = append(added, e.index)
			}
		}
		timer := time.NewTimer(settle)
	burst:
		for {
			select {
			case <-d.quit:
				timer.Stop()
				return
			case e := <-events:
				if e.added {
					added = append(added, e.index)
				}
			case <-timer.C:
				break burst
			}
		}
		if len(added) > 0 {
			// a plugged dongle's microphone can lag its sinks; give it time
			// to appear before picking the defaults.
			select {
			case <-d.quit:
				return
			case <-time.After(plugSettle):
			}
		}
		syncUSBAudio(added)
	}
}
