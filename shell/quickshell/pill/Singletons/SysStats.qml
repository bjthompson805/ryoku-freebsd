pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// live system vitals for the Nacre bar's stats module, from FreeBSD sysctls:
// CPU% from kern.cp_times deltas, RAM% from the vm page counters (with the ZFS
// ARC counted as available, since it is released on demand), temperature from
// the CPU sensor or the ACPI thermal zone, disk I/O from iostat's cumulative
// counters, and disk usage from `df`. the poller runs only while `active` (a
// visible BarStats sets it), and keeps a short history for the resources
// popout sparklines.
Singleton {
    id: root

    property bool active: false
    property int cpu: 0
    property int mem: 0
    property int temp: 0
    property bool tempAvailable: false
    property int gpu: 0
    property bool gpuAvailable: false
    // disk usage barely moves, so it's reported as a plain snapshot rather
    // than a tracked history like the other metrics.
    property int disk: 0
    property bool diskAvailable: false
    property string diskUsed: ""
    property string diskTotal: ""
    // disk read/write throughput, bytes/sec, sampled on the same cadence as
    // CPU/mem (unlike the usage snapshot above, I/O rate moves fast enough
    // that a 10s poll would miss most of it).
    property int diskReadRate: 0
    property int diskWriteRate: 0
    property bool diskIOAvailable: false
    // bar-fill reference for the read/write rate bars in the popout: rates
    // rarely sustain past this, so it reads as "mostly full" under real load
    // without needing a proper adaptive scale.
    readonly property real diskIOMaxBps: 150 * 1024 * 1024
    property string _diskDev: ""
    property real _prevDiskReadKB: -1
    property real _prevDiskWriteKB: -1
    property real _prevDiskIOTs: 0

    function fmtRate(bps) {
        if (bps < 1024)
            return bps + " B/s";
        if (bps < 1024 * 1024)
            return (bps / 1024).toFixed(1) + " KB/s";
        return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    }

    // per-core CPU% (0-indexed, in kern.cp_times order). empty until the
    // second sample lands.
    property var cpuPerCore: []

    readonly property int histLen: 60
    property var cpuHistory: []
    property var memHistory: []
    property var tempHistory: []
    property var gpuHistory: []

    // previous kern.cp_times sample: [idle, total] per core, for the deltas.
    property var _prevCores: []

    // "amdgpu" when drm-kmod exposes gpu_busy_percent as a sysctl, "nvidia"
    // when nvidia-smi answers, else "none". resolved once.
    property string _gpuBackend: ""
    // per-engine busy% for the popout's engine-bar row, e.g. [{name:"sm",
    // pct:12}, ...].
    property var gpuEngines: []

    function _push(arr, v) {
        var a = arr.slice();
        a.push(v);
        if (a.length > root.histLen)
            a.shift();
        return a;
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            sysctlProc.running = true;
            if (root._diskDev.length > 0)
                diskIOProc.running = true;
        }
    }

    Timer {
        // disk usage barely moves tick to tick; polling it at the CPU/mem
        // rate would just be a subprocess spawned for nothing.
        interval: 10000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: diskProc.running = true
    }

    // kern.cp_times: five counters per core (user nice sys intr idle).
    function _applyCpTimes(fields) {
        var prev = root._prevCores;
        var next = [];
        var cores = [];
        var dIdleAll = 0, dTotalAll = 0;
        for (var c = 0; c + 4 < fields.length; c += 5) {
            var idle = Number(fields[c + 4]);
            var total = 0;
            for (var j = 0; j < 5; j++)
                total += Number(fields[c + j]);
            var i = c / 5;
            next.push([idle, total]);
            if (prev[i]) {
                var dIdle = idle - prev[i][0];
                var dTotal = total - prev[i][1];
                dIdleAll += dIdle;
                dTotalAll += dTotal;
                cores.push(dTotal > 0 ? Math.max(0, Math.min(100, Math.round(100 * (1 - dIdle / dTotal)))) : 0);
            }
        }
        root._prevCores = next;
        if (cores.length > 0 && dTotalAll > 0) {
            root.cpuPerCore = cores;
            root.cpu = Math.max(0, Math.min(100, Math.round(100 * (1 - dIdleAll / dTotalAll))));
            root.cpuHistory = root._push(root.cpuHistory, root.cpu);
        }
    }

    // one sysctl call per tick. -i skips the names this machine lacks (no ZFS,
    // no CPU temperature driver), so values are read back by name.
    Process {
        id: sysctlProc
        command: ["sysctl", "-i", "kern.cp_times", "hw.physmem", "hw.pagesize",
            "vm.stats.vm.v_free_count", "vm.stats.vm.v_inactive_count",
            "kstat.zfs.misc.arcstats.size", "dev.cpu.0.temperature",
            "hw.acpi.thermal.tz0.temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = {};
                (this.text || "").split("\n").forEach(function (ln) {
                    var at = ln.indexOf(": ");
                    if (at > 0)
                        v[ln.slice(0, at)] = ln.slice(at + 2).trim();
                });

                if (v["kern.cp_times"])
                    root._applyCpTimes(v["kern.cp_times"].split(/\s+/));

                var physmem = Number(v["hw.physmem"] || 0);
                var page = Number(v["hw.pagesize"] || 0);
                if (physmem > 0 && page > 0) {
                    var avail = (Number(v["vm.stats.vm.v_free_count"] || 0) + Number(v["vm.stats.vm.v_inactive_count"] || 0)) * page
                        + Number(v["kstat.zfs.misc.arcstats.size"] || 0);
                    root.mem = Math.max(0, Math.min(100, Math.round(100 * (physmem - avail) / physmem)));
                    root.memHistory = root._push(root.memHistory, root.mem);
                }

                var t = parseFloat(v["dev.cpu.0.temperature"] || v["hw.acpi.thermal.tz0.temperature"] || "");
                if (t > 0) {
                    root.temp = Math.round(t);
                    root.tempAvailable = true;
                    root.tempHistory = root._push(root.tempHistory, root.temp);
                } else {
                    root.tempAvailable = false;
                }
            }
        }
    }

    // detect the GPU load source once. amdgpu's sysfs busy counters surface
    // under sys.device.drmn0; Intel has no equivalent on FreeBSD, so it shows
    // no load.
    Process {
        id: gpuResolve
        running: root.active && root._gpuBackend.length === 0
        command: ["sh", "-c", "if sysctl -n sys.device.drmn0.gpu_busy_percent >/dev/null 2>&1; then echo amdgpu; " +
            "elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits >/dev/null 2>&1; then echo nvidia; " +
            "else echo none; fi"]
        stdout: StdioCollector {
            onStreamFinished: root._gpuBackend = (this.text || "").trim() || "none"
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active && root._gpuBackend === "nvidia"
        triggeredOnStart: true
        onTriggered: gpuNvidiaProc.running = true
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active && root._gpuBackend === "amdgpu"
        triggeredOnStart: true
        onTriggered: gpuAmdProc.running = true
    }

    // graphics/compute and the VCN video block (encode + decode).
    Process {
        id: gpuAmdProc
        command: ["sysctl", "-i", "sys.device.drmn0.gpu_busy_percent", "sys.device.drmn0.vcn_busy_percent"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = {};
                (this.text || "").split("\n").forEach(function (ln) {
                    var at = ln.indexOf(": ");
                    if (at > 0)
                        v[ln.slice(ln.lastIndexOf(".", at) + 1, at)] = Number(ln.slice(at + 2).trim());
                });
                var gfx = v["gpu_busy_percent"];
                if (gfx === undefined || isNaN(gfx)) {
                    root.gpuAvailable = false;
                    return;
                }
                var clamp = function (n) { return Math.max(0, Math.min(100, Math.round(n))); };
                var engines = [{ name: "gfx", pct: clamp(gfx) }];
                if (v["vcn_busy_percent"] !== undefined && !isNaN(v["vcn_busy_percent"]))
                    engines.push({ name: "video", pct: clamp(v["vcn_busy_percent"]) });
                root.gpuEngines = engines;
                root.gpu = engines[0].pct;
                root.gpuHistory = root._push(root.gpuHistory, root.gpu);
                root.gpuAvailable = true;
            }
        }
    }

    Process {
        id: gpuNvidiaProc
        // SM (general compute/3D), memory controller, video encoder, video
        // decoder.
        command: ["sh", "-c", "nvidia-smi --query-gpu=utilization.gpu,utilization.memory,utilization.encoder,utilization.decoder --format=csv,noheader,nounits | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = (this.text || "").trim().split(",").map(function (s) { return Number(s.trim()); });
                if (parts.length === 4 && parts.every(function (n) { return !isNaN(n); })) {
                    var names = ["sm", "mem", "enc", "dec"];
                    root.gpuEngines = names.map(function (n, i) {
                        return { name: n, pct: Math.max(0, Math.min(100, Math.round(parts[i]))) };
                    });
                    root.gpu = root.gpuEngines[0].pct;
                    root.gpuHistory = root._push(root.gpuHistory, root.gpu);
                    root.gpuAvailable = true;
                } else {
                    root.gpuAvailable = false;
                }
            }
        }
    }

    // resolve the whole disk under the home dir once: a ZFS dataset maps to its
    // pool's first vdev, a UFS /dev node is used directly, and the partition
    // suffix (p4, s1a) is stripped since iostat reports whole disks.
    Process {
        id: diskDevResolve
        running: root.active && root._diskDev.length === 0
        command: ["sh", "-c",
            "src=$(df \"$HOME\" | awk 'NR==2{print $1}'); " +
            "case \"$src\" in /dev/*) d=$src;; " +
            "*) d=$(zpool list -vHP \"${src%%/*}\" 2>/dev/null | awk '$1 ~ /^\\/dev\\//{print $1; exit}');; esac; " +
            "d=${d#/dev/}; echo \"$d\" | sed -E 's/(p[0-9]+|s[0-9]+[a-h]?)$//'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = (this.text || "").trim();
                if (d.length > 0)
                    root._diskDev = d;
            }
        }
    }

    // iostat -I: cumulative KB read/written since boot (kr/i, kw/i columns).
    Process {
        id: diskIOProc
        command: ["iostat", "-I", "-x", "-d", root._diskDev]
        stdout: StdioCollector {
            onStreamFinished: {
                var row = (this.text || "").split("\n").filter(function (ln) {
                    return ln.trim().split(/\s+/)[0] === root._diskDev;
                })[0];
                if (!row)
                    return;
                var f = row.trim().split(/\s+/);
                var readKB = Number(f[3]);
                var writeKB = Number(f[4]);
                var now = Date.now();
                if (root._prevDiskIOTs > 0) {
                    var dt = (now - root._prevDiskIOTs) / 1000;
                    if (dt > 0) {
                        root.diskReadRate = Math.max(0, Math.round((readKB - root._prevDiskReadKB) * 1024 / dt));
                        root.diskWriteRate = Math.max(0, Math.round((writeKB - root._prevDiskWriteKB) * 1024 / dt));
                        root.diskIOAvailable = true;
                    }
                }
                root._prevDiskReadKB = readKB;
                root._prevDiskWriteKB = writeKB;
                root._prevDiskIOTs = now;
            }
        }
    }

    // usage of the filesystem backing the home dir (covers the common
    // separate-/home case without hardcoding a mountpoint): capacity, used,
    // size from BSD df's columns.
    Process {
        id: diskProc
        command: ["sh", "-c", "df -h \"$HOME\" | awk 'NR==2{print $5, $3, $2}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = (this.text || "").trim().split(/\s+/);
                var v = f.length === 3 ? Number(f[0].replace("%", "")) : NaN;
                if (!isNaN(v)) {
                    root.disk = Math.max(0, Math.min(100, v));
                    root.diskUsed = f[1];
                    root.diskTotal = f[2];
                    root.diskAvailable = true;
                } else {
                    root.diskAvailable = false;
                }
            }
        }
    }
}
