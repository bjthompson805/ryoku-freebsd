import QtQuick
import Quickshell
import Quickshell.Io

// Codex's app-server exposes subscription limits, while its native session
// history supplies the token breakdown beneath them.
Item {
    id: root
    visible: false

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property string codexHome: Quickshell.env("CODEX_HOME") || (Quickshell.env("HOME") + "/.codex")

    property bool active: false
    property bool available: false
    property bool everHadLimits: false
    property bool lastProbeFailed: false
    property real lastCheckedMs: 0
    property real lastUpdatedMs: 0
    property string planLabel: ""
    readonly property string sessionLabel: "Session (5-hour)"
    readonly property string weeklyLabel: "Weekly (7-day)"
    property int sessionPercent: 0
    property int weeklyPercent: 0
    property real sessionResetsAtMs: -1
    property real weeklyResetsAtMs: -1
    property string authHelpText: "Run `codex login` to see usage."

    property bool localStatsAvailable: false
    property var recentDays: []
    property var modelUsage: []

    readonly property int minRetryIntervalMs: 15000
    readonly property int manualCooldownMs: 5000
    property real lastAttemptMs: 0
    property real lastLocalStatsMs: 0
    readonly property bool refreshing: probeProc.running || scanProc.running

    function refresh() {
        root._refreshLimits(false);
        root._refreshLocalStats();
    }

    function refreshNow() {
        root._refreshLimits(true);
        root._refreshLocalStats();
    }

    function refreshIfStale() {
        var now = Date.now();
        if (now - root.lastCheckedMs >= 120000)
            root._refreshLimits(false);
        if (now - root.lastLocalStatsMs >= 900000)
            root._refreshLocalStats();
    }

    function _refreshLimits(force) {
        if (probeProc.running)
            return;
        var now = Date.now();
        var floor = force ? root.manualCooldownMs : root.minRetryIntervalMs;
        if (now - root.lastAttemptMs < floor)
            return;
        root.lastAttemptMs = now;
        probeProc.running = true;
    }

    function _refreshLocalStats() {
        if (!scanProc.running)
            scanProc.running = true;
    }

    function formatTokenCount(n) {
        var v = Number(n) || 0;
        if (v >= 1e9) return (v / 1e9).toFixed(1) + "B";
        if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
        if (v >= 1e3) return (v / 1e3).toFixed(1) + "K";
        return String(Math.round(v));
    }

    function _modelWordCase(word) {
        return word.charAt(0).toUpperCase() + word.slice(1);
    }

    function friendlyModelName(id) {
        var parts = String(id || "codex").split("-");
        for (var i = 0; i < parts.length; i++)
            parts[i] = root._modelWordCase(parts[i]);
        return parts.join(" ");
    }

    function _resetMs(raw) {
        var n = Number(raw);
        return isFinite(n) && n > 0 ? (n < 1e12 ? n * 1000 : n) : -1;
    }

    function _applyLimits(account, rateLimits) {
        root.lastCheckedMs = Date.now();
        var limits = rateLimits || {};
        var windows = [limits.primary, limits.secondary];
        var found = 0;
        for (var i = 0; i < windows.length; i++) {
            var window = windows[i] || {};
            var percent = Number(window.usedPercent);
            if (!isFinite(percent) || percent < 0)
                continue;
            percent = Math.round(Math.max(0, Math.min(100, percent)));
            if (i === 0) {
                root.sessionPercent = percent;
                root.sessionResetsAtMs = root._resetMs(window.resetsAt);
            } else {
                root.weeklyPercent = percent;
                root.weeklyResetsAtMs = root._resetMs(window.resetsAt);
            }
            found++;
        }
        if (found === 0) {
            root.available = root.everHadLimits;
            root.lastProbeFailed = true;
            root.authHelpText = "Codex's usage endpoint returned no limits.";
            return;
        }
        var plan = limits.planType || (account || {}).planType || (account || {}).type || "";
        root.planLabel = String(plan);
        root.available = true;
        root.everHadLimits = true;
        root.lastProbeFailed = false;
        root.lastUpdatedMs = root.lastCheckedMs;
        root._writeCache();
    }

    function _applyLimitsError(message) {
        root.available = root.everHadLimits;
        root.lastProbeFailed = true;
        root.lastCheckedMs = Date.now();
        root.authHelpText = message || "Couldn't reach Codex's usage endpoint.";
    }

    function _sendRpc(id, method, params) {
        probeProc.write(JSON.stringify({ id: id, method: method, params: params || {} }) + "\n");
    }

    function _handleRpc(raw) {
        var message;
        try {
            message = JSON.parse(raw);
        } catch (e) {
            return;
        }
        if (message.id === 1) {
            probeProc.write(JSON.stringify({ method: "initialized", params: {} }) + "\n");
            root._sendRpc(2, "account/read");
        } else if (message.id === 2) {
            probeProc.probeAccount = (message.result || {}).account || {};
            root._sendRpc(3, "account/rateLimits/read");
        } else if (message.id === 3) {
            probeProc.probeComplete = true;
            root._applyLimits(probeProc.probeAccount, (message.result || {}).rateLimits || {});
            probeProc.running = false;
        }
    }

    function _recentDateStrings() {
        var out = [];
        var now = new Date();
        for (var i = 6; i >= 0; i--) {
            var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            out.push(d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"));
        }
        return out;
    }

    function _applyLocalStats(byDay, byModel) {
        var dates = root._recentDateStrings();
        var days = [];
        for (var i = 0; i < dates.length; i++)
            days.push({ date: dates[i], tokens: Number((byDay || {})[dates[i]] || 0) });
        root.recentDays = days;

        var models = [];
        for (var id in (byModel || {}))
            models.push({ id: id, name: root.friendlyModelName(id), total: Number(byModel[id] || 0) });
        models.sort(function(a, b) { return b.total - a.total; });
        root.modelUsage = models.slice(0, 4);
        root.localStatsAvailable = true;
        root.lastLocalStatsMs = Date.now();
        root._writeCache();
    }

    function _writeCache() {
        cacheFile.setText(JSON.stringify({
            planLabel: root.planLabel,
            sessionPercent: root.sessionPercent,
            weeklyPercent: root.weeklyPercent,
            sessionResetsAtMs: root.sessionResetsAtMs,
            weeklyResetsAtMs: root.weeklyResetsAtMs,
            lastUpdatedMs: root.lastUpdatedMs,
            recentDays: root.recentDays,
            modelUsage: root.modelUsage
        }));
    }

    function _loadCache() {
        try {
            var c = JSON.parse(cacheFile.text());
            root.planLabel = c.planLabel || "";
            root.sessionPercent = c.sessionPercent || 0;
            root.weeklyPercent = c.weeklyPercent || 0;
            root.sessionResetsAtMs = c.sessionResetsAtMs === undefined ? -1 : c.sessionResetsAtMs;
            root.weeklyResetsAtMs = c.weeklyResetsAtMs === undefined ? -1 : c.weeklyResetsAtMs;
            root.lastUpdatedMs = c.lastUpdatedMs || 0;
            if (c.sessionPercent !== undefined || c.weeklyPercent !== undefined) {
                root.available = true;
                root.everHadLimits = true;
            }
            if (Array.isArray(c.recentDays) && c.recentDays.length > 0) {
                root.recentDays = c.recentDays;
                root.localStatsAvailable = true;
            }
            if (Array.isArray(c.modelUsage))
                root.modelUsage = c.modelUsage;
        } catch (e) {}
    }

    Component.onCompleted: root._loadCache()

    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }

    FileView {
        id: cacheFile
        path: root.stateDir + "/agent-usage-codex.json"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: probeProc
        property bool probeComplete: false
        property var probeAccount: ({})
        stdinEnabled: true
        command: ["codex", "-s", "read-only", "-a", "never", "app-server"]
        onStarted: {
            probeProc.probeComplete = false;
            probeProc.probeAccount = ({});
            root._sendRpc(1, "initialize", { clientInfo: { name: "ryoku", version: "1" } });
        }
        onExited: {
            if (!probeProc.probeComplete)
                root._applyLimitsError("Run `codex login` to see usage.");
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._handleRpc(data)
        }
    }

    Timer {
        interval: 12000
        running: probeProc.running
        onTriggered: {
            root._applyLimitsError("Codex's usage endpoint timed out.");
            probeProc.probeComplete = true;
            probeProc.running = false;
        }
    }

    Process {
        id: scanProc
        command: ["bash", "-c",
            "find \"$0/sessions\" \"$0/archived_sessions\" -type f -name '*.jsonl' -mtime -8 -print0 2>/dev/null" +
            " | xargs -0 -r cat 2>/dev/null" +
            " | jq -cs 'reduce .[] as $entry ({model: \"codex\", rows: []};" +
            " ($entry.payload // $entry) as $payload |" +
            " if $entry.type == \"turn_context\" then .model = (($entry.payload.model // $entry.payload.model_slug // .model) | tostring)" +
            " elif $payload.type == \"token_count\" then" +
            " ($payload.info.last_token_usage // {}) as $usage |" +
            " ((($usage.input_tokens // 0) - ($usage.cached_input_tokens // 0) - ($usage.cache_write_input_tokens // 0)) | if . > 0 then . else 0 end) as $input |" +
            " ($input + ($usage.output_tokens // 0) + ($usage.cached_input_tokens // 0) + ($usage.cache_write_input_tokens // 0)) as $tokens |" +
            " if $tokens > 0 and (($entry.timestamp // \"\") | tostring | length) >= 10 then .rows += [{day: (($entry.timestamp | tostring)[0:10]), model: .model, tokens: $tokens}] else . end" +
            " else . end) | .rows as $rows |" +
            " {byDay: ($rows | group_by(.day) | map({key: .[0].day, value: (map(.tokens) | add)}) | from_entries)," +
            "  byModel: ($rows | group_by(.model) | map({key: .[0].model, value: (map(.tokens) | add)}) | from_entries)}'",
            root.codexHome]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(this.text);
                    root._applyLocalStats(result.byDay, result.byModel);
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 120000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }

    Timer {
        interval: 900000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }
}
