import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { searchUrl, parseArt, cleanTitle } = require("./albumart.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

eq(searchUrl("Kanye West", "I Wonder"),
   "https://itunes.apple.com/search?term=" + encodeURIComponent("Kanye West I Wonder") + "&entity=song&limit=1",
   "artist and title joined by a space, encoded");
eq(searchUrl("  Radiohead  ", "  No Surprises  "),
   "https://itunes.apple.com/search?term=" + encodeURIComponent("Radiohead No Surprises") + "&entity=song&limit=1",
   "inputs trimmed before joining");
eq(searchUrl("", "Lone Title"),
   "https://itunes.apple.com/search?term=" + encodeURIComponent("Lone Title") + "&entity=song&limit=1",
   "empty artist still queries by title");
eq(searchUrl("Solo Artist", ""),
   "https://itunes.apple.com/search?term=" + encodeURIComponent("Solo Artist") + "&entity=song&limit=1",
   "empty title still queries by artist");
eq(searchUrl("", ""), "", "both empty yields empty URL");
eq(searchUrl(null, undefined), "", "null/undefined treated as empty");

// noise-stripping: video/browser titles carry cruft that wrecks the iTunes match
eq(cleanTitle("One More Time (Official Video)"), "One More Time", "parenthetical tag stripped");
eq(cleanTitle("Creep [HD]"), "Creep", "bracket tag stripped");
eq(cleanTitle("Blinding Lights (Official Music Video) [4K]"), "Blinding Lights", "multiple tags stripped");
eq(cleanTitle("Get Lucky feat. Pharrell Williams"), "Get Lucky", "feat. credit stripped");
eq(cleanTitle("Daft Punk - Around the World"), "Daft Punk", "dash-separated tail stripped");
eq(cleanTitle("Plain Title"), "Plain Title", "clean title untouched");
eq(searchUrl("The Weeknd", "Blinding Lights (Official Video)"),
   "https://itunes.apple.com/search?term=" + encodeURIComponent("The Weeknd Blinding Lights") + "&entity=song&limit=1",
   "searchUrl strips title noise before querying");
eq(searchUrl("", "(Lyrics)"),
   "https://itunes.apple.com/search?term=" + encodeURIComponent("(Lyrics)") + "&entity=song&limit=1",
   "a title that is all noise falls back to the raw title, not empty");

const goodBody = JSON.stringify({
    resultCount: 1,
    results: [{
        artistName: "Kanye West",
        trackName: "I Wonder",
        artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/Music128/v4/aa/bb/cc/deadbeef/00602517483507.rgb.jpg/100x100bb.jpg"
    }]
});
eq(parseArt(goodBody),
   "https://is1-ssl.mzstatic.com/image/thumb/Music128/v4/aa/bb/cc/deadbeef/00602517483507.rgb.jpg/600x600bb.jpg",
   "valid body swaps 100x100 to 600x600");

eq(parseArt(JSON.stringify({ resultCount: 0, results: [] })), "", "empty results yields empty string");
eq(parseArt(JSON.stringify({ resultCount: 1, results: [{ trackName: "X" }] })), "", "missing artworkUrl100 yields empty string");
eq(parseArt("not json at all"), "", "garbage text yields empty string");
eq(parseArt(""), "", "empty text yields empty string");
eq(parseArt(null), "", "null yields empty string");
eq(parseArt(JSON.stringify({})), "", "no results key yields empty string");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
