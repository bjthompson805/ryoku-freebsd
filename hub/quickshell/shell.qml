import QtQuick
import Quickshell

// Ryoku Settings entry point. A normal floating window (not a layer-shell
// surface); the Hyprland window rule floats and centres it. `qs -c hub` loads
// this (the config dir and binary keep the internal "hub" name).
ShellRoot {
    id: root

    // Pages stream remote images (lock skin gifs, store previews) through the
    // QML engine's network manager. Tearing the engine down with one of those
    // downloads in flight double-deletes its QNetworkReply and aborts qs, so
    // unload the hub first (which cancels them) and quit on the next tick.
    function quit() {
        content.active = false;
        Qt.callLater(Qt.quit);
    }

    FloatingWindow {
        id: win
        title: "Ryoku Settings"
        minimumSize: Qt.size(900, 600)

        // The launcher keybind (Super+,) guards against a second instance with
        // `flock` on /tmp/ryoku-hub.lock, held for the life of this process.
        // Closing the window through the compositor (Super+Q) only hides it
        // while qs keeps running, which would pin the lock and make Super+,
        // silently no-op until the orphan is killed. Quit on every close so the
        // lock always releases.
        onClosed: root.quit()

        Loader {
            id: content
            anchors.fill: parent
            focus: true
            sourceComponent: Hub {
                onQuitRequested: root.quit()
            }
        }
    }
}
