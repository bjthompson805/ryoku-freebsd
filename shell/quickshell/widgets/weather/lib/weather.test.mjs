import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { categoryFor, labelFor, unitParam, tempSymbol, formatTemp, parseForecast, parseLoc, parseJson } = require("./weather.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}
function ok(cond, msg) { eq(!!cond, true, msg); }

// WMO code -> animation category (only the six the Sky knows how to draw)
eq(categoryFor(0), "clear", "code 0 clear -> clear");
eq(categoryFor(1), "clear", "code 1 mainly clear -> clear");
eq(categoryFor(2), "clouds", "code 2 partly cloudy -> clouds");
eq(categoryFor(3), "clouds", "code 3 overcast -> clouds");
eq(categoryFor(45), "fog", "code 45 -> fog");
eq(categoryFor(48), "fog", "code 48 -> fog");
eq(categoryFor(51), "rain", "code 51 drizzle -> rain");
eq(categoryFor(61), "rain", "code 61 -> rain");
eq(categoryFor(80), "rain", "code 80 showers -> rain");
eq(categoryFor(71), "snow", "code 71 -> snow");
eq(categoryFor(86), "snow", "code 86 -> snow");
eq(categoryFor(95), "storm", "code 95 -> storm");
eq(categoryFor(99), "storm", "code 99 -> storm");
const cats = new Set(["clear", "clouds", "rain", "snow", "storm", "fog"]);
ok([0, 1, 2, 3, 45, 48, 51, 61, 71, 80, 85, 95, 99, 1234].every(c => cats.has(categoryFor(c))), "every category is a Sky-drawable name");

eq(labelFor(0), "Clear", "label clear");
eq(labelFor(3), "Cloudy", "label cloudy");
eq(labelFor(61), "Rain", "label rain");
eq(labelFor(95), "Thunder", "label thunder");

eq(unitParam("C"), "celsius", "C -> celsius request");
eq(unitParam("F"), "fahrenheit", "F -> fahrenheit request");
eq(tempSymbol("C"), "\u00b0", "celsius shows bare degree");
eq(tempSymbol("F"), "\u00b0", "fahrenheit shows bare degree");
eq(formatTemp(19.7, "C"), "20\u00b0", "formatTemp rounds half-up");
eq(formatTemp(67.4, "F"), "67\u00b0", "formatTemp rounds down");

const sample = {
    current: { time: "2026-06-22T10:30", temperature_2m: 19.7, weather_code: 61, is_day: 1, relative_humidity_2m: 63, wind_speed_10m: 12.4 },
    daily: { time: ["2026-06-22", "2026-06-23", "2026-06-24"], weather_code: [63, 0, 71], temperature_2m_max: [20.9, 25.1, 1.4], temperature_2m_min: [9.5, 15.5, -3.2] }
};
const f = parseForecast(sample, "C");
ok(f.available, "parseForecast available on a good body");
eq(f.tempNow, 20, "tempNow rounded");
eq(f.temp, "20\u00b0", "temp formatted bare degree");
eq(f.code, 61, "current code kept");
eq(f.condition, "Rain", "condition from code 61");
eq(f.category, "rain", "category from code 61");
eq(f.humidity, 63, "humidity parsed");
eq(f.wind, 12, "wind rounded");
eq(f.isDay, true, "isDay from is_day 1");
eq(f.daily.length, 3, "daily length");
eq(f.daily[0].code, 63, "daily[0] code");
eq(f.daily[0].category, "rain", "daily[0] category");
eq(f.daily[1].category, "clear", "daily[1] clear");
eq(f.daily[2].category, "snow", "daily[2] snow");
eq(f.daily[0].hi, 21, "daily[0] hi rounded");
eq(f.daily[2].lo, -3, "daily[2] negative lo rounded");
ok(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].includes(f.daily[0].day), "daily[0] day is a weekday name");

eq(parseForecast({}, "C").available, false, "no current -> unavailable");
eq(parseForecast({ current: {} }, "C").available, false, "current without temp -> unavailable");
eq(parseForecast(null, "C").available, false, "null json -> unavailable");

eq(parseLoc({ status: "success", city: "Pittsfield", lat: 42.45, lon: -73.25 }), { city: "Pittsfield", lat: 42.45, lon: -73.25 }, "parseLoc reads a success body");
eq(parseLoc({ lat: 1, lon: 2 }), { city: "", lat: 1, lon: 2 }, "parseLoc tolerates a missing status/city");
eq(parseLoc({ status: "fail" }), null, "parseLoc null on failure");
eq(parseLoc(null), null, "parseLoc null on null");

eq(parseJson('{"a":1}'), { a: 1 }, "parseJson reads valid json");
eq(parseJson(""), null, "parseJson null on empty");
eq(parseJson("nope"), null, "parseJson null on garbage");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
