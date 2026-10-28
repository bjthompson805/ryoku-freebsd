import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Every process spawn in this tree should go through the vendored
// Singletons/Spawn.qml (captures stdout/stderr to a log, notifies on failure)
// instead of a raw Quickshell.execDetached() call, which is silent and
// unloggable. Walks every .qml file under this root (following symlinks —
// Spawn.qml/SpawnCore.qml are symlinks into ryoku/shared/quickshell/) and
// fails if the raw call shows up anywhere outside the wrapper's own
// implementation.
const root = path.resolve(fileURLToPath(new URL(".", import.meta.url)), "..");

function findRepoRoot(dir) {
    let d = dir;
    while (true) {
        if (fs.existsSync(path.join(d, ".git")))
            return d;
        const parent = path.dirname(d);
        if (parent === d)
            throw new Error("could not locate repo root (.git) above " + dir);
        d = parent;
    }
}
const repoRoot = findRepoRoot(root);

// Matched by resolved (symlink-followed) real path — every vendored
// Spawn.qml/SpawnCore.qml in this root is a symlink to one of these two
// canonical files.
const allowlist = new Set([
    "ryoku/shared/quickshell/SpawnCore.qml",
    "ryoku/shared/quickshell/SpawnSingleton.qml",
]);
const pattern = /Quickshell\.execDetached\s*\(/;

function walk(dir, out) {
    for (const name of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, name.name);
        const stat = fs.statSync(p);   // follows symlinks, unlike Dirent.isFile()/isDirectory()
        if (stat.isDirectory())
            walk(p, out);
        else if (stat.isFile() && name.name.endsWith(".qml"))
            out.push(p);
    }
    return out;
}

let failed = 0;
function ok(cond, msg) {
    if (cond) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}

const files = walk(root, []);
ok(files.length > 0, "found .qml files to scan");

const offenders = [];
for (const file of files) {
    const real = fs.realpathSync(file);
    const relReal = path.relative(repoRoot, real).split(path.sep).join("/");
    if (allowlist.has(relReal))
        continue;
    const rel = path.relative(repoRoot, file).split(path.sep).join("/");
    const text = fs.readFileSync(file, "utf8");
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        if (pattern.test(lines[i]))
            offenders.push(rel + ":" + (i + 1));
    }
}

ok(offenders.length === 0, offenders.length === 0
    ? "no raw Quickshell.execDetached() calls outside Spawn.qml"
    : "raw Quickshell.execDetached() found outside Spawn.qml:\n  " + offenders.join("\n  "));

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
