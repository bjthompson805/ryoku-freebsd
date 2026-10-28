pragma Singleton
import QtQuick
import Quickshell

// generic "flash this setting" bus. A SettingSection declares its own
// highlightId and listens for requested(id); anything that relocates the
// user to a setting -- a search-result click, an "Open <page>" cross-link
// like Desktop Widgets > Weather > Location -> General -- just calls
// trigger() with the id it already shares with that section, via
// Hub.qml's go(section, tab, highlight). No caller needs its own one-off
// highlight/scroll logic.
Singleton {
    signal requested(string id)

    function trigger(id) {
        if (id && id.length > 0)
            requested(id);
    }
}
