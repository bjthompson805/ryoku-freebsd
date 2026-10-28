-- keyboard layout. user-owned: seeded on install, then never overwritten by
-- install.sh, so edits here stick.
--
-- multiple layouts? comma-separate + a switch key, e.g.
--     kb_layout  = "us,ru,de,fr"
--     kb_options = "grp:alt_shift_toggle"
-- codes: /usr/local/share/X11/xkb/rules/base.lst. variants/options live in the
-- hyprland wiki (input settings). picking a layout in ryoku settings (input)
-- writes a single-layout override of this file, so for multi-layout setups
-- edit here and leave the settings keyboard layout at its default.
hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_options = "",
    },
})
