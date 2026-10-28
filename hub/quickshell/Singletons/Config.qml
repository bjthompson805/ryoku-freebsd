pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * clock24h / clockSeconds: time-display prefs read from general.json (the
 * file Desktop -> General writes). Read only here: the Hub's own live
 * previews (WidgetsPage, ProfileStats) follow the same desktop-wide toggles
 * as every other clock in the shell.
 */
Singleton {
    id: root

    property alias clock24h: adapter.clock24h
    property alias clockSeconds: adapter.clockSeconds

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/general.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        JsonAdapter { id: adapter; property bool clock24h: true; property bool clockSeconds: false }
    }
}
