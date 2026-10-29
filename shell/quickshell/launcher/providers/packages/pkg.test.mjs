import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { parse, escapeRegex, LIMIT } = require("./pkg.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

const out = [
    "R\tkitty-themes\t1.0\tFreeBSD-ports\tThemes for kitty",
    "R\tkitty\t0.47.4\tFreeBSD-ports\tCross-platform GPU-based terminal",
    "R\tpykitty\t2.1\tFreeBSD-ports\tA\ttab in the comment",
    "I\tkitty\t0.47.1\tFreeBSD-ports\tCross-platform GPU-based terminal",
    "I\tlocal-kitty\t1.0\tunknown-repository\tInstalled from a file",
    "",
    "pkg: some warning"
].join("\n");

const rows = parse(out, "kitty");
eq(rows.map(r => r.name), ["kitty", "kitty-themes", "local-kitty", "pykitty"], "exact, then prefix, then substring");
eq(rows[0], { name: "kitty", version: "0.47.1", source: "FreeBSD-ports", description: "Cross-platform GPU-based terminal", installed: true }, "installed row merges and takes the local version");
eq(rows[1].installed, false, "repository-only row is not installed");
eq(rows[2].source, "unknown-repository", "installed-only row kept");
eq(rows[3].description, "A\ttab in the comment", "tabs in the comment survive");

eq(parse("", "x"), [], "empty output yields no rows");
eq(parse("R\t\t1\trepo\tno name", "x"), [], "row without a name is dropped");

const many = Array.from({ length: 50 }, (_, i) => `R\tp${i}\t1\trepo\tc`).join("\n");
eq(parse(many, "p").length, LIMIT, "capped at the limit");

eq(escapeRegex("c++ (x)"), "c\\+\\+ \\(x\\)", "regex specials escaped");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
