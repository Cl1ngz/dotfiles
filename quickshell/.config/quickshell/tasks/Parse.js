.pragma library

// Parser / serializer for the Obsidian task vault.
//
// Line format:
//   - [ ] buy cable @home !2
//   - [x] fix router @home !1 \u2705 2026-10-08
//
// @name  category, matched against config.md
// !N     importance, matched against config.md
// \u2705     completion date (the Tasks plugin's marker, written by us)
//
// A category is "@name" rather than "#name" on purpose: see CAT_RE.
//
// Pure JavaScript, no QML imports, so it runs under node for tests and
// under Quickshell unchanged.
//
// THE CENTRAL RULE: this module never rebuilds the file from a model.
// It keeps the original lines and edits only the lines it has to. That
// is what makes "parse then serialize with no changes produces an
// identical file" true by construction rather than by effort, and it is
// what guarantees notes, headings, front matter, blank lines and any
// markdown we do not understand survive untouched.
//
// Every mutation takes the FULL CURRENT TEXT and returns new text. There
// is deliberately no long-lived document object: on a machine syncing
// over Syncthing, the only safe write is re-read -> apply -> write, and
// an API that cannot hold a stale copy cannot write one by mistake.
//
// Tasks are addressed by their exact raw line. If that line is no longer
// in the file (it changed on another device between read and click), the
// operation reports failure instead of guessing which line was meant.

// ---------------------------------------------------------------------
// patterns
// ---------------------------------------------------------------------

// Obsidian's own checkbox toggle writes "- [x]"; some editors use "*".
// The space after the bracket is optional so "- [ ]" with nothing after
// it still parses as an (empty) task rather than as prose.
var TASK_RE = /^([ \t]*)([-*]) \[([ xX\-])\] ?(.*)$/;

// The Tasks plugin's done marker. We are not using that plugin, so this
// module is the only thing that ever writes one -- but the format is
// kept identical so a vault that has seen the plugin still reads right.
var DONE_MARK = "✅";
var DATE_RE = /✅[ \t]*(\d{4}-\d{2}-\d{2})/;

// "!2" as a whole token, so "wow!2 things" is not an importance.
var IMP_RE = /(^|[ \t])!(\d+)(?=[ \t]|$)/;

// Category marker.
//
// Deliberately "@name", not "#name". A # makes Obsidian index the word
// as a real tag: every category shows up in the tag pane, in
// autocomplete and as a node in the graph, which buries the tags you
// actually meant to write. Obsidian attaches no meaning to @, so a
// category is invisible to it while staying readable in the raw file
// and typable on a phone.
//
// Any #tag you write yourself is now just text to this parser and is
// carried through untouched.
var CAT_RE = /(^|[ \t])@([^\s@]+)/g;

// Used only by the one-off migration below, never by normal parsing.
var LEGACY_PREFIX = "#";

var H2_DONE = /^##[ \t]+Done[ \t]*$/i;
var H3_DATE = /^###[ \t]+(\d{4}-\d{2}-\d{2})[ \t]*$/;
var ANY_H1_H2 = /^#{1,2}[ \t]+\S/;

// ---------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------

function pad2(n) { return n < 10 ? "0" + n : "" + n; }

// Local date, not UTC: toISOString() would roll over at 02:00 Warsaw
// time in summer and file a task under the previous day.
function isoDate(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function today() { return isoDate(new Date()); }

function parseIso(s) {
    var p = s.split("-");
    return new Date(+p[0], +p[1] - 1, +p[2]);
}

// Split keeping enough information to put the file back together byte
// for byte: whether it ended with a newline, and which newline.
function splitLines(text) {
    var eol = text.indexOf("\r\n") !== -1 ? "\r\n" : "\n";
    var trailing = text.length > 0 && text.slice(-eol.length) === eol;
    var body = trailing ? text.slice(0, -eol.length) : text;
    return { lines: body === "" && !trailing ? [] : body.split(eol), eol: eol, trailing: trailing };
}

function joinLines(doc) {
    return doc.lines.join(doc.eol) + (doc.trailing ? doc.eol : "");
}

// ---------------------------------------------------------------------
// line-level parsing
// ---------------------------------------------------------------------

// Pull the known tokens out of a task's body. Everything not recognised
// stays in `text`, including tags that are not configured categories --
// "Other tags are kept untouched" means they ride along in the text and
// get written back verbatim.
function splitBody(body, categoryNames) {
    var rest = body;
    var doneDate = null;
    var importance = null;
    var category = null;

    var m = DATE_RE.exec(rest);
    if (m) {
        doneDate = m[1];
        rest = rest.slice(0, m.index) + rest.slice(m.index + m[0].length);
    }

    m = IMP_RE.exec(rest);
    if (m) {
        importance = parseInt(m[2], 10);
        rest = rest.slice(0, m.index) + m[1] + rest.slice(m.index + m[0].length);
    }

    // First @marker that names a configured category wins; any other
    // @word is left in the text untouched.
    if (categoryNames && categoryNames.length > 0) {
        CAT_RE.lastIndex = 0;
        var t;
        while ((t = CAT_RE.exec(rest)) !== null) {
            var name = t[2];
            if (categoryNames.indexOf(name) !== -1) {
                category = name;
                rest = rest.slice(0, t.index) + t[1] + rest.slice(t.index + t[0].length);
                break;
            }
        }
    }

    return {
        text: rest.replace(/[ \t]{2,}/g, " ").trim(),
        category: category,
        importance: importance,
        doneDate: doneDate
    };
}

// The one place a task line is written. Token order is fixed here:
// text, @category, !N, done date.
function renderTask(t) {
    var s = t.indent + t.bullet + " [" + t.mark + "]";
    var body = t.text;
    if (t.category) body += (body ? " " : "") + "@" + t.category;
    if (t.importance !== null && t.importance !== undefined)
        body += (body ? " " : "") + "!" + t.importance;
    if (t.doneDate) body += (body ? " " : "") + DONE_MARK + " " + t.doneDate;
    return body === "" ? s : s + " " + body;
}

// ---------------------------------------------------------------------
// document parsing
// ---------------------------------------------------------------------

// Returns { lines, eol, trailing, tasks, doneStart, dateHeadings, order }
//
// Only unindented task lines are tasks. An indented one is a subtask or
// a note and belongs to the task above it, so it travels with it when
// the task moves between sections.
function parseDoc(text, categoryNames) {
    var doc = splitLines(text);
    doc.tasks = [];
    doc.doneStart = -1;
    doc.dateHeadings = [];     // { line, date }

    var cur = null;
    // Tracked as we go. Resolving it afterwards by scanning the heading
    // list per task is O(tasks x headings) -- on ten years of data that
    // is 18k x 3.6k = 66 million iterations, and it was the single
    // reason a parse took half a second.
    var curHeading = null;
    var inDone = false;

    for (var i = 0; i < doc.lines.length; i++) {
        var line = doc.lines[i];

        if (doc.doneStart === -1 && H2_DONE.test(line)) { doc.doneStart = i; inDone = true; }

        var h3 = H3_DATE.exec(line);
        if (h3) {
            doc.dateHeadings.push({ line: i, date: h3[1] });
            curHeading = h3[1];
            cur = null;
            continue;
        }

        // A new heading ends whatever block was open.
        if (ANY_H1_H2.test(line)) { cur = null; continue; }

        var m = TASK_RE.exec(line);
        if (m && m[1] === "") {
            var parts = splitBody(m[4], categoryNames);
            cur = {
                line: i,
                last: i,                 // last line of the block, inclusive
                raw: line,
                indent: "",
                bullet: m[2],
                mark: m[3] === "X" ? "x" : m[3],
                text: parts.text,
                category: parts.category,
                importance: parts.importance,
                doneDate: parts.doneDate,
                headingDate: curHeading,
                inDone: inDone
            };
            doc.tasks.push(cur);
            continue;
        }

        // Indented continuation (including indented sub-checkboxes).
        if (cur !== null && /^[ \t]+\S/.test(line)) { cur.last = i; continue; }

        // A blank line inside an indented block keeps the block open;
        // anything else closes it.
        if (cur !== null && line.trim() === "") continue;
        cur = null;
    }

    // Blank lines swept up at the end of a block are not part of it.
    for (var k = 0; k < doc.tasks.length; k++) {
        var t = doc.tasks[k];
        while (t.last > t.line && doc.lines[t.last].trim() === "") t.last--;
    }

    // Section and heading were captured during the scan above; only the
    // mark still needs decoding.
    for (var j = 0; j < doc.tasks.length; j++) {
        var task = doc.tasks[j];
        task.done = task.mark === "x";
        task.cancelled = task.mark === "-";
        task.open = task.mark === " ";
    }

    return doc;
}

// ---------------------------------------------------------------------
// public read API
// ---------------------------------------------------------------------

// The display model. `effectiveDate` is what stats count by: the done
// date on the line is the source of truth, and the heading above it is
// only a fallback for a task ticked elsewhere that has not been stamped
// yet. Cancelled tasks are never counted anywhere.
function readTasks(text, cfg) {
    var names = (cfg && cfg.categories ? cfg.categories : []).map(function (c) { return c.name; });
    var doc = parseDoc(text, names);
    var out = [];
    for (var i = 0; i < doc.tasks.length; i++) {
        var t = doc.tasks[i];
        out.push({
            raw: t.raw,
            text: t.text,
            category: t.category,
            importance: t.importance,
            doneDate: t.doneDate,
            effectiveDate: t.doneDate || (t.done ? t.headingDate : null),
            done: t.done,
            cancelled: t.cancelled,
            open: t.open,
            inDone: t.inDone,
            hasChildren: t.last > t.line
        });
    }
    return out;
}

// Everything the dashboard needs on open, from ONE parse.
//
// readTasks, buildStats and needsStamping each walk the whole file. Run
// back to back that is three full parses for one keypress, and on ten
// years of tasks that was most of the time spent opening the panel.
// The view model, the stats cache and the stamping question all come
// out of the same pass here.
function analyze(text, cfg) {
    var names = catNames(cfg);
    var doc = parseDoc(text, names);

    var tasks = [];
    var byDate = {};
    var total = 0;
    var first = null;
    var last = null;
    var needsStamp = false;

    for (var i = 0; i < doc.tasks.length; i++) {
        var t = doc.tasks[i];
        var eff = t.doneDate || (t.done ? t.headingDate : null);

        tasks.push({
            raw: t.raw,
            text: t.text,
            category: t.category,
            importance: t.importance,
            doneDate: t.doneDate,
            effectiveDate: eff,
            done: t.done,
            cancelled: t.cancelled,
            open: t.open,
            inDone: t.inDone,
            hasChildren: t.last > t.line
        });

        if (t.done && (!t.doneDate || !t.inDone)) needsStamp = true;
        if (!t.done || t.cancelled || !eff) continue;

        var e = byDate[eff];
        if (!e) { e = { total: 0, cat: {}, imp: {} }; byDate[eff] = e; }
        e.total++;
        total++;
        var c = t.category || "uncategorized";
        e.cat[c] = (e.cat[c] || 0) + 1;
        if (t.importance !== null && t.importance !== undefined)
            e.imp[t.importance] = (e.imp[t.importance] || 0) + 1;

        if (first === null || eff < first) first = eff;
        if (last === null || eff > last) last = eff;
    }

    return {
        tasks: tasks,
        stats: { byDate: byDate, total: total, first: first, last: last },
        needsStamp: needsStamp
    };
}

// True when there is a [x] with no done date, or a [x] sitting in the
// open section. Those are the tasks ticked on the phone; the dashboard
// stamps them, and this says whether stamping would change anything so
// the caller can skip a pointless write.
function needsStamping(text, cfg) {
    var names = (cfg && cfg.categories ? cfg.categories : []).map(function (c) { return c.name; });
    var doc = parseDoc(text, names);
    for (var i = 0; i < doc.tasks.length; i++) {
        var t = doc.tasks[i];
        if (t.done && (!t.doneDate || !t.inDone)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------
// structural helpers for mutations
// ---------------------------------------------------------------------

function findByRaw(doc, raw) {
    for (var i = 0; i < doc.tasks.length; i++)
        if (doc.tasks[i].raw === raw) return doc.tasks[i];
    return null;
}

function cutBlock(doc, task) {
    var block = doc.lines.slice(task.line, task.last + 1);
    doc.lines.splice(task.line, task.last - task.line + 1);
    return block;
}

// End of the open section: just before "## Done", or end of file.
// Trailing blank lines are stepped over so added tasks land against the
// existing list rather than after a gap.
function openSectionEnd(doc) {
    var end = doc.doneStart === -1 ? doc.lines.length : doc.doneStart;
    while (end > 0 && doc.lines[end - 1].trim() === "") end--;
    return end;
}

// Insert (creating "## Done" and "### <date>" when missing) and return
// the index the block was written at. Date headings are kept newest
// first, which is the order the file is read in.
function insertUnderDate(doc, block, date) {
    if (doc.doneStart === -1) {
        var at = doc.lines.length;
        while (at > 0 && doc.lines[at - 1].trim() === "") at--;
        var header = [];
        if (at > 0) header.push("");
        header.push("## Done");
        doc.lines.splice(at, 0, ...header);
        doc.doneStart = at + header.length - 1;
        doc.dateHeadings = [];
        reindexHeadings(doc);
    }

    var headings = doc.dateHeadings;
    for (var i = 0; i < headings.length; i++) {
        if (headings[i].date === date) {
            // Appended to the end of that day's block, not straight
            // after the heading: stamping several phone ticks at once
            // inserts them one by one, and inserting at the top would
            // reverse their order relative to the file.
            var at = endOfHeadingBlock(doc, headings[i]);
            doc.lines.splice(at, 0, ...block);
            return at;
        }
    }

    // No heading for this date: put it before the first older one, or
    // at the top of the Done section if it is the newest.
    var insertAt = -1;
    for (var j = 0; j < headings.length; j++) {
        if (headings[j].date < date) { insertAt = headings[j].line; break; }
    }
    if (insertAt === -1) {
        insertAt = headings.length > 0
            ? endOfHeadingBlock(doc, headings[headings.length - 1])
            : doc.doneStart + 1;
        while (insertAt < doc.lines.length && doc.lines[insertAt].trim() === "") insertAt++;
    }

    var chunk = ["### " + date].concat(block);
    if (insertAt > 0 && doc.lines[insertAt - 1] !== undefined
        && doc.lines[insertAt - 1].trim() !== "") chunk.unshift("");
    if (insertAt < doc.lines.length && doc.lines[insertAt].trim() !== "") chunk.push("");
    doc.lines.splice(insertAt, 0, ...chunk);
    return insertAt + (chunk[0] === "" ? 2 : 1);
}

function endOfHeadingBlock(doc, heading) {
    var i = heading.line + 1;
    while (i < doc.lines.length && !H3_DATE.test(doc.lines[i]) && !ANY_H1_H2.test(doc.lines[i])) i++;
    while (i > heading.line + 1 && doc.lines[i - 1].trim() === "") i--;
    return i;
}

function reindexHeadings(doc) {
    doc.dateHeadings = [];
    doc.doneStart = -1;
    for (var i = 0; i < doc.lines.length; i++) {
        if (doc.doneStart === -1 && H2_DONE.test(doc.lines[i])) doc.doneStart = i;
        var h = H3_DATE.exec(doc.lines[i]);
        if (h) doc.dateHeadings.push({ line: i, date: h[1] });
    }
}

function result(ok, text, reason) {
    return { ok: ok, text: text, reason: reason || null };
}

// ---------------------------------------------------------------------
// mutations
// ---------------------------------------------------------------------

// Tick: stamp the date and move the task (with its subtasks) under
// today's heading in the Done section.
function tick(text, raw, cfg, dateStr) {
    var names = catNames(cfg);
    var doc = parseDoc(text, names);
    var t = findByRaw(doc, raw);
    if (!t) return result(false, text, "that line is no longer in the file");

    var date = dateStr || today();
    t.mark = "x";
    t.doneDate = t.doneDate || date;
    var block = cutBlock(doc, t);
    block[0] = renderTask(t);
    reindexHeadings(doc);
    insertUnderDate(doc, block, t.doneDate);
    return result(true, joinLines(doc));
}

// Untick: drop the done date and put the task back at the end of the
// open list. The now-empty date heading is removed so the Done section
// does not fill up with headings for days with nothing under them.
function untick(text, raw, cfg) {
    var doc = parseDoc(text, catNames(cfg));
    var t = findByRaw(doc, raw);
    if (!t) return result(false, text, "that line is no longer in the file");

    t.mark = " ";
    t.doneDate = null;
    var block = cutBlock(doc, t);
    block[0] = renderTask(t);
    reindexHeadings(doc);
    dropEmptyDateHeadings(doc);
    doc.lines.splice(openSectionEnd(doc), 0, ...block);
    return result(true, joinLines(doc));
}

function dropEmptyDateHeadings(doc) {
    for (var i = doc.lines.length - 1; i >= 0; i--) {
        if (!H3_DATE.test(doc.lines[i])) continue;
        var j = i + 1;
        var empty = true;
        while (j < doc.lines.length && !H3_DATE.test(doc.lines[j]) && !ANY_H1_H2.test(doc.lines[j])) {
            if (doc.lines[j].trim() !== "") { empty = false; break; }
            j++;
        }
        if (empty) doc.lines.splice(i, j - i);
    }
    reindexHeadings(doc);
}

function setCancelled(text, raw, cancelled, cfg) {
    var doc = parseDoc(text, catNames(cfg));
    var t = findByRaw(doc, raw);
    if (!t) return result(false, text, "that line is no longer in the file");
    t.mark = cancelled ? "-" : " ";
    doc.lines[t.line] = renderTask(t);
    return result(true, joinLines(doc));
}

function editTask(text, raw, fields, cfg) {
    var doc = parseDoc(text, catNames(cfg));
    var t = findByRaw(doc, raw);
    if (!t) return result(false, text, "that line is no longer in the file");
    if (fields.text !== undefined) t.text = fields.text.trim();
    if (fields.category !== undefined) t.category = fields.category || null;
    if (fields.importance !== undefined)
        t.importance = (fields.importance === null || fields.importance === "")
            ? null : parseInt(fields.importance, 10);
    doc.lines[t.line] = renderTask(t);
    return result(true, joinLines(doc));
}

function deleteTask(text, raw, cfg) {
    var doc = parseDoc(text, catNames(cfg));
    var t = findByRaw(doc, raw);
    if (!t) return result(false, text, "that line is no longer in the file");
    cutBlock(doc, t);
    reindexHeadings(doc);
    dropEmptyDateHeadings(doc);
    return result(true, joinLines(doc));
}

function addTask(text, fields, cfg) {
    var doc = parseDoc(text, catNames(cfg));
    var line = renderTask({
        indent: "", bullet: "-", mark: " ",
        text: (fields.text || "").trim(),
        category: fields.category || null,
        importance: (fields.importance === null || fields.importance === undefined
                     || fields.importance === "") ? null : parseInt(fields.importance, 10),
        doneDate: null
    });
    var at = openSectionEnd(doc);
    doc.lines.splice(at, 0, line);
    return result(true, joinLines(doc));
}

// The phone-tick reconciliation, run when the dashboard opens.
//
// Without the Tasks plugin, Obsidian's checkbox toggle writes "[x]" and
// nothing else: no date, and the line stays where it was. So any [x]
// without a date gets today's, and any [x] left in the open section is
// moved into Done. Today's date is a floor, not the truth -- the task
// may have been ticked days ago on the phone -- which is the price of
// not running a plugin, and is why this runs on open rather than on
// some later edit.
function stampUndated(text, cfg, dateStr) {
    var date = dateStr || today();
    var names = catNames(cfg);
    var changed = false;

    // One at a time, re-parsing after each move: every move shifts the
    // line numbers of everything below it, and re-parsing is far
    // cheaper than keeping a second set of indices correct by hand.
    for (var guard = 0; guard < 10000; guard++) {
        var doc = parseDoc(text, names);
        var target = null;
        for (var i = 0; i < doc.tasks.length; i++) {
            var t = doc.tasks[i];
            if (t.done && (!t.doneDate || !t.inDone)) { target = t; break; }
        }
        if (!target) break;

        var r = tick(text, target.raw, cfg, target.doneDate || date);
        if (!r.ok) break;
        text = r.text;
        changed = true;
    }
    return { ok: true, text: text, changed: changed };
}

// ---------------------------------------------------------------------
// one-off migration from the old #tag marker
// ---------------------------------------------------------------------

function escapeRe(x) { return x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

// Finds "#name" on a task line where name is a configured category and
// the line has no @category yet. Only exact whole-token matches, so
// "#jobsearch" is never mistaken for "#job", and only task lines, so a
// #tag in a note stays a tag.
function scanLegacyTags(text, cfg, rewrite) {
    var names = catNames(cfg);
    var doc = parseDoc(text, names);
    var count = 0;

    for (var i = 0; i < doc.tasks.length; i++) {
        var t = doc.tasks[i];
        // Already carries an @category: nothing to convert, and a line
        // with both should keep the one it is actually using.
        if (t.category !== null) continue;

        var line = doc.lines[t.line];
        for (var k = 0; k < names.length; k++) {
            var re = new RegExp("(^|[ \t])" + LEGACY_PREFIX + escapeRe(names[k])
                                + "(?=[ \t]|$)");
            var m = re.exec(line);
            if (!m) continue;
            count++;
            if (rewrite) {
                doc.lines[t.line] = line.slice(0, m.index) + m[1] + "@" + names[k]
                                  + line.slice(m.index + m[0].length);
            }
            break;
        }
    }
    return { count: count, text: rewrite ? joinLines(doc) : text };
}

function needsTagMigration(text, cfg) {
    return scanLegacyTags(text, cfg, false).count > 0;
}

// Rewrites every configured category's #tag to @tag, in one pass, and
// touches nothing else -- importance, done dates, notes, sub-tasks and
// any #tag that is not a category are all left exactly as they were.
function migrateTags(text, cfg) {
    var r = scanLegacyTags(text, cfg, true);
    return { ok: true, text: r.text, count: r.count };
}

// Renaming a category rewrites the marker on every task that carries
// it, and only that one: a category whose name merely starts with the
// same letters is left alone, and anything inside prose stays put
// because only task lines are touched.
function renameCategory(text, oldName, newName, cfg) {
    var names = catNames(cfg);
    if (names.indexOf(oldName) === -1) names = names.concat([oldName]);
    var doc = parseDoc(text, names);
    var hits = 0;
    for (var i = 0; i < doc.tasks.length; i++) {
        var t = doc.tasks[i];
        if (t.category !== oldName) continue;
        t.category = newName;
        doc.lines[t.line] = renderTask(t);
        hits++;
    }
    return { ok: true, text: joinLines(doc), count: hits };
}

function catNames(cfg) {
    return (cfg && cfg.categories ? cfg.categories : []).map(function (c) { return c.name; });
}

// ---------------------------------------------------------------------
// config.md
// ---------------------------------------------------------------------

var CFG_H2 = /^##[ \t]+(.+?)[ \t]*$/;
var CFG_CAT = /^[-*][ \t]+(.+?)[ \t]+`(#[0-9a-fA-F]{3,8})`[ \t]*$/;
var CFG_IMP = /^[-*][ \t]+(\d+)[ \t]+(.+?)[ \t]+`(#[0-9a-fA-F]{3,8})`[ \t]*$/;

function readConfig(text) {
    var categories = [];
    var importance = [];
    var section = "";
    var lines = splitLines(text).lines;

    for (var i = 0; i < lines.length; i++) {
        var h = CFG_H2.exec(lines[i]);
        if (h) { section = h[1].toLowerCase(); continue; }

        if (section.indexOf("categor") === 0) {
            var c = CFG_CAT.exec(lines[i]);
            if (c) categories.push({ name: c[1].replace(/^#/, ""), color: c[2] });
        } else if (section.indexOf("importance") === 0) {
            var m = CFG_IMP.exec(lines[i]);
            if (m) importance.push({ level: parseInt(m[1], 10), label: m[2], color: m[3] });
        }
    }

    importance.sort(function (a, b) { return a.level - b.level; });
    return { categories: categories, importance: importance };
}

// Rewrites only the list items inside the two sections, leaving every
// other line in config.md -- prose, extra headings, anything -- alone.
function writeConfig(text, cfg) {
    var doc = splitLines(text);
    if (doc.lines.length === 0) doc.lines = ["## Categories", "", "## Importance", ""];

    var out = [];
    var section = "";
    var emitted = { cat: false, imp: false };

    for (var i = 0; i < doc.lines.length; i++) {
        var line = doc.lines[i];
        var h = CFG_H2.exec(line);
        if (h) {
            section = h[1].toLowerCase();
            out.push(line);
            if (section.indexOf("categor") === 0) {
                emitted.cat = true;
                for (var a = 0; a < cfg.categories.length; a++)
                    out.push("- " + cfg.categories[a].name + " `" + cfg.categories[a].color + "`");
            } else if (section.indexOf("importance") === 0) {
                emitted.imp = true;
                for (var b = 0; b < cfg.importance.length; b++)
                    out.push("- " + cfg.importance[b].level + " " + cfg.importance[b].label
                             + " `" + cfg.importance[b].color + "`");
            }
            continue;
        }
        // Drop the old entries of a managed section; keep everything else.
        var managed = (section.indexOf("categor") === 0 && CFG_CAT.test(line))
                   || (section.indexOf("importance") === 0 && CFG_IMP.test(line));
        if (!managed) out.push(line);
    }

    if (!emitted.cat) {
        if (out.length && out[out.length - 1].trim() !== "") out.push("");
        out.push("## Categories");
        for (var c2 = 0; c2 < cfg.categories.length; c2++)
            out.push("- " + cfg.categories[c2].name + " `" + cfg.categories[c2].color + "`");
    }
    if (!emitted.imp) {
        if (out.length && out[out.length - 1].trim() !== "") out.push("");
        out.push("## Importance");
        for (var d2 = 0; d2 < cfg.importance.length; d2++)
            out.push("- " + cfg.importance[d2].level + " " + cfg.importance[d2].label
                     + " `" + cfg.importance[d2].color + "`");
    }

    doc.lines = out;
    return joinLines(doc);
}

// ---------------------------------------------------------------------
// stats cache
// ---------------------------------------------------------------------

// Built once per file change. Everything the stats view shows -- any
// range, any filter -- is derived from this table without touching the
// text again, which is what keeps range toggles free.
//
//   byDate: { "2026-10-08": { total, cat: {name: n}, imp: {level: n} } }
function buildStats(text, cfg) {
    var tasks = readTasks(text, cfg);
    var byDate = {};
    var total = 0;
    var first = null;
    var last = null;

    for (var i = 0; i < tasks.length; i++) {
        var t = tasks[i];
        if (!t.done || t.cancelled) continue;
        var d = t.effectiveDate;
        if (!d) continue;

        if (!byDate[d]) byDate[d] = { total: 0, cat: {}, imp: {} };
        var e = byDate[d];
        e.total++;
        total++;
        var c = t.category || "uncategorized";
        e.cat[c] = (e.cat[c] || 0) + 1;
        if (t.importance !== null && t.importance !== undefined)
            e.imp[t.importance] = (e.imp[t.importance] || 0) + 1;

        if (first === null || d < first) first = d;
        if (last === null || d > last) last = d;
    }

    return { byDate: byDate, total: total, first: first, last: last };
}

// Count on one day under the active filters.
function countOn(stats, date, category, importance) {
    var e = stats.byDate[date];
    if (!e) return 0;
    if (category && importance !== null && importance !== undefined) {
        // Both filters at once needs per-task detail the cache does not
        // keep, so the narrower of the two is used. Kept deliberately:
        // storing the cross product would make the cache quadratic in
        // categories x levels for a gain nobody looks at.
        return Math.min(e.cat[category] || 0, e.imp[importance] || 0);
    }
    if (category) return e.cat[category] || 0;
    if (importance !== null && importance !== undefined) return e.imp[importance] || 0;
    return e.total;
}

// Days with at least one completion, counted backwards from `from`
// (default today). A streak that ended yesterday still counts today, so
// the number does not reset at midnight before you have done anything.
function currentStreak(stats, category, importance, fromDate) {
    var d = fromDate ? parseIso(fromDate) : new Date();
    var n = 0;
    if (countOn(stats, isoDate(d), category, importance) === 0) {
        d.setDate(d.getDate() - 1);
        if (countOn(stats, isoDate(d), category, importance) === 0) return 0;
    }
    while (countOn(stats, isoDate(d), category, importance) > 0) {
        n++;
        d.setDate(d.getDate() - 1);
    }
    return n;
}

function longestStreak(stats, category, importance) {
    var dates = Object.keys(stats.byDate).filter(function (d) {
        return countOn(stats, d, category, importance) > 0;
    }).sort();
    var best = 0, run = 0, prev = null;
    for (var i = 0; i < dates.length; i++) {
        var d = parseIso(dates[i]);
        if (prev !== null && Math.round((d - prev) / 86400000) === 1) run++;
        else run = 1;
        if (run > best) best = run;
        prev = d;
    }
    return best;
}

// Weeks start on Monday. getDay() calls Sunday 0, so Sunday is pulled
// back six days rather than forward one.
function startOfWeek(d) {
    var x = new Date(d);
    var wd = (x.getDay() + 6) % 7;
    x.setDate(x.getDate() - wd);
    x.setHours(0, 0, 0, 0);
    return x;
}

function addDays(d, n) {
    var x = new Date(d);
    x.setDate(x.getDate() + n);
    return x;
}

// One pass over an inclusive date range, producing everything both
// charts and all four numbers need. Lives here rather than in the view
// so the arithmetic can be tested without a running Quickshell.
function aggregateRange(stats, startIso, endIso, category, importance) {
    var days = [];
    var total = 0;
    var max = 0;
    var best = { date: null, count: 0 };

    var end = parseIso(endIso);
    for (var d = parseIso(startIso); d <= end; d = addDays(d, 1)) {
        var key = isoDate(d);
        var n = countOn(stats, key, category, importance);
        days.push({ date: key, count: n });
        total += n;
        if (n > max) max = n;
        if (n > best.count) best = { date: key, count: n };
    }

    var run = 0, longest = 0;
    for (var i = 0; i < days.length; i++) {
        run = days[i].count > 0 ? run + 1 : 0;
        if (run > longest) longest = run;
    }

    return { days: days, total: total, max: max, best: best, longest: longest };
}

// Collapse days into bars. Ten years per day would be 3650 bars in a
// 690px box, so beyond a month the unit grows: weeks, then months.
function bucketBars(days, unit) {
    var out = [];
    var byKey = {};
    for (var i = 0; i < days.length; i++) {
        var date = parseIso(days[i].date);
        var key, label;
        if (unit === "day") {
            key = days[i].date;
            label = "" + date.getDate();
        } else if (unit === "week") {
            key = isoDate(startOfWeek(date));
            label = date.getDate() + "/" + (date.getMonth() + 1);
        } else {
            key = date.getFullYear() + "-" + pad2(date.getMonth() + 1);
            label = (date.getMonth() + 1) + "/" + ("" + date.getFullYear()).slice(2);
        }
        if (byKey[key] === undefined) {
            byKey[key] = out.length;
            out.push({ key: key, label: label, count: 0 });
        }
        out[byKey[key]].count += days[i].count;
    }
    return out;
}

function bestDay(stats, category, importance) {
    var best = { date: null, count: 0 };
    for (var d in stats.byDate) {
        var n = countOn(stats, d, category, importance);
        if (n > best.count) best = { date: d, count: n };
    }
    return best;
}
