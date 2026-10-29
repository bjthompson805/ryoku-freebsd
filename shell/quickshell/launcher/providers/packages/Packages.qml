import QtQuick
import Quickshell
import Quickshell.Io
import "../../Singletons"
import "pkg.js" as Pkg
import ".."

// Package provider backed by pkg(8): `pkg rquery` over the repository
// catalogue plus `pkg query` for what is installed, both local and answering
// in well under a second. Routed by "/" is the actions panel; packages use
// explicit "install "/"remove "/"search " queries (matching inir) so a plain
// search never forks pkg. Search is async + cached; installs/removes spawn a
// terminal because pkg needs root and the sudo/doas prompt needs a tty.
Provider {
    id: packages

    providerId: "packages"
    prefix: ">"
    defaultProvider: false

    property bool available: false
    property string cachedQuery: ""
    property var cachedRows: []
    property string pendingQuery: ""

    readonly property string terminal: "kitty"

    // text after ">": "search x" / "install x" / "remove x", or a bare query that
    // defaults to search. So ">fish" searches, ">install fish" installs.
    function parseOp(text) {
        var m = String(text || "").match(/^(install|remove|search)\s+(.+)$/i);
        if (m)
            return { op: m[1].toLowerCase(), term: m[2].trim() };
        var t = String(text || "").trim();
        // a bare verb mid-typing (">install ") is an incomplete command, not
        // a search for the literal word; searching it flashed unrelated rows.
        if (/^(install|remove|search)$/i.test(t))
            return null;
        return t.length ? { op: "search", term: t } : null;
    }

    function rowFor(pkg, op) {
        var verb = op === "remove" ? "Remove" : (pkg.installed ? "Reinstall" : "Install");
        return {
            id: "pkg:" + pkg.source + ":" + pkg.name,
            title: pkg.name + "  " + pkg.version,
            subtitle: pkg.source + (pkg.installed ? "  (installed)" : "") + "  " + pkg.description,
            icon: "",
            type: "Package",
            score: 0,
            launchedCount: Spawn.countFor("pkg:" + pkg.source + ":" + pkg.name),
            actions: [{
                name: verb,
                icon: "",
                execute: function () {
                    var pkgOp = op === "remove" ? "delete" : "install";
                    // the name is a positional arg, never spliced into the script.
                    Spawn.spawn([packages.terminal, "--hold", "-e", "sh", "-c",
                        'if command -v doas >/dev/null 2>&1; then doas pkg "$1" "$2"; else sudo pkg "$1" "$2"; fi',
                        "sh", pkgOp, pkg.name], { id: "pkg:" + pkg.source + ":" + pkg.name });
                    // the install/remove will change what a re-search should
                    // show; drop the cached rows so the next query refetches.
                    packages.cachedQuery = "";
                }
            }]
        };
    }

    function query(text) {
        if (!packages.available)
            return [];
        var p = parseOp(text);
        if (!p || p.term.length < 2)
            return [];
        if (p.term === packages.cachedQuery)
            return packages.cachedRows
                .filter(function (pkg) { return p.op !== "remove" || pkg.installed; })
                .map(function (pkg) { return packages.rowFor(pkg, p.op); });
        packages.pendingQuery = p.term;
        debounce.restart();
        return [];
    }

    Timer {
        id: debounce
        interval: 120
        repeat: false
        onTriggered: {
            searchProc.term = packages.pendingQuery;
            searchProc.running = false;
            searchProc.running = true;
        }
    }

    Process {
        id: availProc
        command: ["pkg", "-N"]
        onExited: (code) => { packages.available = (code === 0); }
    }

    Process {
        id: searchProc
        onRunningChanged: Dispatcher.setBusy("packages", running)
        property string term: ""
        property string out: ""
        command: ["sh", "-c",
            "pkg rquery -i -x 'R\t%n\t%v\t%R\t%c' \"$1\" 2>/dev/null; pkg query -i -x 'I\t%n\t%v\t%R\t%c' \"$1\" 2>/dev/null; true",
            "sh", Pkg.escapeRegex(term)]
        stdout: SplitParser {
            onRead: data => searchProc.out += data + "\n"
        }
        onStarted: searchProc.out = ""
        onExited: (code, status) => {
            // killed = superseded; don't cache a partial read.
            if (status !== 0)
                return;
            packages.cachedQuery = searchProc.term;
            packages.cachedRows = Pkg.parse(searchProc.out, searchProc.term);
            Dispatcher.notifyAsync();
        }
    }

    Component.onCompleted: {
        availProc.running = true;
        Dispatcher.register(packages);
    }
}
