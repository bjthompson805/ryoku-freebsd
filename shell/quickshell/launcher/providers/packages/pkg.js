// Parse the package provider's search output into launcher rows. The search
// runs `pkg rquery` (the repositories) then `pkg query` (what is installed)
// with the same format, each line tagged R or I:
//   <R|I> \t name \t version \t repository \t comment
// A name in both is one installed row. Rows rank exact name, then prefix,
// then substring, alphabetical within each. Pure logic so the provider's
// parsing is node-tested without pkg.

var LIMIT = 30;

// pkg -x matches a POSIX extended regex; a typed term is a literal.
function escapeRegex(term) {
    return String(term).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function rank(name, term) {
    var n = name.toLowerCase();
    var t = term.toLowerCase();
    if (n === t)
        return 0;
    if (n.indexOf(t) === 0)
        return 1;
    return 2;
}

function parse(raw, term) {
    var byName = {};
    var lines = String(raw || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t");
        if (f.length < 5 || (f[0] !== "R" && f[0] !== "I") || !f[1])
            continue;
        var row = byName[f[1]];
        if (!row) {
            row = byName[f[1]] = {
                name: f[1],
                version: f[2],
                source: f[3],
                description: f.slice(4).join("\t"),
                installed: false
            };
        }
        if (f[0] === "I") {
            row.installed = true;
            // the installed version is the one on disk.
            row.version = f[2];
        }
    }
    var out = Object.keys(byName).map(function (k) { return byName[k]; });
    out.sort(function (a, b) {
        return (rank(a.name, term) - rank(b.name, term)) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    });
    return out.slice(0, LIMIT);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { parse, escapeRegex, rank, LIMIT };
}
