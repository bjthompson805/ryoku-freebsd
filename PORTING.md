# Porting checklist

What still assumes Linux. Delete a line when it is done.

## No FreeBSD equivalent

- Bluetooth: `Quickshell.Bluetooth` talks to BlueZ, which FreeBSD lacks. `shared/BluetoothLink.qml`, `pill/LinkBt.qml`, `hub/BluetoothTab.qml` should hide when no adapter appears.
- External monitor brightness: `ddcutil` needs Linux's `/dev/i2c-*` and has no FreeBSD port. `shared/Devices.qml` finds no monitors without it, so the faders stay hidden.
- Power profiles: Quickshell's PowerProfiles service needs `power-profiles-daemon`, which FreeBSD lacks. Find what uses it and hide it, or back it with `powerd`/`powerdxx`.

## Not yet verified on hardware

- Wi-Fi through `ryoku-shell wifi` (scan, join, radio, game mode's power save): the Zenbook's MT7925 has no FreeBSD driver, so only the wired path and a fake supplicant in the tests have run it.
- The battery charge limit (`ryoku-priv charge-limit`, ASUS WMI through acpi_call): the Zenbook's firmware answers the support probe, but no limit has been written yet. Only ASUS laptops are handled; others show no control.
- The hotspot (`ryoku-priv hotspot`: hostap clone, hostapd, dnsmasq, pf NAT) has never run. Many FreeBSD Wi-Fi drivers cannot do hostap mode at all.
- The internal speakers on the Zenbook S 16 (UM5606WA): FreeBSD `snd_hda` gap, see `~/zenbook-audio-fix.md` on that machine.
- Every QML surface under Quickshell 0.3.2 / Qt 6.11 beyond the bar, launcher, Hub and ryowalls.
- qylock PAM auth against FreeBSD's `/etc/pam.d`.
- A real wf-recorder capture: VAAPI fallback timing, region crop, and pipewire-pulse audio device names.
- A real `ryoku update` run and a rollback into the pre-update boot environment.
- `ryoku-leds` against real OpenRGB devices.
