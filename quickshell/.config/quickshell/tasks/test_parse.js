// Tests for Parse.js. Run with:  node tasks/test_parse.js
//
// Parse.js is written for QML, so it starts with `.pragma library` and
// has no exports. Loading it here strips that line and evaluates the
// rest, which keeps the shipped file free of test scaffolding.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const src = fs.readFileSync(path.join(__dirname, "Parse.js"), "utf8")
    .replace(/^\.pragma library\s*/, "");
const P = {};
vm.createContext(P);
vm.runInContext(src, P);

let pass = 0, fail = 0;
function ok(name, cond, extra) {
    if (cond) { pass++; return; }
    fail++;
    console.log("FAIL  " + name);
    if (extra !== undefined) console.log(String(extra).split("\n").map(l => "        " + l).join("\n"));
}
function eq(name, got, want) {
    ok(name, got === want, got === want ? "" : "got:  " + JSON.stringify(got) + "\nwant: " + JSON.stringify(want));
}

const cfg = {
    categories: [
        { name: "job", color: "#e06c75" },
        { name: "bash", color: "#98c379" },
        { name: "coding", color: "#61afef" }
    ],
    importance: [
        { level: 1, label: "urgent", color: "#ff5555" },
        { level: 2, label: "high", color: "#ffb86c" },
        { level: 3, label: "normal", color: "#8be9fd" }
    ]
};

const SAMPLE = `# Tasks

Some free-form note that must survive.

- [ ] end project for bash @bash !2
- [ ] end project for job @job !1
- [ ] buy cable
- [ ] write docs @coding
  - [ ] outline
  note under the task

## Done

### 2026-10-08
- [x] programming @coding !3 ✅ 2026-10-08

### 2026-10-07
- [x] fix router #home ✅ 2026-10-07
- [-] old idea @job
`;

// --- parsing ---------------------------------------------------------

const tasks = P.readTasks(SAMPLE, cfg);
eq("task count", tasks.length, 7);
eq("open count", tasks.filter(t => t.open).length, 4);
eq("done count", tasks.filter(t => t.done).length, 2);
eq("cancelled count", tasks.filter(t => t.cancelled).length, 1);

const bash = tasks[0];
eq("text strips tokens", bash.text, "end project for bash");
eq("category", bash.category, "bash");
eq("importance", bash.importance, 2);
eq("no done date", bash.doneDate, null);

eq("no importance sorts as null", tasks[2].importance, null);
eq("subtask attaches to parent", tasks[3].hasChildren, true);
eq("indented checkbox is not a task", tasks[4].text, "programming");

const router = tasks.find(t => t.text.indexOf("fix router") === 0);
eq("unknown tag stays in text", router.text, "fix router #home");
eq("unknown tag is not a category", router.category, null);
eq("done date read", router.doneDate, "2026-10-07");

// --- round trip ------------------------------------------------------

// The headline guarantee: no change means no diff, byte for byte.
const roundTripCases = {
    sample: SAMPLE,
    "no trailing newline": SAMPLE.trimEnd(),
    "crlf": SAMPLE.replace(/\n/g, "\r\n"),
    empty: "",
    "only a note": "just prose, no tasks at all\n",
    "tabs for indent": "- [ ] parent\n\t- [ ] child\n",
    "front matter": "---\ntags: x\n---\n\n- [ ] a @job\n"
};
for (const [name, text] of Object.entries(roundTripCases)) {
    // A no-op edit: set a task's fields to exactly what they already are.
    const list = P.readTasks(text, cfg);
    let out = text;
    for (const t of list) {
        const r = P.editTask(out, t.raw, {
            text: t.text, category: t.category, importance: t.importance
        }, cfg);
        if (r.ok) out = r.text;
    }
    eq("round trip: " + name, out, text);
}

// A file whose tokens are in a different order, or spaced oddly, must
// survive being read and must survive an edit to a DIFFERENT task.
// This is the real guarantee: only the line being changed is rewritten.
const ODD = `# Tasks

- [x] odd order ✅ 2026-10-01 @job !2
- [ ]   wide   spacing   @bash
- [ ] plain
`;
let r = P.editTask(ODD, "- [ ] plain", { text: "plain edited" }, cfg);
ok("edit leaves odd-order line byte-identical",
   r.text.indexOf("- [x] odd order ✅ 2026-10-01 @job !2") !== -1, r.text);
ok("edit leaves odd spacing byte-identical",
   r.text.indexOf("- [ ]   wide   spacing   @bash") !== -1, r.text);
ok("edit applied to the target", r.text.indexOf("- [ ] plain edited") !== -1, r.text);

// Reading odd order still finds the tokens.
const oddTasks = P.readTasks(ODD, cfg);
eq("odd order: date found", oddTasks[0].doneDate, "2026-10-01");
eq("odd order: category found", oddTasks[0].category, "job");
eq("odd order: importance found", oddTasks[0].importance, 2);
eq("odd order: text clean", oddTasks[0].text, "odd order");
eq("wide spacing collapses in text only", oddTasks[1].text, "wide spacing");

// Deleting one task must not reformat its neighbours either.
r = P.deleteTask(ODD, "- [ ] plain", cfg);
ok("delete leaves neighbours byte-identical",
   r.text.indexOf("- [x] odd order ✅ 2026-10-01 @job !2") !== -1
   && r.text.indexOf("- [ ]   wide   spacing   @bash") !== -1, r.text);

// Ticking rewrites only the ticked line.
r = P.tick(ODD, "- [ ] plain", cfg, "2026-10-09");
ok("tick leaves neighbours byte-identical",
   r.text.indexOf("- [ ]   wide   spacing   @bash") !== -1, r.text);

// --- tick ------------------------------------------------------------

r = P.tick(SAMPLE, "- [ ] buy cable", cfg, "2026-10-08");
ok("tick succeeds", r.ok, r.reason);
ok("tick marks done", r.text.indexOf("- [x] buy cable ✅ 2026-10-08") !== -1, r.text);
ok("tick removes from open section",
   r.text.split("## Done")[0].indexOf("buy cable") === -1, r.text);
ok("tick files under today's heading",
   r.text.split("### 2026-10-08")[1].split("###")[0].indexOf("buy cable") !== -1, r.text);
eq("tick keeps other content",
   r.text.indexOf("Some free-form note that must survive.") !== -1, true);

// A date with no heading yet creates one, newest first.
r = P.tick(SAMPLE, "- [ ] buy cable", cfg, "2026-10-09");
const order = r.text.match(/### \d{4}-\d{2}-\d{2}/g);
eq("new heading created", order[0], "### 2026-10-09");
eq("headings stay newest first", order.join(","), "### 2026-10-09,### 2026-10-08,### 2026-10-07");

// An older date slots in between rather than on top.
r = P.tick(SAMPLE, "- [ ] buy cable", cfg, "2026-10-07");
ok("existing older heading reused",
   r.text.split("### 2026-10-07")[1].indexOf("buy cable") !== -1, r.text);

r = P.tick(SAMPLE, "- [ ] buy cable", cfg, "2026-01-01");
const order2 = r.text.match(/### \d{4}-\d{2}-\d{2}/g);
eq("older date goes last", order2[order2.length - 1], "### 2026-01-01");

// Subtasks travel with the parent.
r = P.tick(SAMPLE, "- [ ] write docs @coding", cfg, "2026-10-08");
const doneBlock = r.text.split("### 2026-10-08")[1].split("### ")[0];
ok("subtask moved with parent", doneBlock.indexOf("- [ ] outline") !== -1, doneBlock);
ok("note moved with parent", doneBlock.indexOf("note under the task") !== -1, doneBlock);
ok("subtask gone from open section",
   r.text.split("## Done")[0].indexOf("outline") === -1, r.text);

// Acting on a line that is no longer there must fail, not guess.
r = P.tick(SAMPLE, "- [ ] a task that was edited on the phone", cfg, "2026-10-08");
eq("stale line rejected", r.ok, false);
eq("stale line leaves text untouched", r.text, SAMPLE);

// --- untick ----------------------------------------------------------

r = P.untick(SAMPLE, "- [x] programming @coding !3 ✅ 2026-10-08", cfg);
ok("untick succeeds", r.ok, r.reason);
ok("untick clears the date", r.text.indexOf("✅ 2026-10-08") === -1, r.text);
ok("untick returns to open section",
   r.text.split("## Done")[0].indexOf("- [ ] programming @coding !3") !== -1, r.text);
ok("emptied heading removed", r.text.indexOf("### 2026-10-08") === -1, r.text);
ok("other heading kept", r.text.indexOf("### 2026-10-07") !== -1, r.text);

// --- add / edit / delete / cancel ------------------------------------

r = P.addTask(SAMPLE, { text: "new thing", category: "job", importance: 2 }, cfg);
ok("add writes canonical token order",
   r.text.indexOf("- [ ] new thing @job !2") !== -1, r.text);
ok("add lands in the open section",
   r.text.split("## Done")[0].indexOf("new thing") !== -1, r.text);

r = P.addTask(SAMPLE, { text: "bare", category: null, importance: null }, cfg);
ok("add with no tokens", r.text.indexOf("- [ ] bare") !== -1, r.text);

r = P.editTask(SAMPLE, "- [ ] buy cable", { category: "job", importance: 1 }, cfg);
ok("edit adds tokens", r.text.indexOf("- [ ] buy cable @job !1") !== -1, r.text);

r = P.editTask(SAMPLE, "- [ ] end project for bash @bash !2",
               { text: "renamed", category: null, importance: null }, cfg);
ok("edit can clear tokens", r.text.indexOf("- [ ] renamed") !== -1, r.text);
ok("cleared category is gone", r.text.indexOf("renamed @bash") === -1, r.text);

r = P.deleteTask(SAMPLE, "- [ ] write docs @coding", cfg);
ok("delete removes the task", r.text.indexOf("write docs") === -1, r.text);
ok("delete removes its subtask too", r.text.indexOf("- [ ] outline") === -1, r.text);
ok("delete keeps the rest", r.text.indexOf("buy cable") !== -1, r.text);

r = P.setCancelled(SAMPLE, "- [ ] buy cable", true, cfg);
ok("cancel marks [-]", r.text.indexOf("- [-] buy cable") !== -1, r.text);

// --- stamping phone ticks --------------------------------------------

// What Obsidian's own checkbox produces with no plugin: [x], no date,
// still sitting in the open section.
const PHONE = `# Tasks

- [ ] still open @job
- [x] ticked on the phone @bash !2
- [x] also ticked

## Done

### 2026-10-07
- [x] older @job ✅ 2026-10-07
`;

eq("needsStamping detects undated ticks", P.needsStamping(PHONE, cfg), true);
eq("needsStamping is false when clean", P.needsStamping(SAMPLE, cfg), false);

r = P.stampUndated(PHONE, cfg, "2026-10-09");
eq("stamping reports a change", r.changed, true);
ok("phone tick dated",
   r.text.indexOf("- [x] ticked on the phone @bash !2 ✅ 2026-10-09") !== -1, r.text);
ok("second phone tick dated", r.text.indexOf("- [x] also ticked ✅ 2026-10-09") !== -1, r.text);
ok("open task untouched", r.text.split("## Done")[0].indexOf("- [ ] still open @job") !== -1, r.text);
ok("phone ticks moved out of open section",
   r.text.split("## Done")[0].indexOf("[x]") === -1, r.text);
ok("already-dated task keeps its date", r.text.indexOf("older @job ✅ 2026-10-07") !== -1, r.text);
eq("stamping twice changes nothing more", P.stampUndated(r.text, cfg, "2026-10-09").changed, false);
eq("stamped file is stable", P.stampUndated(r.text, cfg, "2026-10-09").text, r.text);

// A [x] that already has a date but sits in the open section keeps its
// own date rather than being re-dated to today.
const MISPLACED = "- [ ] a\n- [x] b ✅ 2026-09-01\n\n## Done\n\n### 2026-10-01\n- [x] c ✅ 2026-10-01\n";
r = P.stampUndated(MISPLACED, cfg, "2026-10-09");
ok("misplaced done keeps its own date", r.text.indexOf("- [x] b ✅ 2026-09-01") !== -1, r.text);
ok("misplaced done filed under its own heading",
   r.text.split("### 2026-09-01")[1].indexOf("- [x] b") !== -1, r.text);

// No "## Done" section at all: one gets created.
r = P.stampUndated("- [ ] a\n- [x] b\n", cfg, "2026-10-09");
ok("Done section created", r.text.indexOf("## Done") !== -1, r.text);
ok("heading created under it", r.text.indexOf("### 2026-10-09") !== -1, r.text);
ok("open task still open", r.text.split("## Done")[0].indexOf("- [ ] a") !== -1, r.text);

// --- rename category --------------------------------------------------

r = P.renameCategory(SAMPLE, "job", "work", cfg);
eq("rename reports count", r.count, 2);
ok("rename rewrites the marker", r.text.indexOf("@work") !== -1, r.text);
ok("old marker gone", r.text.indexOf("@job") === -1, r.text);
ok("unrelated #tag untouched", r.text.indexOf("#home") !== -1, r.text);
ok("rename keeps importance", r.text.indexOf("- [ ] end project for job @work !1") !== -1, r.text);

// A tag that merely shares a prefix must not be caught.
const PREFIX = "- [ ] a @job\n- [ ] b @jobsearch\n";
r = P.renameCategory(PREFIX, "job", "work", { categories: [{ name: "job" }, { name: "jobsearch" }] });
ok("prefix marker untouched", r.text.indexOf("@jobsearch") !== -1, r.text);
ok("exact marker renamed", r.text.indexOf("- [ ] a @work") !== -1, r.text);

// --- @ marker and the #tag migration ------------------------------------

// A #tag the user wrote themselves is now ordinary text and must never
// be touched -- that is the entire point of moving off #.
const MIXED = `# Tasks

A note mentioning #job in prose.

- [ ] a #job !1
- [ ] b #home
- [ ] c @bash
- [ ] d #job @bash

## Done

### 2026-10-08
- [x] e #bash \u2705 2026-10-08
`;

eq("migration detected", P.needsTagMigration(MIXED, cfg), true);
const mig = P.migrateTags(MIXED, cfg);
eq("converted count", mig.count, 2);   // #home is not a category; the @bash line already has one
ok("legacy tag converted", mig.text.indexOf("- [ ] a @job !1") !== -1, mig.text);
ok("done task converted", mig.text.indexOf("- [x] e @bash \u2705 2026-10-08") !== -1, mig.text);
ok("prose #tag untouched",
   mig.text.indexOf("A note mentioning #job in prose.") !== -1, mig.text);
ok("non-category #tag untouched", mig.text.indexOf("- [ ] b #home") !== -1, mig.text);
ok("already-@ line untouched", mig.text.indexOf("- [ ] c @bash") !== -1, mig.text);
ok("line that already has a category keeps it",
   mig.text.indexOf("- [ ] d #job @bash") !== -1, mig.text);
eq("migration is idempotent", P.migrateTags(mig.text, cfg).count, 0);
eq("nothing to migrate in a clean file", P.needsTagMigration(SAMPLE, cfg), false);

// A category whose name is a prefix of another must not be grabbed.
const PRE = "- [ ] x #job\n- [ ] y #jobsearch\n";
const preCfg = { categories: [{ name: "job" }, { name: "jobsearch" }], importance: [] };
const preMig = P.migrateTags(PRE, preCfg);
ok("exact legacy match only", preMig.text.indexOf("- [ ] y @jobsearch") !== -1, preMig.text);
ok("shorter name did not grab it", preMig.text.indexOf("@jobsearch") !== -1, preMig.text);

// @ is what gets written now.
const added = P.addTask("# Tasks\n", { text: "n", category: "job", importance: 1 }, cfg);
ok("new tasks are written with @", added.text.indexOf("- [ ] n @job !1") !== -1, added.text);
eq("no # written", added.text.indexOf("#job"), -1);

// An @word that is not a configured category stays in the text.
const atTasks = P.readTasks("- [ ] ping @someone about @job\n", cfg);
eq("unknown @word stays in text", atTasks[0].text, "ping @someone about");
eq("known @word becomes the category", atTasks[0].category, "job");

// --- config -----------------------------------------------------------

const CONFIG = `# Config

Edit this on the phone; it is plain markdown.

## Categories
- job \`#e06c75\`
- bash \`#98c379\`

## Importance
- 1 urgent \`#ff5555\`
- 2 high \`#ffb86c\`
`;

const c = P.readConfig(CONFIG);
eq("config categories", c.categories.length, 2);
eq("config category name", c.categories[0].name, "job");
eq("config category color", c.categories[0].color, "#e06c75");
eq("config importance levels", c.importance.length, 2);
eq("config importance label", c.importance[0].label, "urgent");
eq("config importance level", c.importance[1].level, 2);

eq("config round trip", P.writeConfig(CONFIG, c), CONFIG);

const c2 = P.readConfig(CONFIG);
c2.categories.push({ name: "coding", color: "#61afef" });
const written = P.writeConfig(CONFIG, c2);
ok("config write adds entry", written.indexOf("- coding `#61afef`") !== -1, written);
ok("config write keeps prose",
   written.indexOf("Edit this on the phone; it is plain markdown.") !== -1, written);
eq("config write reparses", P.readConfig(written).categories.length, 3);

// Reordering is just the array order.
const c3 = P.readConfig(CONFIG);
c3.categories.reverse();
eq("config reorder", P.readConfig(P.writeConfig(CONFIG, c3)).categories[0].name, "bash");

// Building config.md from nothing.
const fresh = P.writeConfig("", { categories: [{ name: "x", color: "#fff" }], importance: [] });
eq("config from empty", P.readConfig(fresh).categories[0].name, "x");

// --- stats ------------------------------------------------------------

const STATS_SRC = `# Tasks

- [ ] open one @job

## Done

### 2026-10-08
- [x] a @job !1 ✅ 2026-10-08
- [x] b @bash !2 ✅ 2026-10-08
- [-] cancelled @job ✅ 2026-10-08

### 2026-10-07
- [x] c @job ✅ 2026-10-07

### 2026-10-05
- [x] d @coding !1 ✅ 2026-10-05
`;

const st = P.buildStats(STATS_SRC, cfg);
eq("stats total", st.total, 4);
eq("cancelled not counted", st.byDate["2026-10-08"].total, 2);
eq("stats first date", st.first, "2026-10-05");
eq("stats last date", st.last, "2026-10-08");
eq("count on day", P.countOn(st, "2026-10-08", null, null), 2);
eq("count by category", P.countOn(st, "2026-10-08", "job", null), 1);
eq("count by importance", P.countOn(st, "2026-10-08", null, 1), 1);
eq("count on empty day", P.countOn(st, "2026-10-06", null, null), 0);
eq("uncategorized bucket", P.countOn(st, "2026-10-07", "job", null), 1);

eq("current streak", P.currentStreak(st, null, null, "2026-10-08"), 2);
eq("streak survives a quiet today", P.currentStreak(st, null, null, "2026-10-09"), 2);
eq("streak breaks after two quiet days", P.currentStreak(st, null, null, "2026-10-10"), 0);
eq("longest streak", P.longestStreak(st, null, null), 2);
eq("best day date", P.bestDay(st, null, null).date, "2026-10-08");
eq("best day count", P.bestDay(st, null, null).count, 2);

// A done task with no date at all still parses; it just cannot be
// counted until the dashboard stamps it.
const UNDATED = "## Done\n\n### 2026-10-08\n- [x] no date @job\n";
eq("undated under heading falls back to heading",
   P.buildStats(UNDATED, cfg).byDate["2026-10-08"].total, 1);

// --- analyze: one parse, same answers as three ------------------------

for (const [name, text] of Object.entries({ sample: SAMPLE, phone: PHONE, stats: STATS_SRC })) {
    const a = P.analyze(text, cfg);
    const viaTasks = P.readTasks(text, cfg);
    const viaStats = P.buildStats(text, cfg);
    eq("analyze matches readTasks: " + name, JSON.stringify(a.tasks), JSON.stringify(viaTasks));
    eq("analyze matches buildStats: " + name, JSON.stringify(a.stats), JSON.stringify(viaStats));
    eq("analyze matches needsStamping: " + name, a.needsStamp, P.needsStamping(text, cfg));
}

// --- range aggregation -------------------------------------------------

const ag = P.aggregateRange(st, "2026-10-05", "2026-10-08", null, null);
eq("range day count", ag.days.length, 4);
eq("range total", ag.total, 4);
eq("range max", ag.max, 2);
eq("range best", ag.best.date, "2026-10-08");
eq("range longest streak", ag.longest, 2);
eq("gap day is zero", ag.days[1].count, 0);
eq("range respects category", P.aggregateRange(st, "2026-10-05", "2026-10-08", "job", null).total, 2);
eq("range respects importance", P.aggregateRange(st, "2026-10-05", "2026-10-08", null, 1).total, 2);

// A range entirely outside the data is empty, not an error.
eq("empty range total", P.aggregateRange(st, "2025-01-01", "2025-01-03", null, null).total, 0);
eq("single day range", P.aggregateRange(st, "2026-10-08", "2026-10-08", null, null).days.length, 1);

// Longest streak is measured inside the range only.
const ag2 = P.aggregateRange(st, "2026-10-07", "2026-10-08", null, null);
eq("longest clipped to range", ag2.longest, 2);

// --- bar bucketing ------------------------------------------------------

const yearDays = P.aggregateRange(st, "2026-01-01", "2026-12-31", null, null).days;
eq("a year is 365 days", yearDays.length, 365);

const perDay = P.bucketBars(yearDays, "day");
eq("day buckets", perDay.length, 365);

const perWeek = P.bucketBars(yearDays, "week");
ok("week buckets ~53", perWeek.length >= 52 && perWeek.length <= 54, perWeek.length);
eq("week buckets keep the total",
   perWeek.reduce((a, b) => a + b.count, 0), 4);

const perMonth = P.bucketBars(yearDays, "month");
eq("month buckets", perMonth.length, 12);
eq("month buckets keep the total", perMonth.reduce((a, b) => a + b.count, 0), 4);
eq("october bucket", perMonth[9].count, 4);
eq("month label", perMonth[9].label, "10/26");

// Weeks start Monday: 2026-10-05 is a Monday, 2026-10-07 and -08 fall in
// the same week, so all four completions land in one bucket.
const octWeeks = P.bucketBars(
    P.aggregateRange(st, "2026-10-05", "2026-10-11", null, null).days, "week");
eq("one week bucket", octWeeks.length, 1);
eq("week bucket total", octWeeks[0].count, 4);

const mondayStart = P.startOfWeek(new Date(2026, 9, 11)); // a Sunday
eq("sunday belongs to the week that started Monday",
   mondayStart.getFullYear() + "-" + (mondayStart.getMonth() + 1) + "-" + mondayStart.getDate(),
   "2026-10-5");

// --- report -----------------------------------------------------------

console.log("\n" + pass + " passed, " + fail + " failed");
process.exit(fail === 0 ? 0 : 1);
