import QtQuick
import Quickshell
import Quickshell.Io

// Claude Code's rate-limit usage source for the bar's agent-usage readout. reads the
// OAuth access token Claude Code's CLI already keeps in
// ~/.claude/.credentials.json (claudeAiOauth.accessToken -- nothing else in
// that file is touched beyond the plan label, and the token goes nowhere but
// this one request's Authorization header) and probes Anthropic's own usage
// endpoint for the session (5-hour) and weekly (7-day) rate-limit percentages
// -- the same figures `claude usage` reports, no local transcript scanning
// for those two numbers. Separately, a local scan of ~/.claude/projects'
// *.jsonl transcripts (last 8 days only, to keep it bounded) builds the
// token-by-day and token-by-model breakdown the popout shows underneath the
// limits, mirroring Omarchy's agent-usage panel. last-good reading of both
// is cached to disk so a shell restart shows real numbers instead of blank
// ones until the next poll lands. the pollers run only while `active` (a
// visible BarAgentUsage sets it), same idiom as SysStats/NetSpeed -- on two
// separate clocks, since the two costs are wildly different: the rate-limit
// probe is one small request and needs to stay current (polls every 2
// minutes -- Anthropic's usage endpoint 429s a straight 1-minute cadence),
// the transcript scan is real CPU for numbers that only need daily
// granularity anyway (every 15 minutes). refreshNow() (the popout's manual
// refresh button) runs both against a much shorter cooldown than the
// periodic timer's, but not zero -- see manualCooldownMs.
Item {
    id: root
    visible: false

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property string credentialsPath: (Quickshell.env("CLAUDE_CONFIG_DIR") || (Quickshell.env("HOME") + "/.claude")) + "/.credentials.json"
    readonly property string projectsPath: (Quickshell.env("CLAUDE_CONFIG_DIR") || (Quickshell.env("HOME") + "/.claude")) + "/projects"

    property bool active: false

    // ---- rate limits (Anthropic's usage endpoint) --------------------------
    property bool available: false
    // sticky once true: a later probe failure (rate-limited, transport error,
    // ...) shouldn't blank out a reading we already have. `available` stays
    // true and keeps showing the last-good numbers; authHelpText carries the
    // failure detail for the popout instead.
    property bool everHadLimits: false
    // true only for the most recent probe -- distinct from `available`
    // (which is sticky), so the popout can still surface "rate-limited,
    // retrying shortly" even while it's showing a stale-but-real reading.
    property bool lastProbeFailed: false
    // epoch ms of the most recent completed attempt, success or failure --
    // so the popout can say "checked 8s ago" and a repeated-but-genuinely-
    // rechecked 429 reads as "still limited as of just now" instead of
    // looking like the click did nothing at all.
    property real lastCheckedMs: 0
    // epoch ms of the most recent SUCCESSFUL probe -- distinct from
    // lastCheckedMs. a long rate-limit stretch can leave lastCheckedMs
    // ticking every couple minutes while the actual sessionPercent/
    // weeklyPercent on screen are hours stale; this is what answers "how
    // old is the number I'm looking at", not "when did it last try".
    property real lastUpdatedMs: 0
    property string planLabel: ""
    readonly property string sessionLabel: "Session (5-hour)"
    readonly property string weeklyLabel: "Weekly (7-day)"
    property int sessionPercent: 0
    property int weeklyPercent: 0
    // epoch ms, or -1 when unknown; kept raw (not pre-formatted) so the
    // popout's own countdown stays live while it's open instead of freezing
    // the text at fetch time.
    property real sessionResetsAtMs: -1
    property real weeklyResetsAtMs: -1
    property string authHelpText: "Run `claude auth login` to see usage."

    // ---- local transcript scan (token-by-day / token-by-model) -------------
    property bool localStatsAvailable: false
    // [{date: "YYYY-MM-DD", tokens: N}, ...] oldest -> newest, always 7 entries.
    property var recentDays: []
    // [{id, name, total}, ...] sorted desc, top 4.
    property var modelUsage: []

    // a 429 or transport failure shouldn't retry faster than this even if the
    // periodic timer pokes refresh() again right away (mirrors Omarchy's
    // collector).
    readonly property int minRetryIntervalMs: 15000
    // the manual refresh button's own floor -- much shorter than the timer's,
    // so it still feels responsive, but NOT zero: a user double/triple
    // clicking it during an active rate limit was re-triggering a fresh 429
    // from Anthropic on every single click (confirmed live -- every click
    // really was reaching the endpoint and really was getting rate-limited
    // again each time, not a stuck/frozen UI), which just kept the window
    // extended. This stops a click storm from being self-defeating.
    readonly property int manualCooldownMs: 5000
    property real lastAttemptMs: 0
    property real lastLocalStatsMs: 0

    // true while either probe is in flight, for the popout's refresh spinner.
    readonly property bool refreshing: probeProc.running || scanProc.running

    function refresh() {
        root._refreshLimits(false);
        root._refreshLocalStats();
    }

    // user-triggered (the popout's refresh button): shorter floor than the
    // periodic timer's, not zero -- see manualCooldownMs.
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
        tokenFile.reload();
    }

    function _refreshLocalStats() {
        if (!scanProc.running)
            scanProc.running = true;
    }

    // ---- formatting, shared with the popout --------------------------------

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

    // model ids arrive like "claude-opus-4-5" or "claude-haiku-4-5-20251001";
    // strip the "claude-" prefix and a trailing 8-digit date snapshot, rejoin
    // the numeric run into one version, title-case the rest.
    function friendlyModelName(id) {
        if (!id)
            return "Unknown";
        var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "");
        var parts = name.split("-");
        var words = [];
        var version = [];
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i];
            if (part === "")
                continue;
            if (/^\d/.test(part)) {
                version.push(part);
                continue;
            }
            if (version.length > 0) {
                words.push(version.join("."));
                version = [];
            }
            words.push(root._modelWordCase(part));
        }
        if (version.length > 0)
            words.push(version.join("."));
        return words.length > 0 ? words.join(" ") : "Unknown";
    }

    // ---- rate-limit parsing --------------------------------------------

    // Anthropic's usage endpoint reports percentages (37.0) on some payloads
    // and fractions (0.37) on others. A single value can't tell which -- a
    // genuine 0.5% usage and a 0.5 fraction (50%) look identical -- so the
    // scale is settled once per payload from whichever field is unambiguous
    // (any raw value >= 1 means the payload speaks percent), same as
    // Omarchy's collector.
    function _percentScale(rawValues) {
        for (var i = 0; i < rawValues.length; i++) {
            var n = Number(rawValues[i]);
            if (n >= 1)
                return true;
        }
        return false;
    }

    function _normalizePercent(raw, percentScale) {
        var n = Number(raw);
        if (!(n >= 0))
            return -1;
        return Math.round(Math.min(100, percentScale ? n : n * 100));
    }

    function _resetMs(raw) {
        if (raw === undefined || raw === null || raw === "")
            return -1;
        var n = Number(raw);
        var d = !isNaN(n) && /^[0-9.]+$/.test(String(raw).trim())
            ? new Date(n < 1e12 ? n * 1000 : n)
            : new Date(raw);
        var ms = d.getTime();
        return isNaN(ms) ? -1 : ms;
    }

    function _planLabel(tier, subscription) {
        var t = String(tier || "");
        var m = /max_(\d+x)/i.exec(t);
        if (m)
            return "Max " + m[1].toUpperCase();
        var s = String(subscription || "");
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : "";
    }

    function _applyLimits(payload) {
        var session = payload.five_hour;
        var weekly = payload.seven_day_oauth_apps || payload.seven_day;
        var percentScale = root._percentScale([
            session ? session.utilization : undefined,
            weekly ? weekly.utilization : undefined
        ]);
        var sp = session ? root._normalizePercent(session.utilization, percentScale) : -1;
        var wp = weekly ? root._normalizePercent(weekly.utilization, percentScale) : -1;
        root.lastCheckedMs = Date.now();
        if (sp < 0 && wp < 0) {
            root.authHelpText = "Anthropic's usage endpoint returned no limits.";
            root.available = root.everHadLimits;
            root.lastProbeFailed = true;
            return;
        }
        if (sp >= 0) {
            root.sessionPercent = sp;
            root.sessionResetsAtMs = root._resetMs(session.resets_at);
        }
        if (wp >= 0) {
            root.weeklyPercent = wp;
            root.weeklyResetsAtMs = root._resetMs(weekly.resets_at);
        }
        root.available = true;
        root.everHadLimits = true;
        root.lastProbeFailed = false;
        root.lastUpdatedMs = root.lastCheckedMs;
        root._writeCache();
    }

    // a non-2xx response: curl still exits 0 and prints the error body, so
    // this is a separate path from the JSON.parse try/catch below -- an
    // error payload parses just fine, it just isn't a usage record, and
    // treating it as "valid JSON with no limits" was exactly what turned a
    // 429 into a false "no limits at all" (and, before everHadLimits, wiped
    // an already-good reading over one rate-limited probe).
    function _applyLimitsError(status) {
        root.authHelpText = status === 429
            ? "Anthropic's usage endpoint is rate-limiting checks right now. Retrying shortly."
            : status > 0
            ? "Anthropic's usage endpoint returned status " + status + "."
            : "Couldn't reach Anthropic's usage endpoint.";
        root.available = root.everHadLimits;
        root.lastProbeFailed = true;
        root.lastCheckedMs = Date.now();
    }

    // ---- local-stats parsing --------------------------------------------

    // last 7 calendar days ending today, pre-seeded to 0 so a quiet day shows
    // as an empty bar instead of vanishing from the strip.
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
        models.sort(function (a, b) { return b.total - a.total; });
        root.modelUsage = models.slice(0, 4);

        root.localStatsAvailable = true;
        root.lastLocalStatsMs = Date.now();
        root._writeCache();
    }

    // ---- cache: last-good reading survives a restart -----------------------

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
        var text = cacheFile.text();
        if (!text || text.length === 0)
            return;
        try {
            var c = JSON.parse(text);
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
        path: root.stateDir + "/agent-usage-claude.json"
        blockLoading: true
        printErrors: false
    }

    // read fresh (not watched -- the credentials file only needs checking
    // right before a probe) so a token rotated by `claude auth login` is
    // picked up on the very next poll instead of waiting on a stale watch.
    FileView {
        id: tokenFile
        path: root.credentialsPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            var token = "";
            try {
                var data = JSON.parse(tokenFile.text());
                var login = data.claudeAiOauth || {};
                token = login.accessToken || "";
                root.planLabel = root._planLabel(login.rateLimitTier, login.subscriptionType);
            } catch (e) {}
            if (token.length === 0) {
                root.available = root.everHadLimits;
                root.authHelpText = "Run `claude auth login` to see usage.";
                root.lastProbeFailed = true;
                root.lastCheckedMs = Date.now();
                return;
            }
            probeProc.token = token;
            probeProc.running = true;
        }
        onLoadFailed: {
            root.available = root.everHadLimits;
            root.authHelpText = "Run `claude auth login` to see usage.";
            root.lastProbeFailed = true;
            root.lastCheckedMs = Date.now();
        }
    }

    Process {
        id: probeProc
        property string token: ""
        // -w appends the HTTP status on its own trailing line: curl exits 0
        // and happily prints an error response body (a 429's JSON, an HTML
        // error page, ...) same as a real payload, so without checking this
        // separately, a rate-limited probe parses as "valid JSON, no limits
        // in it" instead of being recognized as the failure it is.
        command: ["curl", "-s", "--max-time", "8",
            "-w", "\n%{http_code}",
            "-H", "Authorization: Bearer " + probeProc.token,
            "-H", "anthropic-beta: oauth-2025-04-20",
            "-H", "Accept: application/json",
            "https://api.anthropic.com/api/oauth/usage"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = this.text;
                var splitAt = raw.lastIndexOf("\n");
                var body = splitAt >= 0 ? raw.slice(0, splitAt) : "";
                var status = Number(splitAt >= 0 ? raw.slice(splitAt + 1).trim() : raw.trim());
                if (!(status >= 200 && status < 300)) {
                    root._applyLimitsError(status || 0);
                    return;
                }
                try {
                    root._applyLimits(JSON.parse(body));
                } catch (e) {
                    // malformed body on an otherwise-2xx response -- same
                    // "couldn't reach it" message _applyLimitsError(0) gives
                    // a genuine transport failure, so just reuse it instead
                    // of duplicating the message/flag bookkeeping here.
                    root._applyLimitsError(0);
                }
            }
        }
    }

    // last 8 days of transcripts (by file mtime -- generous over the 7-day
    // display window so a session that started just before midnight isn't
    // lost), deduped by message id and summed per day / per model. jq is
    // already a dependency elsewhere in this shell (ryoku-plugins-place).
    // ~80MB / 70 files runs in a little over a second on a heavy transcript
    // history, so this rides the same poll cadence as the limits probe
    // rather than needing its own faster or slower timer.
    Process {
        id: scanProc
        // the projects path travels as $0 (bash's "$0" inside -c script is
        // the arg right after the script string), not string-interpolated
        // into the script itself, so it needs no shell-quoting of its own.
        command: ["bash", "-c",
            "find \"$0\" -name '*.jsonl' -mtime -8 -print0 2>/dev/null" +
            " | xargs -0 -r cat 2>/dev/null" +
            " | jq -c 'select((.type==\"assistant\") or (.message.role==\"assistant\"))" +
            " | (.message.usage // .usage) as $u | select($u != null)" +
            " | { id: (.message.id // .uuid // .requestId // \"\")," +
            "     day: ((.timestamp // .message.timestamp // \"\")[0:10])," +
            "     model: (.message.model // .model // \"claude\")," +
            "     tokens: (($u.input_tokens // $u.inputTokens // 0)" +
            "            + ($u.output_tokens // $u.outputTokens // 0)" +
            "            + ($u.cache_read_input_tokens // $u.cacheReadInputTokens // 0)" +
            "            + ($u.cache_creation_input_tokens // $u.cacheCreationInputTokens // 0)) }" +
            " | select(.tokens > 0 and .day != \"\")' 2>/dev/null" +
            " | jq -s '(if length == 0 then [] else unique_by(.id) end) as $rows" +
            " | { byDay: ($rows | group_by(.day) | map({key: .[0].day, value: (map(.tokens)|add)}) | from_entries)," +
            "     byModel: ($rows | group_by(.model) | map({key: .[0].model, value: (map(.tokens)|add)}) | from_entries) }'",
            root.projectsPath
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text);
                    root._applyLocalStats(r.byDay, r.byModel);
                } catch (e) {}
            }
        }
    }

    // the rate-limit probe is one small request, but Anthropic's usage
    // endpoint 429s a straight 1-minute cadence -- 2 minutes is the floor
    // that actually stays clear.
    Timer {
        interval: 120000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }

    // the local transcript scan is real CPU (~1.3s over a heavy history on
    // this machine) for daily-granularity numbers that don't need
    // minute-level freshness, so it rides its own slower clock.
    Timer {
        interval: 900000
        repeat: true
        running: root.active
        onTriggered: root.refreshIfStale()
    }
}
