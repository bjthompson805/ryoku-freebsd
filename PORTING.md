# Porting checklist

What still assumes Linux. Delete a line when it is done.

## Dead references to removed Linux-only features

- Stash installer: `pill/Singletons/Stash.qml`.
- Update channel: `pill/Singletons/Updates.qml`, `shell/ipc/wallpaper.go` (`ryoku update`, `ryoku-leds`).
- ryowalls (the wallpaper browser), still bound to `Super+Shift+W` in `binds.lua` with a rule in `window_rules.lua`.
- Battery charge limit: `pill/Singletons/Battery.qml` calls `ryoku-charge-limit`, which used Linux sysfs + udev. Hidden while the helper is absent.

## Linux tools with a FreeBSD equivalent

- Wi-Fi via `nmcli`: `shared/WifiLink.qml`, `pill/Singletons/Network.qml`, `pill/LinkWifi.qml`, `pill/popouts/NetworkPopout.qml`, `hub/WifiTab.qml`, `hub/HotspotTab.qml`. Port to `ifconfig wlan0 scan` + `wpa_cli`.
- Brightness via `brightnessctl` in QML: `shared/Devices.qml`, `pill/popouts/DisplayPopout.qml`, `pill/popouts/SidebarSystem.qml`, `hub/AppearancePage.qml`. Port to `backlight(8)` (the daemon already uses it).
- Volume via `wpctl`: `hyprland/modules/binds.lua`, `pill/DeckControls.qml`. Port to `pactl` (pipewire-pulse) or `mixer(8)`.
- `pw-dump`: `visualizer/shell.qml`.
- `/proc` and `/sys` reads: `pill/Singletons/SysStats.qml`, `NetSpeed.qml`, `LockKeys.qml`, `Keyring.qml`, `shared/WifiLink.qml`, `scripts/ryoku-sysinfo`, `scripts/ryoku-profile-stats`, `scripts/ryoku-cmd-game-mode`. Port to `sysctl`, `netstat -ibn`, `swapinfo`, `geom`.
- `ip addr` / `ip route` / `lsblk`: `pill/popouts/NetworkPopout.qml`, `NetSpeed.qml`, `SysStats.qml`. Port to `ifconfig`, `route -n get default`, `geom disk list`.
- Package search via pacman/yay: `launcher/providers/packages/Packages.qml`. Port to `pkg search`.
- Battery via upower: `pill/Singletons/Battery.qml`. Check upower's FreeBSD backend, else `acpiconf -i 0`.
- `ddcutil` (external monitor brightness): `shared/Devices.qml`, `DisplayPopout.qml`.

## No FreeBSD equivalent

- Bluetooth: `Quickshell.Bluetooth` talks to BlueZ, which FreeBSD lacks. `shared/BluetoothLink.qml`, `pill/LinkBt.qml`, `hub/BluetoothTab.qml` should hide when no adapter appears.

## Not yet verified on hardware

- `install.sh` end to end, the `Ryoku.Blobs` CMake build, and the `ryoku-livewall` build.
- Every QML surface under Quickshell 0.3.2 / Qt 6.11.
- qylock PAM auth against FreeBSD's `/etc/pam.d`.
- A real wf-recorder capture: VAAPI fallback timing, region crop, and pipewire-pulse audio device names.
