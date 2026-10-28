pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// live system vitals for the Nacre bar's stats module: CPU% from /proc/stat
// deltas, RAM% from /proc/meminfo, temperature from a /sys thermal zone, disk
// usage from `df`. all kernel-native except the disk poll (the zone path is
// resolved once). the poller runs only while `active` (a visible BarStats
// sets it), and keeps a short history for the resources popout sparklines.
Singleton {
    id: root

    property bool active: false
    property int cpu: 0
    property int mem: 0
    property int temp: 0
    property bool tempAvailable: false
    property int npu: 0
    property bool npuAvailable: false
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
    property real _prevDiskReadSectors: -1
    property real _prevDiskWriteSectors: -1
    property real _prevDiskIOTs: 0

    function fmtRate(bps) {
        if (bps < 1024)
            return bps + " B/s";
        if (bps < 1024 * 1024)
            return (bps / 1024).toFixed(1) + " KB/s";
        return (bps / 1024 / 1024).toFixed(1) + " MB/s";
    }

    // per-core CPU% (0-indexed, in /proc/stat order). empty until the first
    // sample lands.
    property var cpuPerCore: []

    readonly property int histLen: 60
    property var cpuHistory: []
    property var memHistory: []
    property var tempHistory: []
    property var npuHistory: []
    property var gpuHistory: []

    // previous /proc/stat aggregate sample, for the busy-fraction delta.
    property real _prevIdle: 0
    property real _prevTotal: 0
    // previous per-core samples, indexed the same as cpuPerCore.
    property var _prevIdlePerCore: []
    property var _prevTotalPerCore: []
    property string _tempPath: ""
    property string _npuPath: ""
    // cumulative busy-microseconds counter, sampled against wall-clock time
    // since it isn't a simple idle/total ratio like /proc/stat.
    property real _prevNpuBusyUs: -1
    property real _prevNpuTs: 0

    // GPU vendor/driver detected once at startup: "nvidia" (nvidia-smi, no
    // fdinfo support in the proprietary driver), "amdgpu" or "intel-xe" or
    // "intel-i915" (all three read the kernel's standard DRM fdinfo engine
    // counters -- one mechanism covers every non-nvidia driver), or "none".
    // _gpuPdev is the matching card's PCI address, used to filter fdinfo.
    property string _gpuBackend: ""
    property string _gpuPdev: ""
    // per-engine busy% for the popout's engine-bar row, e.g. [{name:"rcs",
    // pct:12}, ...]. empty when the backend has no per-engine breakdown.
    property var gpuEngines: []
    // previous fdinfo sample, keyed by engine name, for the delta calc.
    property var _prevEngineCyclesBusy: ({})
    property var _prevEngineCyclesTotal: ({})
    property var _prevEngineNs: ({})
    property real _prevEngineWallMs: 0

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
            statFile.reload();
            memFile.reload();
            if (root._tempPath.length > 0)
                tempFile.reload();
            if (root._npuPath.length > 0)
                npuFile.reload();
            if (root._diskDev.length > 0)
                diskStatFile.reload();
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

    // busy-fraction delta shared by the aggregate line and each per-core line.
    function _busyPct(f, prevIdle, prevTotal) {
        var idle = Number(f[4]) + Number(f[5]);
        var total = 0;
        for (var i = 1; i < f.length; i++)
            total += Number(f[i]);
        var dIdle = idle - prevIdle;
        var dTotal = total - prevTotal;
        var hadPrev = prevTotal > 0;
        return { idle: idle, total: total, pct: (hadPrev && dTotal > 0) ? Math.max(0, Math.min(100, Math.round(100 * (1 - dIdle / dTotal)))) : -1 };
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
        printErrors: false
        onLoaded: {
            var lines = statFile.text().split("\n");

            var f = lines[0].trim().split(/\s+/);
            if (f.length < 8 || f[0] !== "cpu")
                return;
            var agg = root._busyPct(f, root._prevIdle, root._prevTotal);
            root._prevIdle = agg.idle;
            root._prevTotal = agg.total;
            if (agg.pct >= 0) {
                root.cpu = agg.pct;
                root.cpuHistory = root._push(root.cpuHistory, root.cpu);
            }

            var cores = [];
            var prevIdles = root._prevIdlePerCore.slice();
            var prevTotals = root._prevTotalPerCore.slice();
            var nextIdles = [];
            var nextTotals = [];
            for (var li = 1; li < lines.length; li++) {
                var cf = lines[li].trim().split(/\s+/);
                if (cf.length < 8 || !/^cpu\d+$/.test(cf[0]))
                    break;
                var idx = cores.length;
                var core = root._busyPct(cf, prevIdles[idx] || 0, prevTotals[idx] || 0);
                nextIdles.push(core.idle);
                nextTotals.push(core.total);
                cores.push(core.pct >= 0 ? core.pct : (root.cpuPerCore[idx] !== undefined ? root.cpuPerCore[idx] : 0));
            }
            root._prevIdlePerCore = nextIdles;
            root._prevTotalPerCore = nextTotals;
            if (cores.length > 0)
                root.cpuPerCore = cores;
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
        printErrors: false
        onLoaded: {
            var t = memFile.text();
            var total = Number((t.match(/MemTotal:\s+(\d+)/) || [])[1] || 0);
            var avail = Number((t.match(/MemAvailable:\s+(\d+)/) || [])[1] || 0);
            if (total > 0) {
                root.mem = Math.max(0, Math.min(100, Math.round(100 * (total - avail) / total)));
                root.memHistory = root._push(root.memHistory, root.mem);
            }
        }
    }

    // resolve a cpu-ish thermal zone once (types vary by machine), then poll it.
    Process {
        id: tempResolve
        running: root.active && root._tempPath.length === 0
        command: ["sh", "-c",
            "for d in /sys/class/thermal/thermal_zone*; do " +
            "t=$(cat \"$d/type\" 2>/dev/null); " +
            "case \"$t\" in *pkg*|*x86*|*cpu*|*coretemp*|*k10*|*acpitz*) echo \"$d/temp\"; exit 0;; esac; done; " +
            "ls /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (this.text || "").trim();
                if (p.length > 0)
                    root._tempPath = p;
            }
        }
    }

    FileView {
        id: tempFile
        path: root._tempPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            var v = Number((tempFile.text() || "").trim());
            if (v > 0) {
                root.temp = Math.round(v / 1000);
                root.tempAvailable = true;
                root.tempHistory = root._push(root.tempHistory, root.temp);
            } else {
                root.tempAvailable = false;
            }
        }
    }

    // resolve the NPU's busy-time counter once (its PCI address isn't fixed
    // across machines), then poll it.
    Process {
        id: npuResolve
        running: root.active && root._npuPath.length === 0
        command: ["sh", "-c", "find /sys/devices -maxdepth 5 -name npu_busy_time_us 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = (this.text || "").trim();
                if (p.length > 0)
                    root._npuPath = p;
            }
        }
    }

    FileView {
        id: npuFile
        path: root._npuPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            var busy = Number((npuFile.text() || "").trim());
            var now = Date.now();
            if (root._prevNpuTs > 0) {
                var dBusyUs = busy - root._prevNpuBusyUs;
                var dtUs = (now - root._prevNpuTs) * 1000;
                if (dtUs > 0) {
                    root.npu = Math.max(0, Math.min(100, Math.round(100 * dBusyUs / dtUs)));
                    root.npuHistory = root._push(root.npuHistory, root.npu);
                }
            }
            root._prevNpuBusyUs = busy;
            root._prevNpuTs = now;
            root.npuAvailable = true;
        }
    }

    // preferred display order for known engine names (render/3D first, then
    // compute, then copy/blit, then video); anything unrecognized sorts
    // after these, alphabetically.
    readonly property var _enginePriority: ({
        rcs: 0, gfx: 0, render: 0, "3d": 0,
        ccs: 1, compute: 1, comp: 1,
        bcs: 2, dma: 2, copy: 2, blit: 2,
        vcs: 3, dec: 3, decode: 3,
        vecs: 4, enc: 4, encode: 4, jpeg: 4
    })

    function _engineRank(name) {
        var r = root._enginePriority[name.toLowerCase()];
        return r !== undefined ? r : 99;
    }

    // detect the GPU once: prefer nvidia-smi (the proprietary driver has no
    // fdinfo engine stats), else find whichever non-nvidia card is actually
    // bound to a driver and record its PCI address for the fdinfo scan
    // below -- that scan is the single mechanism covering amdgpu, xe, and
    // i915 alike, since all three publish the kernel's standard DRM fdinfo
    // engine counters.
    Process {
        id: gpuResolve
        running: root.active && root._gpuBackend.length === 0
        command: ["sh", "-c",
            "if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits >/dev/null 2>&1; then echo nvidia; exit 0; fi; " +
            "intel_drv=; intel_pdev=; amd_pdev=; " +
            "for d in /sys/class/drm/card*/device; do " +
            "drv=$(readlink -f \"$d/driver\" 2>/dev/null); " +
            "pdev=$(basename \"$(readlink -f \"$d\")\" 2>/dev/null); " +
            "case \"$drv\" in " +
            "*/amdgpu) amd_pdev=\"$pdev\";; " +
            "*/xe) intel_drv=xe; intel_pdev=\"$pdev\";; " +
            "*/i915) intel_drv=i915; intel_pdev=\"$pdev\";; " +
            "esac; " +
            "done; " +
            "if [ -n \"$amd_pdev\" ]; then echo \"amdgpu $amd_pdev\"; exit 0; fi; " +
            "if [ \"$intel_drv\" = xe ]; then echo \"intel-xe $intel_pdev\"; exit 0; fi; " +
            "if [ \"$intel_drv\" = i915 ]; then echo \"intel-i915 $intel_pdev\"; exit 0; fi; " +
            "echo none"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = (this.text || "").trim().split(/\s+/);
                root._gpuBackend = parts[0] || "none";
                if (parts[1])
                    root._gpuPdev = parts[1];
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active && root._gpuBackend.length > 0 && root._gpuBackend !== "none"
        triggeredOnStart: true
        onTriggered: {
            if (root._gpuBackend === "nvidia")
                gpuNvidiaProc.running = true;
            else if (root._gpuPdev.length > 0)
                gpuEngineProc.running = true;
        }
    }

    Process {
        id: gpuNvidiaProc
        // SM (general compute/3D), memory controller, video encoder, video
        // decoder -- nvidia-smi's own engine-ish breakdown, since the
        // proprietary driver doesn't publish DRM fdinfo engine stats.
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

    // per-engine busy%, read from the kernel's standard DRM fdinfo interface
    // (Documentation/gpu/drm-usage-stats.rst) rather than any vendor tool --
    // same mechanism for amdgpu, xe, and i915. every readable fd's fdinfo is
    // scanned (unreadable/vanished ones are skipped rather than aborting the
    // whole scan, since fds constantly open and close), entries are kept
    // only for the fd whose "drm-pdev" matches our card, and both counter
    // styles the kernel uses are handled: cycle-based (xe: drm-cycles-<eng>
    // busy over drm-total-cycles-<eng> elapsed, same denominator for every
    // client) and nanosecond-based (amdgpu, older i915: drm-engine-<eng>
    // cumulative busy ns, divided by wall-clock time between samples).
    Process {
        id: gpuEngineProc
        // one awk process reads every fdinfo file directly (no per-file fork);
        // that took ~1.6s of CPU per 3s cycle when this looped a `cat` per
        // file instead (~1300 forks). BEGINFILE/ERRNO/nextfile (gawk) skips a
        // file that vanishes mid-scan the same way the old `[ -r "$f" ]` did,
        // since fds constantly open and close.
        //
        // the `;` after PDEV=... is load-bearing: `PDEV=x awk -v want="$PDEV"`
        // (no `;`) is a single simple command, and POSIX expands every word on
        // it -- including "$PDEV" in that same -v argument -- against the
        // shell's variables *before* the prefix assignment takes effect, so
        // $PDEV expands empty there even though awk's own env does get PDEV.
        // Splitting into two statements makes the assignment land first.
        command: root._gpuPdev.length > 0 ? ["sh", "-c", `PDEV='${root._gpuPdev}'; awk -v want="$PDEV" '
BEGINFILE { if (ERRNO != "") nextfile }
FNR==1 { ok=0 }
/^drm-pdev:/ { ok = ($2==want) }
ok && $1 ~ /^drm-total-cycles-/ { key=$1; sub(/^drm-total-cycles-/,"",key); sub(/:$/,"",key); total[key]=$2 }
ok && $1 ~ /^drm-cycles-/ { key=$1; sub(/^drm-cycles-/,"",key); sub(/:$/,"",key); busy[key]+=$2 }
ok && $1 ~ /^drm-engine-/ { key=$1; sub(/^drm-engine-/,"",key); sub(/:$/,"",key); busyns[key]+=$2 }
END {
  for (k in total) print "C", k, busy[k]+0, total[k]+0
  for (k in busyns) print "N", k, busyns[k]+0
}
' /proc/[0-9]*/fdinfo/* 2>/dev/null`] : ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var now = Date.now();
                var curCyclesBusy = {}, curCyclesTotal = {}, curNs = {};
                (this.text || "").split("\n").forEach(function (ln) {
                    var p = ln.trim().split(/\s+/);
                    if (p[0] === "C" && p.length === 4) {
                        curCyclesBusy[p[1]] = Number(p[2]);
                        curCyclesTotal[p[1]] = Number(p[3]);
                    } else if (p[0] === "N" && p.length === 3) {
                        curNs[p[1]] = Number(p[2]);
                    }
                });

                var engines = [];
                var prevBusy = root._prevEngineCyclesBusy;
                var prevTotal = root._prevEngineCyclesTotal;
                for (var k in curCyclesTotal) {
                    var dTotal = curCyclesTotal[k] - (prevTotal[k] || 0);
                    var dBusy = curCyclesBusy[k] - (prevBusy[k] || 0);
                    var pct = (prevTotal[k] !== undefined && dTotal > 0) ? Math.max(0, Math.min(100, Math.round(100 * dBusy / dTotal))) : 0;
                    engines.push({ name: k, pct: pct });
                }

                var prevNs = root._prevEngineNs;
                var hadPrevWall = root._prevEngineWallMs > 0;
                var dtNs = hadPrevWall ? (now - root._prevEngineWallMs) * 1e6 : 0;
                for (var k2 in curNs) {
                    var dNs = curNs[k2] - (prevNs[k2] || 0);
                    var pct2 = (hadPrevWall && dtNs > 0) ? Math.max(0, Math.min(100, Math.round(100 * dNs / dtNs))) : 0;
                    engines.push({ name: k2, pct: pct2 });
                }

                root._prevEngineCyclesBusy = curCyclesBusy;
                root._prevEngineCyclesTotal = curCyclesTotal;
                root._prevEngineNs = curNs;
                root._prevEngineWallMs = now;

                if (engines.length > 0) {
                    engines.sort(function (a, b) {
                        var ra = root._engineRank(a.name), rb = root._engineRank(b.name);
                        return ra !== rb ? ra - rb : (a.name < b.name ? -1 : 1);
                    });
                    root.gpuEngines = engines;
                    root.gpu = Math.max.apply(null, engines.map(function (e) { return e.pct; }));
                    root.gpuHistory = root._push(root.gpuHistory, root.gpu);
                    root.gpuAvailable = true;
                } else {
                    root.gpuAvailable = false;
                }
            }
        }
    }

    // resolve the whole-disk block device backing the home partition once
    // (lsblk maps a partition like nvme0n1p2 back to its parent nvme0n1,
    // since /sys/block/<dev>/stat only exists for whole disks; a device
    // that's already a whole disk has no pkname, so fall back to its own
    // basename).
    Process {
        id: diskDevResolve
        running: root.active && root._diskDev.length === 0
        command: ["sh", "-c",
            "src=$(df --output=source \"$HOME\" 2>/dev/null | tail -1); " +
            "base=$(basename \"$src\"); " +
            "pk=$(lsblk -no pkname \"$src\" 2>/dev/null); " +
            "echo \"${pk:-$base}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = (this.text || "").trim();
                if (d.length > 0)
                    root._diskDev = d;
            }
        }
    }

    FileView {
        id: diskStatFile
        path: root._diskDev.length > 0 ? "/sys/block/" + root._diskDev + "/stat" : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            var f = diskStatFile.text().trim().split(/\s+/);
            if (f.length < 8)
                return;
            var readSectors = Number(f[2]);
            var writeSectors = Number(f[6]);
            var now = Date.now();
            if (root._prevDiskIOTs > 0) {
                var dt = (now - root._prevDiskIOTs) / 1000;
                if (dt > 0) {
                    root.diskReadRate = Math.max(0, Math.round((readSectors - root._prevDiskReadSectors) * 512 / dt));
                    root.diskWriteRate = Math.max(0, Math.round((writeSectors - root._prevDiskWriteSectors) * 512 / dt));
                    root.diskIOAvailable = true;
                }
            }
            root._prevDiskReadSectors = readSectors;
            root._prevDiskWriteSectors = writeSectors;
            root._prevDiskIOTs = now;
        }
    }

    // usage of the filesystem backing the home dir (covers the common
    // separate-/home-partition case without hardcoding a mountpoint).
    Process {
        id: diskProc
        command: ["sh", "-c", "df -h --output=pcent,used,size \"$HOME\" | tail -1"]
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
