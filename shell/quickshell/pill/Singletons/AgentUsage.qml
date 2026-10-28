pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The selected agent is the one the bar and popout report. Each source owns
// its provider-specific credentials, rate-limit probe, and transcript scan;
// this facade keeps the UI on one shared contract.
Singleton {
    id: root

    property bool active: false
    property string provider: "claude"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"

    readonly property var source: (provider === "antigravity" || provider === "gemini") ? antigravity : (provider === "codex" ? codex : claude)
    readonly property string providerName: (provider === "antigravity" || provider === "gemini") ? "Antigravity" : (provider === "codex" ? "Codex" : "Claude Code")
    readonly property string sessionLabel: source.sessionLabel
    readonly property string weeklyLabel: source.weeklyLabel
    readonly property bool available: source.available
    readonly property bool lastProbeFailed: source.lastProbeFailed
    readonly property bool localStatsAvailable: source.localStatsAvailable
    readonly property bool refreshing: source.refreshing
    readonly property real lastCheckedMs: source.lastCheckedMs
    readonly property real lastUpdatedMs: source.lastUpdatedMs
    readonly property string planLabel: source.planLabel
    readonly property int sessionPercent: source.sessionPercent
    readonly property int weeklyPercent: source.weeklyPercent
    readonly property real sessionResetsAtMs: source.sessionResetsAtMs
    readonly property real weeklyResetsAtMs: source.weeklyResetsAtMs
    readonly property string authHelpText: source.authHelpText
    readonly property var recentDays: source.recentDays
    readonly property var modelUsage: source.modelUsage

    readonly property string antigravityModelGroup: antigravity.modelGroup

    ClaudeUsage { id: claude }
    CodexUsage { id: codex }
    AntigravityUsage { id: antigravity }

    function selectAntigravityModelGroup(group) {
        antigravity.selectModelGroup(group);
    }

    function _syncActive() {
        claude.active = root.active && root.provider === "claude";
        codex.active = root.active && root.provider === "codex";
        antigravity.active = root.active && (root.provider === "antigravity" || root.provider === "gemini");
    }

    function selectProvider(name) {
        var p = name === "gemini" ? "antigravity" : name;
        if (p !== "claude" && p !== "codex" && p !== "antigravity")
            return;
        if (root.provider !== p) {
            root.provider = p;
            selectedProviderFile.setText(p);
        }
        if (root.active)
            root.source.refreshIfStale();
    }

    function refresh() {
        root.source.refresh();
    }

    function refreshNow() {
        root.source.refreshNow();
    }

    function formatTokenCount(n) {
        return root.source.formatTokenCount(n);
    }

    onActiveChanged: {
        root._syncActive();
        if (root.active)
            root.source.refreshIfStale();
    }
    onProviderChanged: root._syncActive()
    Component.onCompleted: {
        var saved = selectedProviderFile.text().trim();
        if (saved === "gemini")
            saved = "antigravity";
        if (saved === "claude" || saved === "codex" || saved === "antigravity")
            root.provider = saved;
        root._syncActive();
    }

    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }

    FileView {
        id: selectedProviderFile
        path: root.stateDir + "/agent-usage-provider"
        blockLoading: true
        printErrors: false
    }
}
