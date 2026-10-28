pragma Singleton
import QtQuick
import Quickshell
import "../lib/dispatch.js" as Dispatch

// Routes a search query to providers. A leading prefix char selects one provider;
// an unprefixed query fans across every default provider, merged by score and
// capped. Providers register themselves on load, so adding one never edits here.
Singleton {
    id: root

    property var registry: ({})   // id -> provider instance
    property var prefixes: ({})   // prefix char -> provider id
    function register(provider) {
        if (!provider || !provider.providerId)
            return;
        root.registry[provider.providerId] = provider;
        var p = root.prefixes;
        if (provider.prefix && provider.prefix.length >= 1)
            p[provider.prefix] = provider.providerId;
        // a provider may claim several prefixes (e.g. find: /file /folder /image
        // /video); each routes to it, and query() gets the matched prefix as mode.
        var extra = provider.prefixes || [];
        for (var i = 0; i < extra.length; i++)
            p[extra[i]] = provider.providerId;
        root.prefixes = p;
    }

    // The provider a prefixed query targets, or "" for the default fan-out.
    function route(text) {
        return Dispatch.routePrefix(text, root.prefixes);
    }

    // Bumped by async providers when a background query resolves; the launcher's
    // results binding reads it so a late result (qalc, fd, gpk, music) repaints
    // without the user retyping.
    property int revision: 0
    function notifyAsync() { root.revision++; }

    // In-flight async providers, keyed by id so begin/end calls are idempotent
    // and several can run at once. `busy` is true while any is searching; the
    // launcher reads it to show a spinner instead of a premature "No matches".
    property var busyProviders: ({})
    property int busyRevision: 0
    readonly property bool busy: { void root.busyRevision; return Object.keys(root.busyProviders).length > 0; }
    function setBusy(id, on) {
        var b = root.busyProviders;
        if (on) b[id] = true; else delete b[id];
        root.busyProviders = b;
        root.busyRevision++;
    }

    // Merged, score-sorted, capped result rows for the current query. Reads
    // `revision` so async caches re-pull on resolve.
    function results(text, limit) {
        void root.revision;
        void Spawn.revision;
        var r = Dispatch.routePrefix(text, root.prefixes);
        var rows = [];
        if (r.provider) {
            var p = root.registry[r.provider];
            if (p)
                rows = p.query(r.query, r.prefix);
        } else {
            for (var id in root.registry) {
                var prov = root.registry[id];
                if (prov && prov.defaultProvider)
                    rows = rows.concat(prov.query(r.query));
                else if (prov && prov.numericFallback && Dispatch.looksNumeric(r.query))
                    rows = rows.concat(prov.query(r.query));
            }
            // QV4's Array.sort is not stable, so a bare score sort scrambles
            // equal-score rows and destroys each provider's internal ranking
            // (apps pre-rank by match tier + frecency). Tag emission order and
            // use it as the tiebreak.
            for (var n = 0; n < rows.length; n++)
                rows[n]._ord = n;
            rows.sort(function (a, b) {
                var d = (a.score || 0) - (b.score || 0);
                return d !== 0 ? d : a._ord - b._ord;
            });
        }
        var cap = limit && limit > 0 ? limit : rows.length;
        rows = rows.length > cap ? rows.slice(0, cap) : rows;

        // Append a "View log" action per tracked spawn-log for this row, so a
        // launch that hung or errored is always one Ctrl+K away from its
        // output — appended, never unshifted, so it can't hijack Enter or the
        // row's displayed verb (both read actions[0]).
        for (var m = 0; m < rows.length; m++) {
            var logs = Spawn.logsFor(rows[m].id);
            if (logs.length > 0)
                rows[m].actions = rows[m].actions.concat(root._logActions(logs));
        }
        return rows;
    }

    function _logActions(logs) {
        var out = [];
        for (var i = 0; i < logs.length && i < 3; i++) {
            var l = logs[i];
            // A clean (exit-0) run is pruned from the registry the moment it
            // exits (Spawn._forget), so anything left with an exitCode set is
            // by construction a failure, not just "finished" — worth saying
            // so, not just showing when it ran.
            var running = l.exitCode === null || l.exitCode === undefined;
            var time = Qt.formatTime(new Date(l.startedAt), "hh:mm");
            var label = "View log (" + time + ", " + (running ? "running" : "failed") + ")";
            out.push({
                name: label,
                icon: "",
                execute: (function (path) { return function () { Qt.openUrlExternally("file://" + path); }; })(l.path)
            });
        }
        return out;
    }
}
