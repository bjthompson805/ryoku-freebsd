# Ryoku FreeBSD

The Ryoku desktop (a Hyprland session with a Quickshell shell) for FreeBSD. It
installs over an existing system; it does not partition disks, install a
bootloader, or replace your base system.

## Install

On a FreeBSD 15 machine with a working GPU driver (see the Handbook's
`drm-kmod` chapter) and a normal user:

    git clone <this repo> ~/code/ryoku-freebsd
    cd ~/code/ryoku-freebsd
    ./install.sh

It installs `packages.txt` with pkg, enables `dbus`, `seatd` and `webcamd`,
adds you to `video`, `operator` and `webcamd`, builds the Go programs and the
QML plugin, and deploys the configs into `~/.config`. Your existing
`~/.config/hypr` is backed up first. Then, from a console login:

    ryoku-session

Make sure `~/.local/bin` is on your `PATH`.

To update, use Ryoku Settings > Updates, or run `ryoku update`: it creates a
boot environment, pulls this checkout, upgrades packages and re-runs
`install.sh`. `ryoku rollback <be>` boots back into the pre-update one.

## Layout

| Path | What |
|---|---|
| `hyprland/` | Hyprland config in Lua, one concern per module. |
| `shell/quickshell/` | The shell UI: pill bar, launcher, ryoshot, widgets, overview, wallpaper picker. |
| `shell/ipc/` | `ryoku-shell`, the Go daemon that supervises the UI and owns wallpaper, clipboard and lock. |
| `shell/plugin/` | `Ryoku.Blobs`, the C++ QML plugin behind the frame. |
| `shell/livewall/` | `ryoku-livewall`, the video-wallpaper daemon. |
| `shell/wallust/` | Palette generation from the wallpaper. |
| `shared/quickshell/` | QML shared by the shell and the hub. |
| `hub/` | Ryoku Settings: QML front end plus the `ryoku-hub` Go backend. |
| `lockscreen/` | The qylock in-session lock. |
| `apps/kitty/` | Terminal config. |
| `apps/ryowalls/` | ryowalls, the wallpaper browser (`Super+Shift+W`). |
| `system/` | Machine helpers: `ryoku` (updates), `ryoku-monitor`, `ryoku-leds`, and `ryoku-priv`, the one root entry point. |
| `assets/` | Brand marks and the default wallpapers. |

## Develop

`shell/dev-run.sh` runs the shell straight from the checkout on the live
session; `shell/dev-stop.sh` stops it. `go test ./...` in `shell/ipc` and
`hub/backend`. `PORTING.md` lists what still assumes Linux.
