import QtQuick
import Quickshell
import "../../Singletons"
import "../../lib/fuzzy.js" as Fuzzy
import ".."

// Desktop-application provider: ranks XDG entries by fuzzy match + launch
// frequency (the same ranker the pill launcher used) and launches the picked one.
// Registers as a default provider (no prefix): apps are the root search.
Provider {
    id: apps

    providerId: "apps"

    readonly property var entries: {
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var e = src[i];
            // X-Ryoku-IconLookup marks a stub .desktop entry that exists only
            // so Apps.titleLookup (Singletons/Apps.qml) can resolve a window
            // icon by title -- it must stay out of NoDisplay (Quickshell's
            // DesktopEntries.applications drops NoDisplay entries entirely,
            // which would make it invisible to that lookup too), so filter
            // it out of the launcher here instead.
            if (e && !e.noDisplay && (!e.categories || e.categories.indexOf("X-Ryoku-IconLookup") < 0))
                out.push(e);
        }
        return out;
    }

    function mapCategory(raw) {
        const order = [
            ["TerminalEmulator", "Terminal"], ["WebBrowser", "Browser"],
            ["InstantMessaging", "Chat"], ["Audio", "Media"], ["AudioVideo", "Media"],
            ["Video", "Media"], ["Game", "Game"], ["Development", "Dev"],
            ["Graphics", "Graphics"], ["Office", "Office"], ["Settings", "System"],
            ["System", "System"], ["Utility", "Tool"], ["Network", "Net"]
        ];
        const cats = String(raw).split(/[;,]/);
        for (let i = 0; i < order.length; i++)
            if (cats.includes(order[i][0]))
                return order[i][1];
        return "App";
    }

    function rowFor(entry) {
        var sub = "";
        if (entry.genericName && entry.genericName.length > 0)
            sub = entry.genericName;
        else if (entry.categories && entry.categories.length > 0)
            sub = mapCategory(entry.categories);
        return {
            id: entry.id,
            title: entry.name,
            subtitle: sub,
            icon: entry.icon ? Quickshell.iconPath(entry.icon, "application-x-executable") : Quickshell.iconPath("application-x-executable", true),
            type: "App",
            score: 0,
            launchedCount: Spawn.countFor(entry.id),
            actions: [{
                name: "Launch",
                icon: "",
                execute: function () {
                    Frecency.bump(entry.id);
                    // Terminal apps keep the built-in launch path unchanged — a
                    // failure there is at least visible in the terminal window
                    // itself, unlike a GUI-only app (the actual VS-Code-hang
                    // case this whole thing exists for).
                    if (entry.runInTerminal) {
                        entry.execute();
                        return;
                    }
                    Spawn.spawn(entry.command, { id: entry.id, cwd: entry.workingDirectory });
                }
            }]
        };
    }

    function query(text) {
        var ranked = Fuzzy.rank(apps.entries, text, Frecency.usage);
        var rows = [];
        for (var i = 0; i < ranked.length; i++)
            rows.push(rowFor(ranked[i]));
        return rows;
    }

    // Every app as a flat row sorted by name, for the all-apps grid.
    function allRows() {
        var src = apps.entries.slice().sort(function (a, b) {
            return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase());
        });
        var rows = [];
        for (var i = 0; i < src.length; i++)
            rows.push(rowFor(src[i]));
        return rows;
    }

    Component.onCompleted: Dispatcher.register(apps)
}
