-- Caps/Num Lock OSD. FreeBSD has no LED classdevs to watch, so on release
-- (the state has toggled by then), without eating the key, the daemon reads
-- the new state off Hyprland and the pill flashes it.
hl.bind("Caps_Lock", hl.dsp.exec_cmd("ryoku-shell lockkeys"), { locked = true, release = true, non_consuming = true })
hl.bind("Num_Lock",  hl.dsp.exec_cmd("ryoku-shell lockkeys"), { locked = true, release = true, non_consuming = true })
