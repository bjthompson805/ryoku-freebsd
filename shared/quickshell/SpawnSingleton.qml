pragma Singleton
import QtQuick

// Trivial singleton wrapper around SpawnCore for every root that doesn't need
// the launcher's extra registry (see launcher/Singletons/Spawn.qml for that
// one — the only root with a search-results UI to key a live count against).
// Symlinked in as Spawn.qml in each of those roots' Singletons/ directory,
// alongside the SpawnCore.qml symlink it depends on.
SpawnCore {
    id: root
}
