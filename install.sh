#!/bin/sh
# Install the Ryoku desktop over an existing FreeBSD system, typically a fresh
# install with a working user and GPU driver. Run it as that user, from the
# checkout; root steps go through sudo or doas. Safe to re-run: it is also how
# a checkout update reaches the machine.
#
#   ./install.sh              packages + services, build, deploy, reload
#   ./install.sh --no-system  skip packages and services (build + deploy only)
#   ./install.sh --no-reload  leave the running session alone until next login
set -eu

system=1
reload=1
for arg in "$@"; do
  case "$arg" in
    --no-system) system=0 ;;
    --no-reload) reload=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = FreeBSD ] || { echo "install.sh: FreeBSD only" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo "install.sh: run as your login user, not root" >&2; exit 1; }

repo="$(cd "$(dirname "$0")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
bin="$HOME/.local/bin"
qml="$HOME/.local/lib/qt6/qml"
say() { printf '  %s\n' "$*"; }

if command -v doas >/dev/null 2>&1; then as_root=doas; else as_root=sudo; fi

# --- system: packages, services, groups --------------------------------------
if [ $system -eq 1 ]; then
  # ask for the password once, up front, so a missing tty fails here and not
  # halfway through.
  if [ "$as_root" = sudo ] && ! sudo -v; then
    echo "install.sh: sudo needs a password; run this from a terminal" >&2
    exit 1
  fi
  say "installing packages"
  # shellcheck disable=SC2046
  $as_root pkg install -y $(grep -Ev '^[[:space:]]*(#|$)' "$repo/packages.txt")
  say "enabling dbus and seatd"
  $as_root sysrc dbus_enable=YES seatd_enable=YES >/dev/null
  $as_root service dbus status >/dev/null 2>&1 || $as_root service dbus start
  $as_root service seatd status >/dev/null 2>&1 || $as_root service seatd start
  say "enabling webcamd"
  $as_root sysrc kld_list+=cuse webcamd_enable=YES >/dev/null
  $as_root kldload -n cuse
  # video: seatd hands the GPU to members. operator: shutdown(8) and
  # acpiconf -s 3 (suspend) from the power menu without root. webcamd: the
  # /dev/video* nodes webcamd creates.
  for g in video operator webcamd; do
    id -Gn | tr ' ' '\n' | grep -qx "$g" || { $as_root pw groupmod "$g" -m "$(id -un)"; say "added $(id -un) to $g (log in again)"; }
  done

  # ryoku-priv: the desktop's only root entry point (lid behaviour, the
  # webcam kill switch), passwordless for this user and this file only.
  $as_root install -o root -g wheel -m 755 "$repo/system/ryoku-priv" /usr/local/libexec/ryoku-priv
  if [ "$as_root" = doas ]; then
    rule="permit nopass $(id -un) as root cmd /usr/local/libexec/ryoku-priv"
    $as_root grep -qxF "$rule" /usr/local/etc/doas.conf 2>/dev/null ||
      printf '%s\n' "$rule" | $as_root tee -a /usr/local/etc/doas.conf >/dev/null
  else
    printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/ryoku-priv\n' "$(id -un)" |
      $as_root tee /usr/local/etc/sudoers.d/ryoku >/dev/null
    $as_root chmod 440 /usr/local/etc/sudoers.d/ryoku
  fi
  say "installed /usr/local/libexec/ryoku-priv"
fi

# --- build ---------------------------------------------------------------------
mkdir -p "$bin" "$qml"
say "building ryoku-shell"
(cd "$repo/shell/ipc" && go build -o "$bin/ryoku-shell" .)
say "building ryoku-hub"
(cd "$repo/hub/backend" && go build -o "$bin/ryoku-hub" .)
say "building Ryoku.Blobs"
RYOKU_BLOBS_BUILD="${XDG_CACHE_HOME:-$HOME/.cache}/ryoku/blobs" "$repo/shell/plugin/build.sh" "$qml" >/dev/null
"$repo/shell/quickshell/plugins/kit/install.sh" "$qml" >/dev/null
say "building ryoku-livewall"
"$repo/shell/livewall/build.sh" "$bin/ryoku-livewall"

for s in ryoku-cmd-radio ryoku-cmd-game-mode; do
  install -m755 "$repo/hyprland/scripts/$s" "$bin/$s"
done
for s in ryoku ryoku-session ryoku-monitor ryoku-leds; do
  install -m755 "$repo/system/$s" "$bin/$s"
done
# the checkout this install came from is the update channel `ryoku` tracks.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/ryoku"
printf '%s\n' "$repo" >"${XDG_STATE_HOME:-$HOME/.local/state}/ryoku/repo"
install -m755 "$repo/shell/quickshell/plugins/ryoku-plugins-place" "$bin/ryoku-plugins-place"
install -m755 "$repo/apps/fastfetch/ryoku-fastfetch" "$bin/ryoku-fastfetch"
for s in ryowalls ryoku-summon; do
  install -m755 "$repo/apps/ryowalls/bin/$s" "$bin/$s"
done

# --- deploy --------------------------------------------------------------------
hypr_live=0
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then hypr_live=1; fi

# quickshell: build the tree aside, then swap it in, so a running qs never
# reloads a half-copied config. -L turns the shared/ symlinks into real files.
qstage="$cfg/quickshell.staging.$$"
rm -rf "$qstage"
mkdir -p "$qstage/hub" "$qstage/ryowalls"
cp -RL "$repo/shell/quickshell/." "$qstage/"
cp -RL "$repo/hub/quickshell/." "$qstage/hub/"
cp -RL "$repo/apps/ryowalls/quickshell/." "$qstage/ryowalls/"
[ $hypr_live -eq 1 ] && [ $reload -eq 1 ] && "$bin/ryoku-shell" quit >/dev/null 2>&1 || true
rm -rf "$cfg/quickshell"
mv "$qstage" "$cfg/quickshell"
say "deployed quickshell -> $cfg/quickshell"

rm -rf "$data/quickshell-lockscreen" "$data/qylock"
mkdir -p "$data/qylock"
cp -R "$repo/lockscreen/qylock/quickshell-lockscreen" "$data/quickshell-lockscreen"
cp -R "$repo/lockscreen/qylock/themes" "$data/qylock/themes"
ln -sfh "$data/qylock/themes" "$data/quickshell-lockscreen/themes_link"
say "deployed lockscreen -> $data/quickshell-lockscreen"

# hypr: shipped files are replaced. over an earlier Ryoku install, anything the
# repo does not ship (the hub's settings.lua, monitors_user.lua) and the seeds
# the user owns are carried over. the old tree is always kept as a backup.
hstage="$cfg/hypr.staging.$$"
rm -rf "$hstage"
cp -R "$repo/hyprland" "$hstage"
if [ -e "$cfg/hypr/modules/autostart.lua" ]; then
  (cd "$cfg/hypr" && find . -type f) | while IFS= read -r rel; do
    [ -e "$hstage/$rel" ] && continue
    mkdir -p "$hstage/$(dirname "$rel")"
    cp -p "$cfg/hypr/$rel" "$hstage/$rel"
  done
  for seed in monitors.lua keyboard.lua user.lua; do
    [ -e "$cfg/hypr/$seed" ] && cp -p "$cfg/hypr/$seed" "$hstage/$seed"
  done
fi
if [ -d "$cfg/hypr" ]; then
  bak="$cfg/hypr.bak-$(date +%Y%m%d%H%M%S)"
  [ $hypr_live -eq 1 ] && hyprctl keyword misc:disable_autoreload true >/dev/null 2>&1 || true
  mv "$cfg/hypr" "$bak"
  say "backed up hypr -> $bak"
fi
touch "$hstage/hyprland.lua"
mv "$hstage" "$cfg/hypr"
say "deployed hyprland -> $cfg/hypr"

mkdir -p "$cfg/wallust" "$cfg/qt6ct" "$cfg/kitty" "$cfg/pulse"
cp "$repo/apps/pulse/client.conf" "$cfg/pulse/client.conf"
cp -R "$repo/shell/wallust/." "$cfg/wallust/"
cp "$repo/shell/qt6ct/qt6ct.conf" "$cfg/qt6ct/qt6ct.conf"
cp "$repo/apps/kitty/kitty.conf" "$cfg/kitty/kitty.conf"
[ -e "$cfg/kitty/current-theme.conf" ] || cp "$repo/apps/kitty/current-theme.conf" "$cfg/kitty/"
# fish: config.fish is Ryoku's, user.fish (sourced last) stays yours.
mkdir -p "$cfg/fish" "$cfg/fastfetch"
cp "$repo/apps/fish/config.fish" "$cfg/fish/config.fish"
cp "$repo/apps/starship/starship.toml" "$cfg/starship.toml"
cp "$repo/apps/fastfetch/config.jsonc" "$cfg/fastfetch/config.jsonc"
cp "$repo/assets/brand/fastfetch-emblem.png" "$cfg/fastfetch/fastfetch-emblem.png"

walls="$HOME/Pictures/Wallpapers"
if [ -z "$(ls -A "$walls" 2>/dev/null)" ]; then
  mkdir -p "$walls"
  cp "$repo/assets/wallpapers/"* "$walls/"
  say "seeded wallpapers -> $walls"
fi

mkdir -p "$data/applications" "$data/icons/hicolor/scalable/apps"
install -m644 "$repo/hub/hub.desktop" "$data/applications/ryoku-hub.desktop"
install -m644 "$repo/assets/brand/logo-mark.svg" "$data/icons/hicolor/scalable/apps/ryoku-hub.svg"
install -m644 "$repo/apps/ryowalls/ryowalls.desktop" "$data/applications/ryowalls.desktop"
install -m644 "$repo/apps/ryowalls/quickshell/logo.svg" "$data/icons/hicolor/scalable/apps/ryowalls.svg"

# fonts the shell draws with that pkg does not carry.
fonts="$data/fonts/ryoku"
gf=https://raw.githubusercontent.com/google/fonts/main/ofl
mi=https://raw.githubusercontent.com/google/material-design-icons/master/variablefont
mkdir -p "$fonts"
for pair in \
  "Inter.ttf $gf/inter/Inter%5Bopsz,wght%5D.ttf" \
  "SpaceGrotesk.ttf $gf/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf" \
  "MaterialSymbolsRounded.ttf $mi/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"; do
  name=${pair%% *}
  [ -s "$fonts/$name" ] || fetch -q -o "$fonts/$name" "${pair#* }" || say "could not fetch $name"
done
fc-cache -f "$fonts" >/dev/null 2>&1 || true

# --- reload --------------------------------------------------------------------
if [ $hypr_live -eq 1 ] && [ $reload -eq 1 ]; then
  hyprctl reload >/dev/null 2>&1 || true
  log="${XDG_STATE_HOME:-$HOME/.local/state}/ryoku-shell.log"
  mkdir -p "$(dirname "$log")"
  daemon -f -o "$log" "$bin/ryoku-shell" daemon
  say "reloaded Hyprland and restarted ryoku-shell"
else
  say "done. start the desktop with: ryoku-session"
fi
case ":$PATH:" in *":$bin:"*) ;; *) say "start it with $bin/ryoku-session (or add $bin to your PATH)" ;; esac
