# Porting checklist

What still assumes Linux. Delete a line when it is done.

## To port, needs a FreeBSD design

- Battery charge limit: `pill/Singletons/Battery.qml` calls `ryoku-charge-limit`, which used Linux sysfs + udev. FreeBSD has no general charge-threshold interface, so this needs a per-vendor backend (start with the ASUS laptop it runs on). The UI hides itself while the helper is absent.

## Linux tools with a FreeBSD equivalent

- Wi-Fi via `nmcli`: `shared/WifiLink.qml`, `pill/Singletons/Network.qml`, `pill/LinkWifi.qml`, `pill/popouts/NetworkPopout.qml`, `hub/WifiTab.qml`, `hub/HotspotTab.qml`. Port to `ifconfig wlan0 scan` + `wpa_cli`. Quickshell's own network service has no FreeBSD backend either.
- `/proc` and `/sys` reads: `pill/Singletons/SysStats.qml`, `NetSpeed.qml`, `LockKeys.qml`, `Keyring.qml`, `shared/WifiLink.qml`, `scripts/ryoku-sysinfo`, `scripts/ryoku-profile-stats`, `scripts/ryoku-cmd-game-mode`. Port to `sysctl`, `netstat -ibn`, `swapinfo`, `geom`.
- `ip addr` / `ip route` / `lsblk`: `pill/popouts/NetworkPopout.qml`, `NetSpeed.qml`, `SysStats.qml`. Port to `ifconfig`, `route -n get default`, `geom disk list`.
- Package search via `gpk` (pacman/yay): `launcher/providers/packages/Packages.qml`. Port to `pkg search`.
- Battery via upower: `pill/Singletons/Battery.qml`. Check upower's FreeBSD backend, else `acpiconf -i 0`.

## No FreeBSD equivalent

- Bluetooth: `Quickshell.Bluetooth` talks to BlueZ, which FreeBSD lacks. `shared/BluetoothLink.qml`, `pill/LinkBt.qml`, `hub/BluetoothTab.qml` should hide when no adapter appears.
- External monitor brightness: `ddcutil` needs Linux's `/dev/i2c-*` and has no FreeBSD port. `shared/Devices.qml` finds no monitors without it, so the faders stay hidden.
- Power profiles: Quickshell's PowerProfiles service needs `power-profiles-daemon`, which FreeBSD lacks. Find what uses it and hide it, or back it with `powerd`/`powerdxx`.

## Not yet verified on hardware

- The internal speakers on the Zenbook S 16 (UM5606WA): FreeBSD `snd_hda` gap, see `~/zenbook-audio-fix.md` on that machine.
- Every QML surface under Quickshell 0.3.2 / Qt 6.11 beyond the bar, launcher, Hub and ryowalls.
- qylock PAM auth against FreeBSD's `/etc/pam.d`.
- A real wf-recorder capture: VAAPI fallback timing, region crop, and pipewire-pulse audio device names.
- A real `ryoku update` run and a rollback into the pre-update boot environment.
- `ryoku-leds` against real OpenRGB devices.
