-- blank on close, wake on open. with Lid Sleep on the kernel suspends first
-- anyway; with it off (ryoku-cmd-lid-sleep) this is all that happens.
hl.bind("switch:on:Control Method Lid Switch",  hl.dsp.exec_cmd("hyprctl dispatch dpms off"), { locked = true })
hl.bind("switch:off:Control Method Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms on"),  { locked = true })
