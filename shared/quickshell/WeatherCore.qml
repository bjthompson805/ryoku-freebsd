import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/weather.js" as Model

// Shared base for every root's Weather singleton (see the per-root Weather.qml,
// which is `WeatherCore { id: root }` for a plain consumer, extended with an
// explicit-location override in pill's copy -- QML function overrides resolve
// on the final composed object, same mechanism this codebase already relies on
// for SpawnCore.qml and launcher/providers/Provider.qml's overridable query()).
// Not a singleton itself -- pragma Singleton types can't be used as an
// inheritance base -- so this is a plain component. One real file, symlinked
// into every consuming root's Singletons/ dir, same trick as SpawnCore.qml.
//
// Open-Meteo, no API key. Location resolves via a keyless IP lookup by
// default (resolveLocation() below is a hook: pill overrides it to try an
// explicit configured location first, geocoded, before falling back to IP).
// The last-fetched forecast is cached to disk and replayed on startup so a
// restart opens on weather, not a bare loading state; a failed first
// geolocate (offline boot, DNS hiccup) retries on the same cadence as the
// regular poll rather than staying dead until the next restart. public
// contract = temp / condition / glyph / available, unchanged from the old
// wttr.in version. hourly / daily / humidity / city / sunrise / sunset for
// richer panes. all parsing + the WMO-code -> glyph/label map live in
// lib/weather.js (unit-tested under node); this singleton just fetches and
// assigns. unit follows the locale (F for US/LR/MM, C elsewhere) unless a
// consumer sets unitOverride. Rooted on Quickshell's Singleton type (not
// QtObject, unlike SpawnCore) so Process/FileView/Timer children can be
// declared directly instead of through SpawnCore's Component+createObject()
// indirection -- Singleton has a default property to hold them, QtObject
// doesn't. No `pragma Singleton` here, deliberately: that pragma is what
// makes a type unusable as an inheritance base, not the Singleton type
// itself, so this file stays a plain (if singleton-shaped) component.
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"

    // "" follows the locale; "C"/"F" force it. Deliberately config-agnostic --
    // this base doesn't know about any particular Config singleton (mirrors
    // SpawnCore never touching one either), so a consumer wires its own
    // settings in with an external Binding, e.g.
    //   Binding { target: Weather; property: "unitOverride"; value: ... }
    property string unitOverride: ""
    readonly property string unit: unitOverride === "C" ? "celsius"
        : unitOverride === "F" ? "fahrenheit"
        : Model.unitFor(Quickshell.env("LC_MEASUREMENT") || Quickshell.env("LANG") || "")
    onUnitChanged: if (root.located) root.fetchWeather()

    // public contract, identical to the old wttr.in version.
    property string temp: ""
    property string condition: ""
    property string glyph: "cloud"
    property bool available: false

    // richer data, ready for an hourly / 5-day pane (+ a sun-position widget).
    property int tempNow: 0
    property int humidity: 0
    property bool isDay: true
    property int sunrise: -1
    property int sunset: -1
    property string city: ""
    property var hourly: []
    property var daily: []

    property real lat: 0
    property real lon: 0
    property bool located: false

    // true while an IP lookup or (pill's override) a geocode is in flight.
    // resolveLocation() queues instead of overlapping requests -- see
    // pill/Singletons/Weather.qml's header comment for the race this closes.
    property bool locating: false
    property bool pendingLocate: false

    // the unit a fetch was requested in, so applyForecast formats with the SAME
    // unit the data came back in even if the setting changed mid-request; a unit
    // change while a fetch is in flight queues one more via pendingFetch.
    property string fetchUnit: ""
    property bool pendingFetch: false

    function fetchWeather() {
        if (!root.located)
            return;
        if (wxProc.running) {
            root.pendingFetch = true;
            return;
        }
        root.fetchUnit = root.unit;
        wxProc.running = true;
    }

    function applyForecast(text) {
        var f = Model.parseForecast(Model.parseJson(text), root.fetchUnit);
        if (!f.available)
            return;
        root.tempNow = f.tempNow;
        root.temp = f.temp;
        root.condition = f.condition;
        root.glyph = f.glyph;
        root.humidity = f.humidity;
        root.isDay = f.isDay;
        root.sunrise = f.sunrise;
        root.sunset = f.sunset;
        root.hourly = f.hourly;
        root.daily = f.daily;
        root.available = true;
        wxCache.setText(text);           // cache the forecast so the next start opens on weather, not a bare loading state
    }

    // ---- location: hooks a subclass can override --------------------------

    // default: cached coords if we have any, else a keyless IP lookup. pill's
    // Weather.qml overrides this to try an explicit configured location
    // (geocoded) first, falling back to _geolocateByIp() for the rest.
    function resolveLocation() {
        if (root.locating) {
            root.pendingLocate = true;
            return;
        }
        var c = Model.parseJson(locCache.text());
        if (c && typeof c.lat === "number" && typeof c.lon === "number") {
            root.city = c.city || "";
            root.lat = c.lat;
            root.lon = c.lon;
            root.located = true;
            root.fetchWeather();
        } else {
            root._geolocateByIp();
        }
    }

    // default: {city, lat, lon}. pill's override adds the query it was
    // resolved from, so the cache can be keyed by (and invalidated on) that
    // query changing.
    function writeLoc() {
        root._writeLocFile(JSON.stringify({ city: root.city, lat: root.lat, lon: root.lon }));
    }

    // ---- internals: kept as functions (not bare ids) so an overriding
    // resolveLocation()/writeLoc() in a derived file can still drive them --
    // ids declared in this file aren't nameable from a derived file's own
    // QML, only through an exposed function call. ----------------------------

    function _geolocateByIp() {
        root.locating = true;
        ipProc.running = true;
    }

    // common end-of-request hook for both ipProc and (pill's override's) geoProc --
    // called unconditionally, success or failure, so a queued resolveLocation()
    // (from a config change that arrived mid-request) always gets its turn instead
    // of racing the in-flight request and possibly overwriting its result.
    function _locateFinished() {
        root.locating = false;
        if (root.pendingLocate) {
            root.pendingLocate = false;
            root.resolveLocation();
        }
    }

    function _readLocFile() {
        return locCache.text();
    }

    function _writeLocFile(text) {
        locCache.setText(text);
    }

    Component.onCompleted: {
        // replay the last cached forecast instantly so the card opens on weather
        // rather than a bare state; the fresh fetch below overwrites it a moment later.
        var w = wxCache.text();
        if (w && w.length > 0)
            root.applyForecast(w);
        root.resolveLocation();
    }

    // fresh profile may not have the state dir; mkdir before writeLoc touches it.
    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }

    FileView {
        id: locCache
        path: root.stateDir + "/weather-loc.json"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: wxCache
        path: root.stateDir + "/weather-cache.json"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: ipProc
        command: ["curl", "-s", "--max-time", "8", "http://ip-api.com/json/?fields=status,city,lat,lon"]
        stdout: StdioCollector {
            onStreamFinished: {
                var loc = Model.parseLoc(Model.parseJson(this.text));
                if (loc) {
                    root.city = loc.city;
                    root.lat = loc.lat;
                    root.lon = loc.lon;
                    root.located = true;
                    root.writeLoc();
                    root.fetchWeather();
                }
                root._locateFinished();
            }
        }
    }

    Process {
        id: wxProc
        command: ["curl", "-s", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.lat
            + "&longitude=" + root.lon
            + "&current=temperature_2m,weather_code,is_day,relative_humidity_2m"
            + "&hourly=temperature_2m,weather_code&forecast_hours=24"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&forecast_days=5"
            + "&timezone=auto&temperature_unit=" + root.fetchUnit]
        stdout: StdioCollector {
            onStreamFinished: {
                root.applyForecast(this.text);
                if (root.pendingFetch) {
                    root.pendingFetch = false;
                    root.fetchWeather();
                }
            }
        }
    }

    Timer {
        interval: 900000
        running: true
        repeat: true
        // a failed first geolocate (offline boot, DNS hiccup) used to leave
        // weather dead until restart; retry through the same resolveLocation()
        // hook a subclass overrides, on the same cadence as the regular poll.
        onTriggered: {
            if (!root.located) {
                root.resolveLocation();
                return;
            }
            root.fetchWeather();
        }
    }
}
