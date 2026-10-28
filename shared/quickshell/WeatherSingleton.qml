pragma Singleton
import QtQuick

// Trivial singleton wrapper around WeatherCore for every root that doesn't
// need pill's explicit-location override (see pill/Singletons/Weather.qml for
// that one). Symlinked in as Weather.qml in each of those roots' Singletons/
// directory, alongside the WeatherCore.qml symlink it depends on.
WeatherCore {
    id: root
}
