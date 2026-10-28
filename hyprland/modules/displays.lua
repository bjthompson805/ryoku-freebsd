-- hotplug: repaint the wallpaper so the new output isn't blank. the sleep lets
-- the mode settle first, else awww caches the image at the wrong resolution.
hl.on("monitor.added", function()
    hl.exec_cmd("command -v ryoku-shell >/dev/null 2>&1 && { sleep 1; ryoku-shell wallpaper refresh; }")
end)
