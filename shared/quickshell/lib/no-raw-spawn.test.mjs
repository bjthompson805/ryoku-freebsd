import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// The canonical Spawn implementation lives here (SpawnCore.qml/
// SpawnSingleton.qml), symlinked into every vendored root's Singletons/
// directory. Unlike the per-root lint tests, nothing here is allowed to use a
// raw Quickshell.execDetached() call — this *is* the wrapper, so there's
// nothing to exempt.
const root = path.resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
const pattern = /Quickshell\.execDetached\s*\(/;

function walk(dir, out) {
    for (const name of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, name.name);
        const stat = fs.statSync(p);
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
ok(files.length > 0, "found .qml files to scan under ryoku/shared/quickshell/");

const offenders = [];
for (const file of files) {
    const rel = path.relative(root, file);
    const text = fs.readFileSync(file, "utf8");
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        if (pattern.test(lines[i]))
            offenders.push(rel + ":" + (i + 1));
    }
}

ok(offenders.length === 0, offenders.length === 0
    ? "no raw Quickshell.execDetached() calls anywhere in the shared implementation"
    : "raw Quickshell.execDetached() found in the shared implementation itself:\n  " + offenders.join("\n  "));

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
