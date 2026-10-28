import QtQuick
import Quickshell
import Quickshell.Io

// Shared base for every root's Spawn singleton (see the per-root Spawn.qml,
// which is just `SpawnBase { id: root }`, extended with a live registry in the
// launcher's copy — QML function overrides resolve on the final composed
// object, same mechanism this codebase already relies on for
// launcher/providers/Provider.qml's overridable query()). Not a singleton
// itself — pragma Singleton types can't be used as an inheritance base — so
// this is a plain component. One real file, symlinked as SpawnBase.qml into
// every vendored Singletons/ directory: deploy.sh and the OS installer's
// deploy_dir both dereference symlinks on copy-out, so the repo stays a single
// source of truth while every deployed root still gets its own real file.
//
// Centralised process spawning: replaces raw fire-and-forget exec calls so
// every launch captures its stdout/stderr to a log file (the same output you'd
// get running the command in a terminal) and fires a desktop notification on a
// non-zero exit. Still genuinely fire-and-forget to the caller — the spawned
// Process is parented to this singleton (same trick as Wallhaven.qml's
// capsProc), so it outlives whatever transient UI panel triggered it, no
// Process.startDetached() needed. Logging/dir-creation is a best-effort side
// channel and must never gate or delay the real command (some callers, e.g. a
// lockscreen unlock action, are latency- and reliability-sensitive) — the
// process is started synchronously, before any of the log-writing plumbing
// below even begins. A clean (exit-0) run has its log deleted immediately —
// only a still-running or failed invocation is worth keeping evidence of.
QtObject {
    id: root

    readonly property string logDir: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/spawn-logs"

    property int _seq: 0
    property var _dirsEnsured: ({})   // dir -> true, once `mkdir -p` has succeeded for it

    // ---- public API -----------------------------------------------------

    // argv: array of strings (same shape Quickshell.execDetached took).
    // opts: { id, cwd, env } — all optional. `id` groups/labels this
    // invocation's logs (only meaningful where the launcher's copy of this
    // singleton tracks a live registry; harmless elsewhere).
    function spawn(argv, opts) {
        opts = opts || {};
        var id = opts.id || "";

        var procOpts = { command: argv };
        if (opts.cwd)
            procOpts.workingDirectory = opts.cwd;
        if (opts.env)
            procOpts.environment = opts.env;
        var proc = root._procComp.createObject(root, procOpts);

        var outP = root._splitComp.createObject(root, { splitMarker: "\n" });
        var errP = root._splitComp.createObject(root, { splitMarker: "\n" });
        proc.stdout = outP;
        proc.stderr = errP;

        var slug = root._slug(id || "unlabeled");
        var dir = root.logDir + "/" + slug;
        root._seq++;
        var stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
        var path = dir + "/" + stamp + "-" + root._seq + ".log";
        var entry = { id: id, cmd: argv.join(" "), startedAt: Date.now(), path: path, exitCode: null };
        var buf = "# cmd: " + entry.cmd + "\n# started: " + new Date(entry.startedAt).toString() + "\n";
        var view = null;
        var cleanExit = false;   // set once a code-0 exit decides this log is not worth keeping
        var gotStarted = false;  // set once `started` fires
        var handled = false;     // guards against handleExit running twice

        function handleExit(code, startFailure) {
            if (handled)
                return;
            handled = true;
            if (startFailure) {
                buf += "# FAILED TO START (binary not found or not executable)\n";
                entry.exitCode = null;
            } else {
                buf += "# EXIT " + code + "\n";
                entry.exitCode = code;
            }
            root._untrack(id);
            if (!startFailure && code === 0) {
                // A clean exit means the log is noise, not evidence: drop it
                // from the registry and delete the file so successful,
                // routine spawns don't pile up on disk forever.
                cleanExit = true;
                root._forget(id, entry);
                if (view) {
                    view.destroy();
                    view = null;
                }
                root._deleteLog(path);
            } else {
                root._ensureDir(dir, function () {
                    if (!view)
                        view = root._fileViewComp.createObject(root, { path: path, atomicWrites: true, printErrors: false });
                    view.setText(buf);
                });
                root._notifyFailure(entry, startFailure ? null : code);
            }
            Qt.callLater(function () {
                proc.destroy();
                outP.destroy();
                errP.destroy();
                if (view)
                    view.destroy();
            });
        }

        root._track(id, entry);

        // A missing/unexecutable binary never fires `started` or `exited` --
        // Quickshell just logs its own WARN and silently flips `running`
        // back to false, so a bad command used to fail completely silently
        // (no log, no notification). Catch that: `running` going false
        // without `started` ever having fired only happens on a failed
        // launch (confirmed empirically -- a real exit always fires
        // `started`/`exited` before the matching runningChanged(false)).
        proc.runningChanged.connect(function () {
            if (!proc.running && !gotStarted)
                handleExit(null, true);
        });
        proc.started.connect(function () { gotStarted = true; });
        proc.exited.connect(function (code) { handleExit(code, false); });

        proc.running = true;   // fires now, unconditionally — nothing above may gate this

        root._ensureDir(dir, function () {
            if (cleanExit)
                return;   // exited 0 before the dir was even ready; never create the file
            view = root._fileViewComp.createObject(root, { path: path, atomicWrites: true, printErrors: false });
            view.setText(buf);
        });

        outP.read.connect(function (line) {
            buf += "OUT: " + line + "\n";
            if (view)
                view.setText(buf);
        });
        errP.read.connect(function (line) {
            buf += "ERR: " + line + "\n";
            if (view)
                view.setText(buf);
        });
    }

    // ---- registry (no-op here; the launcher's Spawn.qml overrides these with
    // real bookkeeping — every other root has no equivalent "search result" UI
    // to key a live count against) --------------------------------------------

    function _track(id, entry) {}
    function _untrack(id) {}
    function _forget(id, entry) {}

    // ---- internals --------------------------------------------------------

    function _slug(s) {
        var t = String(s).toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
        if (t.length > 80)
            t = t.substring(0, 80);
        return t.length ? t : "unlabeled";
    }

    function _ensureDir(dir, cb) {
        if (root._dirsEnsured[dir]) {
            cb();
            return;
        }
        var p = root._mkdirComp.createObject(root, { command: ["mkdir", "-p", dir] });
        p.exited.connect(function () {
            root._dirsEnsured[dir] = true;
            Qt.callLater(function () { p.destroy(); });
            cb();
        });
        p.running = true;
    }

    // Best-effort cleanup for a log a clean exit made pointless. Raw process
    // (like _notifyFailure's), not routed through spawn() itself.
    function _deleteLog(path) {
        var p = root._mkdirComp.createObject(root, { command: ["rm", "-f", path] });
        p.exited.connect(function () { Qt.callLater(function () { p.destroy(); }); });
        p.running = true;
    }

    // notify-send -A implies -w (wait) and prints the clicked action's name
    // to stdout once the user interacts, then exits — this is a raw,
    // unwrapped Process (not routed through spawn() itself, which would
    // recursively try to log the notify-send invocation, and again if
    // notify-send itself failed to launch).
    // code === null means the process never started at all (bad binary),
    // as opposed to a real exit with a nonzero code.
    function _notifyFailure(entry, code) {
        // Short and human on purpose: some notification-center surfaces (e.g.
        // this shell's own Inbox) prefer body over summary for their preview
        // text, so body needs to read well on its own, not carry a log dump —
        // "View log" is what the full output is for.
        var summary = (entry.id || entry.cmd) + (code === null
            ? " failed to start (binary not found?)"
            : " failed (exit " + code + ")");
        var body = entry.cmd;
        var p = root._notifyComp.createObject(root, {
            command: ["notify-send", "-w", "-A", "open=View log", "-u", "critical", "-a", "Ryoku", summary, body]
        });
        var out = root._collectorComp.createObject(root);
        p.stdout = out;
        out.streamFinished.connect(function () {
            if (String(out.text).trim() === "open")
                Qt.openUrlExternally("file://" + entry.path);
            Qt.callLater(function () {
                p.destroy();
                out.destroy();
            });
        });
        p.running = true;
    }

    // ---- dynamic-object templates --------------------------------------------

    property Component _procComp: Component { Process {} }
    property Component _splitComp: Component { SplitParser {} }
    property Component _collectorComp: Component { StdioCollector {} }
    property Component _mkdirComp: Component { Process {} }
    property Component _notifyComp: Component { Process {} }
    property Component _fileViewComp: Component { FileView {} }
}
