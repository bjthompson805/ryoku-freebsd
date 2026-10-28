pragma Singleton
import QtQuick

// This is the launcher's copy: the only root with a search-results UI, so the
// only one that needs a live registry (counts/logsById) on top of the shared
// SpawnCore implementation, so rows can show "N launched" and offer a
// "View log(s)" action. _track/_untrack/_forget override SpawnCore's no-op
// defaults — QML resolves overrides on the final composed object, the same
// mechanism this codebase already relies on for
// launcher/providers/Provider.qml's overridable query().
SpawnCore {
    id: root

    property var counts: ({})     // { rowId: liveCount }
    property var logsById: ({})   // { rowId: [{path, cmd, startedAt, pid, exitCode}, ...] }, newest first, capped
    property int revision: 0      // bumped alongside counts/logsById; belt-and-suspenders re-bind hook

    function countFor(id) { return root.counts[id] || 0; }
    function logsFor(id) { return root.logsById[id] || []; }

    function _track(id, entry) {
        if (!id)
            return;
        var c = root.counts;
        c[id] = (c[id] || 0) + 1;
        root.counts = c;

        var l = root.logsById;
        var list = (l[id] || []).slice();
        list.unshift(entry);
        if (list.length > 5)
            list = list.slice(0, 5);
        l[id] = list;
        root.logsById = l;

        root.revision++;
    }

    function _untrack(id) {
        if (!id)
            return;
        var c = root.counts;
        c[id] = Math.max(0, (c[id] || 0) - 1);
        root.counts = c;
        root.revision++;
    }

    // Drops one specific entry (matched by reference, not just id — a row can
    // have several concurrent invocations) once its process exits cleanly.
    function _forget(id, entry) {
        if (!id)
            return;
        var l = root.logsById;
        var list = (l[id] || []).filter(function (e) { return e !== entry; });
        l[id] = list;
        root.logsById = l;
        root.revision++;
    }
}
