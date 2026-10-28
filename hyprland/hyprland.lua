-- optional(mod): load a drop-in only when its file exists. most of these are
-- never shipped (user overrides, hub and theme output), and hyprland reports
-- even a pcall'd require() of a missing module in the config-error overlay,
-- so a fresh home flashed "Your config has errors" on first boot. probe the
-- path first; a file that exists but is torn or corrupt still degrades via
-- pcall instead of emergency mode.
local function optional(mod)
    if package.searchpath == nil or package.searchpath(mod, package.path) then
        local ok, err = pcall(require, mod)
        if not ok then
            -- degrade, but say so: a syntax error in a hand-edited drop-in
            -- (user.lua, monitors_user.lua) otherwise vanishes without a trace
            -- and the user is left guessing why their edits do nothing.
            print("ryoku: optional config module '" .. mod .. "' failed to load: " .. tostring(err))
        end
    end
end

require("modules.env")
require("keyboard")
optional("monitors")
-- hand-written overrides: ~/.config/hypr/monitors_user.lua, never shipped.
-- loaded after monitors.lua so a pinned panel wins. see monitors_user.lua.example.
optional("monitors_user")
require("modules.displays")
require("modules.input")
require("modules.misc")
require("modules.decoration")
require("modules.animations")
require("modules.binds")
require("modules.resize")
require("modules.ryoshot")
require("modules.window_rules")
require("modules.fullscreen")
require("modules.autostart")

-- machine-state written by the hub (ryoku-hub), never shipped. after the base
-- modules so the GUI's tweaks override the defaults, before user.lua so a
-- hand-written user file still wins.
optional("settings")

optional("modules.private")

-- last word: ~/.config/hypr/user.lua. seeded once, then yours; never
-- overwritten by install.sh.
optional("user")
