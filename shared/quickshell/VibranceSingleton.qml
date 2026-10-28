pragma Singleton
import QtQuick

// Trivial singleton wrapper around VibranceCore, mirroring SpawnSingleton.qml.
// Symlinked in as Vibrance.qml in each root's Singletons/ directory,
// alongside the VibranceCore.qml symlink it depends on.
VibranceCore {
    id: root
}
