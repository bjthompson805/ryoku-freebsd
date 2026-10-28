pragma Singleton
import QtQuick
import Quickshell

/**
 * app/window icon resolution for Hyprland toplevels. a window class often
 * differs from its icon-theme name, so match the class to a desktop entry id
 * first, fall back to a direct icon-theme lookup. shared by every surface
 * that paints a window icon (minimized tray, ws switcher).
 */
Singleton {
    // Proton/Steam windows all report one of these generic wrapper classes
    // regardless of which game they are, so class-based icon lookup goes
    // blank for them -- fall back to matching the window title instead.
    readonly property var genericClasses: ({
        "steam_proton": true,
        "steam_app": true
    })

    // for a generic wrapper class, match the window title against installed
    // desktop entries' Name (case-insensitive substring, either direction so
    // a longer launcher Name still matches a shorter in-game title and vice
    // versa). to teach this a new title, no change is needed here -- just
    // drop a .desktop entry (see wowclassic.desktop) with a Name that
    // appears in that window's title, an Icon set, and
    // Categories=X-Ryoku-IconLookup; so the launcher hides it (see
    // launcher/providers/apps/Apps.qml). NoDisplay=true would hide it from
    // the launcher too, but Quickshell's DesktopEntries.applications drops
    // NoDisplay entries entirely, which would make them invisible to this
    // lookup as well -- hence the separate marker category instead.
    function titleLookup(title) {
        if (!title)
            return null;
        var t = title.toLowerCase();
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            var n = e && e.name ? e.name.toLowerCase() : "";
            if (n.length >= 4 && (t.indexOf(n) >= 0 || n.indexOf(t) >= 0))
                return e;
        }
        return null;
    }

    // collapse a raw (class, title) pair down to the key icon lookups should
    // use: the class as-is for normal apps, or a title-matched desktop
    // entry's id for the generic Proton/Steam wrapper classes.
    function resolveIconKey(cls, title) {
        if (cls && genericClasses[cls.toLowerCase()] && title) {
            var e = titleLookup(title);
            if (e)
                return e.id;
        }
        return cls;
    }

    // resolve an icon path from a raw window class / app-id string, e.g.
    // ToplevelManager.activeToplevel.appId (a generic wlr toplevel, not a
    // Hyprland one -- iconFor below can't be used there, it needs the
    // Hyprland-specific class/appId fields). title, when available, breaks
    // ties for windows sharing a generic wrapper class (see resolveIconKey).
    function iconForClass(cls, title) {
        var key = resolveIconKey(cls, title);
        if (!key)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (e && e.id && e.id.toLowerCase() === key.toLowerCase() && e.icon)
                return Quickshell.iconPath(e.icon, "application-x-executable");
        }
        return Quickshell.iconPath(key, "application-x-executable");
    }

    function iconFor(t) {
        var cls = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class
            : (t && t.wayland && t.wayland.appId ? t.wayland.appId : "");
        var title = (t && t.lastIpcObject && t.lastIpcObject.title) ? t.lastIpcObject.title
            : (t && t.title ? t.title : "");
        return iconForClass(cls, title);
    }
}
