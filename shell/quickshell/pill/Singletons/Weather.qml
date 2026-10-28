pragma Singleton
import QtQuick
import Quickshell.Io
import "../lib/weather.js" as Model

// pill's copy: the only root with an explicit-location setting (Config.
// weatherLocation, a typed city name), so the only one that needs geocoding
// on top of the shared WeatherCore implementation. resolveLocation()/writeLoc()
// override WeatherCore's defaults -- QML function overrides resolve on the
// final composed object, same mechanism launcher/Singletons/Spawn.qml already
// relies on for SpawnCore.
WeatherCore {
    id: root

    // the query a request was actually made for, captured when it starts. writeLoc()
    // tags the cache with THIS, not a live read of Config.weatherLocation -- if the
    // location field is edited again while a geocode/IP lookup is still in flight,
    // the live value would already be the new one by the time the old response lands,
    // mislabeling stale (e.g. IP-resolved) coordinates under the new query. Since
    // resolveLocation() also queues (via the base's locating/pendingLocate) rather
    // than overlapping requests, this only ever holds the query for the response
    // actually being applied.
    property string requestedQuery: ""

    // resolve coords: an explicit Config.weatherLocation wins (geocoded), else the
    // cached coords for the same query, else the base's IP lookup. the cache is
    // keyed by the query, so a restart skips the round-trip only while the
    // location is unchanged.
    function resolveLocation() {
        if (root.locating) {
            root.pendingLocate = true;
            return;
        }
        if (!Config.generalReady) {
            // general.json hasn't finished its async load yet, so
            // Config.weatherLocation still reads "" -- indistinguishable from a
            // deliberately-blank (auto/IP) location. Show cached coords as a
            // best guess without committing to a target or touching the network;
            // onGeneralReadyChanged below re-resolves for real once it lands.
            var cached = Model.parseJson(root._readLocFile());
            if (cached && typeof cached.lat === "number" && typeof cached.lon === "number") {
                root.city = cached.city || "";
                root.lat = cached.lat;
                root.lon = cached.lon;
                root.located = true;
                root.fetchWeather();
            }
            return;
        }
        var target = Config.weatherLocation.trim();
        var c = Model.parseJson(root._readLocFile());
        if (c && c.query === target && typeof c.lat === "number" && typeof c.lon === "number") {
            root.city = c.city || "";
            root.lat = c.lat;
            root.lon = c.lon;
            root.located = true;
            root.fetchWeather();
            return;
        }
        root.requestedQuery = target;
        if (target.length > 0) {
            root.locating = true;
            geoProc.running = true;
        } else {
            root._geolocateByIp();
        }
    }

    function writeLoc() {
        root._writeLocFile(JSON.stringify({ query: root.requestedQuery, city: root.city, lat: root.lat, lon: root.lon }));
    }

    Connections {
        target: Config
        function onWeatherLocationChanged() { root.located = false; root.resolveLocation(); }
        // fires once general.json's async load settles; needed in addition to
        // onWeatherLocationChanged above because a genuinely-blank saved location
        // (auto/IP) never actually changes value, so that signal alone would never
        // fire and the early return above would wait forever.
        function onGeneralReadyChanged() { root.located = false; root.resolveLocation(); }
    }

    // geocode an explicit location via Open-Meteo's keyless geocoding API.
    Process {
        id: geoProc
        command: ["curl", "-s", "--max-time", "8",
            "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name="
            + encodeURIComponent(Config.weatherLocation.trim())]
        stdout: StdioCollector {
            onStreamFinished: {
                var g = Model.parseGeo(Model.parseJson(this.text));
                if (g) {
                    root.city = g.city;
                    root.lat = g.lat;
                    root.lon = g.lon;
                    root.located = true;
                    root.writeLoc();
                    root.fetchWeather();
                }
                root._locateFinished();
            }
        }
    }
}
