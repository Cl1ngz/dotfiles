import QtQuick
import Quickshell
import Quickshell.Io
import "Parse.js" as Parse

// File access for the task dashboard.
//
// Everything about this component exists to make one guarantee: a write
// is always re-read -> apply -> atomic rename, never a dump of whatever
// was in memory. Several laptops and a phone sync this folder with
// Syncthing, and a stale write is how you get sync-conflict copies and
// lost tasks.
//
// Reads go through `cat` and writes through a temp file plus `mv -f`,
// both in the same directory so the rename is atomic on the same
// filesystem. Syncthing itself replaces files by renaming, which is why
// the dashboard re-reads before every write rather than trusting a
// watch to have told it about a change.
Item {
    id: store

    // THE one place the vault path is configured.
    property string dir: "/home/cl1ngz/Documents/Notes/Main_Valut/Other/Tasker"

    readonly property string tasksPath: dir + "/tasks.md"
    readonly property string configPath: dir + "/config.md"

    // Raw file contents, as last read from disk.
    property string tasksText: ""
    property string configText: ""

    property var config: ({ categories: [], importance: [] })
    property var tasks: []
    property var stats: ({ byDate: ({}), total: 0, first: null, last: null })

    property bool loaded: false
    property bool busy: false
    property string error: ""
    property bool hasConflicts: false
    // Set once per session when the dashboard stamps phone ticks, so
    // the UI can say what it silently changed on your behalf.
    property int stampedCount: 0
    // How many "#category" markers were converted to "@category" on
    // this open. See Parse.migrateTags for why the marker changed.
    property int migratedCount: 0

    // Not named `changed`: QML generates <prop>Changed signals for every
    // property, and a bare `changed` invites a collision with one.
    signal refreshed()

    // ---- reading -----------------------------------------------------

    function reload() {
        readConfig.running = false;
        readConfig.running = true;
    }

    // config first: tasks cannot be parsed without the category list,
    // because which #tag counts as a category comes from config.md.
    Process {
        id: readConfig
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || true', "--", store.configPath]
        stdout: StdioCollector {
            onStreamFinished: {
                store.configText = text;
                store.config = Parse.readConfig(text);
                readTasks.running = false;
                readTasks.running = true;
            }
        }
    }

    Process {
        id: readTasks
        command: ["sh", "-c", 'cat "$1" 2>/dev/null || true', "--", store.tasksPath]
        stdout: StdioCollector {
            onStreamFinished: {
                store.tasksText = text;
                store.reparse();
                store.loaded = true;
                store.refreshed();
            }
        }
    }

    // ONE parse per file change, producing the task list, the stats
    // cache and the stamping question together. Range and filter
    // toggles in the stats view never touch the text again -- they only
    // index into stats.byDate.
    property bool needsStamp: false
    function reparse() {
        const a = Parse.analyze(tasksText, config);
        tasks = a.tasks;
        stats = a.stats;
        needsStamp = a.needsStamp;
    }

    Process {
        id: conflictScan
        command: ["sh", "-c",
            'ls -1 "$1"/*.sync-conflict-* 2>/dev/null | head -n 20', "--", store.dir]
        stdout: StdioCollector {
            onStreamFinished: store.hasConflicts = text.trim() !== ""
        }
    }

    // ---- writing -----------------------------------------------------

    // The whole file goes in over stdin, not as an argument: Linux caps
    // a single argv string at 128 KiB (MAX_ARG_STRLEN), and ten years of
    // tasks is comfortably past that. A long file passed as an argument
    // would fail with E2BIG only once the vault got big enough, which is
    // the worst possible time to find out.
    Process {
        id: writer
        property string target: ""
        property string pending: ""
        // NOT named onDone: a property whose name is on<Capital> is
        // parsed as a signal handler and the file fails to load.
        property var afterWrite: null

        stdinEnabled: false

        onExited: (code) => {
            store.busy = false;
            if (code !== 0) {
                store.error = "write failed (exit " + code + ") -- nothing was changed, "
                            + "the original file is untouched";
            } else {
                store.error = "";
            }
            const cb = afterWrite;
            afterWrite = null;
            if (code === 0 && cb) cb();

            // A failed write drops anything still queued: the queue was
            // built from one logical change, and applying half of it
            // (config renamed, tasks.md not) is worse than applying
            // none of it.
            if (code !== 0) store.writeQueue = [];

            if (store.writeQueue.length > 0) { store.pumpWrites(); return; }

            // Always re-read: on success to pick up what we wrote, on
            // failure to make sure the UI reflects what is really there.
            store.reload();
        }
    }

    // Writes are queued, not fired in parallel. Renaming a category
    // touches both tasks.md and config.md, and two Processes writing at
    // once would race each other's reload. One at a time, in order.
    property var writeQueue: []

    function enqueueWrite(path, content) {
        writeQueue = writeQueue.concat([{ path: path, content: content }]);
        pumpWrites();
    }

    function pumpWrites() {
        if (busy || writeQueue.length === 0) return;
        const next = writeQueue[0];
        writeQueue = writeQueue.slice(1);
        writeFile(next.path, next.content);
    }

    function writeFile(path, content, done) {
        if (busy) { error = "a write is already in flight"; return; }
        busy = true;
        error = "";
        writer.target = path;
        writer.afterWrite = done ?? null;
        writer.command = ["sh", "-c",
            // mktemp in the same directory so the rename is atomic
            // rather than a cross-filesystem copy. The trap removes the
            // temp file if anything fails, so a half-written file is
            // never left lying next to the real one for Syncthing to
            // pick up and propagate.
            'f="$1"; d=$(dirname "$f"); ' +
            'tmp=$(mktemp "$d/.tasker.XXXXXX") || exit 1; ' +
            'trap \'rm -f "$tmp"\' EXIT; ' +
            'cat > "$tmp" || exit 1; ' +
            'chmod 644 "$tmp" || exit 1; ' +
            'mv -f "$tmp" "$f" || exit 1; ' +
            'trap - EXIT',
            "--", path];
        // stdin has to be enabled before the process starts, or the
        // pipe does not exist when `cat` begins reading.
        writer.stdinEnabled = true;
        writer.running = true;
        writer.write(content);
        // Closing stdin is what sends EOF, which is what lets `cat`
        // finish. Without this the process hangs forever.
        writer.stdinEnabled = false;
    }

    // ---- mutations ---------------------------------------------------
    //
    // Each one re-reads the file, applies the change to THAT text, and
    // writes the result. They take the task's raw line, so if the line
    // changed on another device in between, Parse refuses rather than
    // editing the wrong task.

    Process {
        id: rmw
        property string op: ""
        property var args: ({})

        command: ["sh", "-c", 'cat "$1" 2>/dev/null || true', "--", store.tasksPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const fresh = text;
                let r = null;

                switch (rmw.op) {
                case "tick":     r = Parse.tick(fresh, rmw.args.raw, store.config); break;
                case "untick":   r = Parse.untick(fresh, rmw.args.raw, store.config); break;
                case "cancel":   r = Parse.setCancelled(fresh, rmw.args.raw, true, store.config); break;
                case "uncancel": r = Parse.setCancelled(fresh, rmw.args.raw, false, store.config); break;
                case "edit":     r = Parse.editTask(fresh, rmw.args.raw, rmw.args.fields, store.config); break;
                case "delete":   r = Parse.deleteTask(fresh, rmw.args.raw, store.config); break;
                case "add":      r = Parse.addTask(fresh, rmw.args.fields, store.config); break;
                case "stamp":    r = Parse.stampUndated(fresh, store.config); break;
                case "migrate":  r = Parse.migrateTags(fresh, store.config); break;
                case "rename":
                    r = Parse.renameCategory(fresh, rmw.args.from, rmw.args.to, store.config);
                    break;
                case "applyConfig": {
                    // Renames are applied to tasks.md one after another
                    // on the same fresh text, then both files are
                    // queued together: a category must never exist in
                    // config.md under one name and in tasks.md under
                    // another.
                    let t = fresh;
                    const cfg = rmw.args.cfg;
                    for (const ren of rmw.args.renames)
                        t = Parse.renameCategory(t, ren.from, ren.to, store.config).text;
                    store.busy = false;
                    if (t !== fresh) store.enqueueWrite(store.tasksPath, t);
                    store.enqueueWrite(store.configPath,
                                       Parse.writeConfig(store.configText, cfg));
                    return;
                }
                }

                if (!r) { store.busy = false; return; }

                if (r.ok === false) {
                    // The line moved or changed under us. Say so plainly
                    // and reload, rather than writing something that
                    // would clobber the other device's edit.
                    store.busy = false;
                    store.error = r.reason + " -- reloaded, try again";
                    store.tasksText = fresh;
                    store.reparse();
                    store.refreshed();
                    return;
                }

                if (rmw.op === "migrate") {
                    store.migratedCount = r.count;
                    if (r.count === 0) {
                        store.busy = false;
                        store.tasksText = fresh;
                        store.reparse();
                        store.refreshed();
                        return;
                    }
                }

                if (rmw.op === "stamp") {
                    if (!r.changed) {
                        // Nothing to stamp: do not write at all. An
                        // unnecessary write is a Syncthing conflict
                        // waiting to happen on a second laptop.
                        store.busy = false;
                        store.tasksText = fresh;
                        store.reparse();
                        store.refreshed();
                        return;
                    }
                    // How many tasks the dashboard just put a date on:
                    // exactly those that were done but undated before.
                    store.stampedCount = Parse.readTasks(fresh, store.config)
                        .filter((t) => t.done && !t.doneDate).length;
                }

                if (r.text === fresh) {
                    store.busy = false;
                    store.tasksText = fresh;
                    store.reparse();
                    store.refreshed();
                    return;
                }

                store.busy = false;
                store.enqueueWrite(store.tasksPath, r.text);
            }
        }
    }

    function run(op, args) {
        if (busy) { error = "busy -- one write at a time"; return; }
        busy = true;
        error = "";
        rmw.op = op;
        rmw.args = args ?? ({});
        rmw.running = false;
        rmw.running = true;
    }

    function tick(raw)            { run("tick", { raw: raw }); }
    function untick(raw)          { run("untick", { raw: raw }); }
    function cancel(raw)          { run("cancel", { raw: raw }); }
    function uncancel(raw)        { run("uncancel", { raw: raw }); }
    function remove(raw)          { run("delete", { raw: raw }); }
    function edit(raw, fields)    { run("edit", { raw: raw, fields: fields }); }
    function add(fields)          { run("add", { fields: fields }); }
    function stamp()              { run("stamp", {}); }
    function migrate()            { run("migrate", {}); }
    function renameCategory(a, b) { run("rename", { from: a, to: b }); }

    // Save the settings view's config, rewriting any renamed category's
    // tag throughout tasks.md in the same operation.
    //   renames: [{ from: "job", to: "work" }, ...]
    function applyConfig(cfg, renames) {
        if (!renames || renames.length === 0) {
            enqueueWrite(configPath, Parse.writeConfig(configText, cfg));
            return;
        }
        run("applyConfig", { cfg: cfg, renames: renames });
    }

    // ---- startup -------------------------------------------------------

    // Opening the dashboard is a click on this machine, so stamping
    // here stays inside the "only write in response to a click" rule.
    // It is also the earliest honest moment to date a task ticked on the
    // phone, where nothing writes a date at all.
    Component.onCompleted: {
        conflictScan.running = true;
        reload();
    }

    // Startup chores, one per refresh so each gets a clean read of the
    // file rather than racing the other's write.
    //   1. convert any leftover #category markers to @category
    //   2. date anything ticked on the phone
    property bool migratedOnce: false
    property bool stampedOnce: false

    onRefreshed: {
        if (!loaded || busy) return;

        if (!migratedOnce) {
            migratedOnce = true;
            if (Parse.needsTagMigration(tasksText, config)) { migrate(); return; }
        }
        if (!stampedOnce) {
            stampedOnce = true;
            if (needsStamp) stamp();
        }
    }
}
