pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// laptop battery state for the pill, from UPower's display device. gated so a
// desktop without a battery reports present=false (hover cluster + 蓄 surface
// stay hidden). exposes pct, charge state, signed draw/charge wattage,
// capacity, optional health, plus a formatted time-to-empty/full string. low
// = present, discharging and <=20% -- gated on present so the pre-UPower
// startup window (batDev null, pct reads 0) can't read as a false low. also
// carries UPower's charge limit and the "holding" state it produces.
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice

    // synthetic displayDevice omits Capacity (health); pull it from the real
    // physical battery in the device list instead.
    readonly property var batDev: {
        var list = UPower.devices ? UPower.devices.values : [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].isLaptopBattery && list[i].isPresent)
                return list[i];
        }
        return dev;
    }

    // presence comes from the physical battery pick: the synthetic display
    // device drops ready/isLaptopBattery on some upower versions once the
    // cell sits fully charged on AC, which blanked every battery readout.
    readonly property bool present: batDev !== null && batDev.isLaptopBattery && batDev.isPresent
    readonly property real frac: batDev ? Math.max(0, Math.min(1, batDev.percentage)) : 0
    readonly property int pct: Math.round(frac * 100)
    readonly property int state: batDev ? batDev.state : UPowerDeviceState.Unknown

    // charge limit, from UPower's charge-threshold support. Quickshell's UPower
    // binding has no threshold properties, so these come from the
    // ryoku-charge-limit helper (see refreshLimit).
    property bool limitSupported: false
    property bool limitEnabled: false
    property int limitEnd: 0
    property int limitMin: 50
    // lift the limit at poweroff so the battery fills while the machine is off;
    // the next boot re-applies it.
    property bool limitFullWhenOff: false

    // a percentage change finished (saved, refused, or a prompt dismissed)
    // and limitEnd has been re-read, so an edited field can drop its draft.
    signal limitSettled()
    property bool limitSetting: false
    property int queuedLimit: -1

    readonly property bool powerIn: state === UPowerDeviceState.Charging
    // on AC but parked at the limit. firmware reports that three ways: pending
    // charge, "full" well below 100%, or (this Samsung, among others) still
    // "charging" once the cell reaches the limit. above the limit that last
    // case holds whatever the rate says: a battery without a power reading gets
    // its rate from the energy delta, so settling down to a lowered limit shows
    // as watts "charging" though nothing flows in.
    readonly property bool holding: present && limitEnabled && !UPower.onBattery
        && (state === UPowerDeviceState.PendingCharge
            || (state === UPowerDeviceState.FullyCharged && pct < 99)
            || (powerIn && (frac * 100 > limitEnd
                || (Math.abs(batDev.changeRate) < 0.05 && frac * 100 >= limitEnd - 1))))
    readonly property bool charging: powerIn && !holding
    readonly property bool full: !holding && (state === UPowerDeviceState.FullyCharged || pct >= 100)
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool low: present && !charging && pct <= 20

    readonly property real rateW: !batDev ? 0
        : (discharging ? -batDev.changeRate : (charging ? batDev.changeRate : 0))
    readonly property real capacityWh: batDev ? batDev.energyCapacity : 0

    readonly property bool healthSupported: batDev ? batDev.healthSupported : false
    readonly property int health: batDev ? Math.round(batDev.healthPercentage) : 0

    readonly property bool hasTime: !batDev ? false
        : (charging ? batDev.timeToFull > 0 : (discharging ? batDev.timeToEmpty > 0 : false))
    readonly property string timeStr: !batDev ? ""
        : (charging ? fmt(batDev.timeToFull) : (discharging ? fmt(batDev.timeToEmpty) : ""))

    readonly property string stateLabel: holding ? "Holding at " + limitEnd + "%"
        : (charging ? "Charging"
        : (full ? "On AC · Full"
        : (discharging ? "Discharging" : "On AC")))

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return h + "h " + m + "m";
        return m + "m";
    }

    // fire a real desktop notification on the discharging <=20% edge (not a
    // level, so plugging in and dropping back below 20% fires again) --
    // the pill/popout tint alone is easy to miss if the bar isn't in view.
    onLowChanged: {
        if (low)
            Spawn.spawn(["notify-send", "-u", "critical", "-i", "battery-caution",
                "-a", "Ryoku", "Battery low", pct + "% remaining"]);
    }

    function refreshLimit() {
        if (present && !limitStatus.running)
            limitStatus.running = true;
    }

    // UPower lets the active user toggle the limit, so no pkexec here. the
    // switch flips at once and the status re-read afterwards corrects it if
    // UPower refused.
    function setLimitEnabled(on) {
        limitEnabled = on;
        runLimit(["ryoku-charge-limit", on ? "on" : "off"]);
    }

    // a new percentage rewrites a udev rule and restarts upower, so it goes
    // through pkexec; 51-ryoku-charge-limit.rules lets wheel skip the password.
    // the opt-in is a root-owned flag the shutdown hook reads, so pkexec again.
    function setLimitFullWhenOff(on) {
        limitFullWhenOff = on;
        runLimit(["pkexec", "/usr/bin/ryoku-charge-limit", "full-when-off", on ? "on" : "off"]);
    }

    // a change made while the prompt is still up is queued, not dropped, so the
    // field never shows a number that was never sent.
    function setLimit(percent) {
        if (limitCmd.running) {
            queuedLimit = Math.round(percent);
            return;
        }
        limitSetting = true;
        runLimit(["pkexec", "/usr/bin/ryoku-charge-limit", "set", String(Math.round(percent))]);
    }

    function runLimit(argv) {
        if (limitCmd.running)
            return;
        limitCmd.command = argv;
        limitCmd.running = true;
    }

    onPresentChanged: refreshLimit()

    Connections {
        target: UPower
        function onOnBatteryChanged() { root.refreshLimit(); }
    }

    Process {
        id: limitStatus
        command: ["ryoku-charge-limit", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var kv = {};
                text.trim().split("\n").forEach(function (line) {
                    var parts = line.split(" ");
                    kv[parts[0]] = parts[1];
                });
                root.limitSupported = kv.supported === "true";
                root.limitEnabled = kv.enabled === "true";
                root.limitEnd = parseInt(kv.end) || 0;
                root.limitMin = parseInt(kv.min) || root.limitMin;
                root.limitFullWhenOff = kv.full_when_off === "true";
                if (root.limitSetting && !limitCmd.running) {
                    root.limitSetting = false;
                    root.limitSettled();
                }
            }
        }
    }

    Process {
        id: limitCmd
        stderr: StdioCollector { id: limitErr }
        onExited: function (exitCode) {
            // 126/127: the polkit prompt was dismissed, not a failure worth a toast.
            if (exitCode !== 0 && exitCode !== 126 && exitCode !== 127)
                Spawn.spawn(["notify-send", "-a", "Ryoku", "Charge limit not changed",
                    limitErr.text.trim() || ("ryoku-charge-limit exited " + exitCode)]);
            if (root.queuedLimit >= 0) {
                var next = root.queuedLimit;
                root.queuedLimit = -1;
                root.setLimit(next);
            } else {
                root.refreshLimit();
            }
        }
    }

    // upower restarts after a new percentage, and the limit can also change
    // from a terminal; a slow re-read keeps the popout honest either way.
    Timer {
        interval: 30000
        running: root.present
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshLimit()
    }
}
