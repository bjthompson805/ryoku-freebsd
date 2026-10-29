# Porting checklist

What still assumes Linux. Delete a line when it is done.

## No FreeBSD equivalent

These stay in the code but hide themselves, since FreeBSD has nothing for them to talk to.

- Bluetooth: `Quickshell.Bluetooth` talks to BlueZ, which FreeBSD lacks, so no adapter appears. The Link row, the deck toggle and the Hub tab hide; the bar's icon was already gated. Quickshell still logs one org.bluez warning at start.
- External monitor brightness: `ddcutil` needs Linux's `/dev/i2c-*` and has no FreeBSD port. `shared/Devices.qml` finds no monitors without it, so the faders stay hidden.

## Not yet verified on hardware

- Wi-Fi through `ryoku-shell wifi` (scan, join, radio, game mode's power save): the Zenbook's MT7925 has no FreeBSD driver, so only the wired path and a fake supplicant in the tests have run it.
- The hotspot (`ryoku-priv hotspot`: hostap clone, hostapd, dnsmasq, pf NAT) has never run. Many FreeBSD Wi-Fi drivers cannot do hostap mode at all.
- The internal speakers on the Zenbook S 16 (UM5606WA): FreeBSD `snd_hda` gap, see `~/zenbook-audio-fix.md` on that machine.
- Every QML surface under Quickshell 0.3.2 / Qt 6.11 beyond the bar, launcher, Hub and ryowalls.
- qylock PAM auth against FreeBSD's `/etc/pam.d`.
- A real wf-recorder capture: VAAPI fallback timing, region crop, and pipewire-pulse audio device names.
- A real `ryoku update` run and a rollback into the pre-update boot environment.
- `ryoku-leds` against real OpenRGB devices.
