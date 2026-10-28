hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark")
    -- no systemd user manager: hand the session env to dbus so activated
    -- services (the portals) can find the compositor.
    hl.exec_cmd("dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE")
    -- audio: no user service manager starts PipeWire, so the session does.
    -- pipewire starts wireplumber itself (the package's 10-wireplumber.conf),
    -- pipewire-spa-oss-ng drives the OSS devices, and pipewire-pulse serves
    -- the apps that speak Pulse (install.sh turns PulseAudio's autospawn off).
    hl.exec_cmd("pgrep -qx pipewire || { pipewire & sleep 1; pipewire-pulse & }")
    hl.exec_cmd("command -v ryoku-monitor >/dev/null 2>&1 && ryoku-monitor autoscale")
    hl.exec_cmd("ryoku-shell daemon")
    hl.exec_cmd("command -v hypridle >/dev/null 2>&1 && hypridle")
    hl.exec_cmd("command -v ryoku-leds >/dev/null 2>&1 && ryoku-leds apply")
    -- first-login walkthrough, once. the flag is written only if qs actually
    -- ran the tour, so a launch failure retries next login.
    local welcome_state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/ryoku"
    hl.exec_cmd("[ -e '" .. welcome_state .. "/welcome-seen' ] || { flock -n \"${XDG_RUNTIME_DIR:-/tmp}/ryoku-welcome.lock\" qs -c welcome && mkdir -p '" .. welcome_state .. "' && touch '" .. welcome_state .. "/welcome-seen'; }")
end)
