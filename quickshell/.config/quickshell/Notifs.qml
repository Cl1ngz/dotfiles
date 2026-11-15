pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Quickshell IS the notification daemon here: NotificationServer
// implements org.freedesktop.Notifications on DBus. dunst/mako must
// not be running -- only one process can own the name.
//
// History is kept in a file, not in memory, so it survives a bar
// restart, a matugen hot-reload, and a reboot. Entries are ONLY removed
// when you delete them: nothing expires, nothing is trimmed on start.
//
// The file is under the state dir, not /tmp: /tmp is tmpfs here and
// would be wiped on every boot, which is the opposite of the point.
Singleton {
    id: notifs

    // ---- history filtering -------------------------------------------
    //
    // Two layers, and they behave differently on purpose:
    //
    //   ignored       apps YOU silenced from the centre with "ignore".
    //                 Exact app name. Absolute: nothing from them is
    //                 kept, critical or not -- you asked for that.
    //
    //   noHistoryApps built-in defaults, matched as substrings, with the
    //                 keepAnyway escape hatch and a critical exception.
    //
    // Both still SHOW as toasts. Ignoring is about what is kept, never
    // about what you are allowed to see.

    // App names, lowercased. Persisted with the history.
    property var ignored: []

    readonly property var noHistoryApps: ["blueman", "networkmanager", "mullvad", "spotify"]

    // Consulted only for an app already filtered by noHistoryApps: a VPN
    // dropping out is recorded while its routine connect chatter is not.
    readonly property var keepAnyway: ["unsecure", "disconnected"]

    readonly property string storeDir: Quickshell.statePath("")
    readonly property string storeFile: Quickshell.statePath("notifications.json")

    readonly property var server: notifServer
    readonly property var live: notifServer.trackedNotifications.values

    // Persisted history, newest last. Each record:
    //   { key, id, appName, appIcon, summary, body, urgency, time, count }
    // key is a monotonic local id: dbus ids get reused across restarts,
    // so they cannot identify a stored entry on their own. count is how
    // many identical messages this entry stands for.
    property var records: []
    property int nextKey: 1
    property bool loaded: false

    // ids currently visible as toast popups (live only, never persisted)
    property var popupIds: []
    property var toastCounts: ({})   // notification id -> repeats while shown
    // bumped every 30s so "Xm ago" labels re-evaluate
    property int tick: 0

    readonly property var popupList: live.filter((n) => popupIds.indexOf(n.id) !== -1)

    // ---- identity ----------------------------------------------------

    function appKey(name) {
        return (name ?? "").trim().toLowerCase();
    }

    // Two notifications are "the same message" when app, summary and
    // body all match. That, not the dbus id, is what stacks: a script
    // that fires the same text twice gets a new id each time.
    function msgKey(app, summary, body) {
        return appKey(app) + "\u0001" + (summary ?? "") + "\u0001" + (body ?? "");
    }

    function isIgnored(name) {
        return ignored.indexOf(appKey(name)) !== -1;
    }

    // ---- which script sent it ------------------------------------------
    //
    // Every script that calls plain notify-send arrives as the app
    // "notify-send", so ignoring one script ignored all of them.
    // libnotify (0.7.12+) adds a "sender-pid" hint: the pid of the
    // notify-send process. Its parent is the script, and the script's
    // path is in the parent's command line, e.g.
    //     bash /home/cl1ngz/Scripts/swall.sh /path/to/wall.png
    // The basename ("swall.sh") becomes the app name everywhere: the
    // centre, the toast, the stacking, and ignore. A script that passes
    // -a keeps the name it gave.
    //
    // The read has to happen while the notification is being delivered:
    // notify-send blocks until the server answers, so it -- and the
    // script waiting on it -- are only guaranteed to exist during
    // onNotification. Hence a blocking read; on /proc it is microseconds.

    // Names that say nothing about who sent it. Never ignorable.
    readonly property var genericApps: ["notify-send", ""]

    // live notification id -> app name resolved from its sender
    property var sourceNames: ({})

    // The name to show and match for a live notification.
    function appNameOf(n) {
        return sourceNames[n.id] ?? n.appName ?? "";
    }

    function canIgnore(key) {
        return key !== "unknown" && genericApps.indexOf(key) === -1;
    }

    Component {
        id: procFile

        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    // A fresh FileView per read: reusing one would hand back the cached
    // text whenever a pid (and so the path) repeats.
    function readProc(path) {
        const f = procFile.createObject(notifs, { "path": path });
        if (f === null)
            return "";
        const t = f.text() ?? "";
        f.destroy();
        return t;
    }

    // "" when the sender is not a script or cannot be found (someone
    // typed notify-send in a terminal, or it was backgrounded and the
    // script already exited).
    function resolveSource(n) {
        if (genericApps.indexOf(appKey(n.appName)) === -1)
            return "";
        const hints = n.hints ?? {};
        const pid = Number(hints["sender-pid"] ?? 0);
        if (!(pid > 1))
            return "";
        const st = /^PPid:\s*(\d+)/m.exec(readProc("/proc/" + pid + "/status"));
        const ppid = st ? Number(st[1]) : 0;
        if (!(ppid > 1))
            return "";
        const argv = readProc("/proc/" + ppid + "/cmdline")
            .split("\u0000")
            .filter((a) => a !== "");
        return scriptName(argv);
    }

    // Picks the script out of an interpreter's command line.
    function scriptName(argv) {
        const base = (p) => p.replace(/["']/g, "").slice(p.replace(/["']/g, "").lastIndexOf("/") + 1);
        if (argv.length === 0)
            return "";
        const prog = base(argv[0]).replace(/^-/, "");
        const interpreter = /^(sh|bash|zsh|dash|ksh|mksh|fish|python[0-9.]*|perl|ruby|node|lua[0-9.]*)$/.test(prog);

        // A real program (a compiled tool, a daemon): its own name.
        if (!interpreter)
            return ["systemd", "init"].indexOf(prog) === -1 ? prog : "";

        for (let i = 1; i < argv.length; i++) {
            const a = argv[i];
            // sh -c "~/Scripts/zoom toggle": name the first word if it
            // is a path; an inline one-liner has no name to give.
            if (a === "-c") {
                const first = (argv[i + 1] ?? "").trim().split(/\s+/)[0] ?? "";
                return first.indexOf("/") !== -1 ? base(first) : "";
            }
            if (a === "-m")
                return argv[i + 1] ?? "";   // python -m module
            if (a === "-o" || a === "-O" || a === "+o" || a === "+O") {
                i++;                         // option that takes a value
                continue;
            }
            if (a.startsWith("-") || a.startsWith("+"))
                continue;
            return base(a);
        }
        // Only flags, or nothing: an interactive shell, i.e. a person.
        return "";
    }

    function shouldKeep(n, appName) {
        const app = appKey(appName);

        if (app !== "" && ignored.indexOf(app) !== -1)
            return false;

        // Critical notifications are kept even from the built-in list:
        // a critical message is by definition one worth finding later.
        if (n.urgency === NotificationUrgency.Critical)
            return true;

        // The freedesktop "transient" hint means "do not persist" --
        // status blips set it (and so do your own scripts, with -e).
        if (n.transient === true)
            return false;

        if (app === "")
            return true;

        if (!noHistoryApps.some((skip) => app.indexOf(skip) !== -1))
            return true;

        const text = ((n.summary ?? "") + " " + (n.body ?? "")).toLowerCase();
        return keepAnyway.some((word) => text.indexOf(word) !== -1);
    }

    function urgencyName(n) {
        return n.urgency === NotificationUrgency.Critical ? "critical"
             : n.urgency === NotificationUrgency.Low ? "low" : "normal";
    }

    // ---- recording -----------------------------------------------------

    // An identical message does not get a second row. The existing entry
    // takes the new time, the new dbus id (so its action buttons point
    // at the notification that is actually still alive), count + 1, and
    // moves to the newest position.
    function record(n, appName) {
        const k = msgKey(appName, n.summary, n.body);
        const idx = records.findIndex((r) => msgKey(r.appName, r.summary, r.body) === k);

        if (idx !== -1) {
            const prev = records[idx];
            const merged = Object.assign({}, prev, {
                "id": n.id,
                "appIcon": (n.appIcon ?? "") !== "" ? n.appIcon : prev.appIcon,
                "urgency": urgencyName(n),
                "time": Date.now(),
                "count": (prev.count ?? 1) + 1
            });
            records = records.slice(0, idx).concat(records.slice(idx + 1), [merged]);
        } else {
            records = records.concat([{
                "key": nextKey,
                "id": n.id,
                "appName": appName,
                "appIcon": n.appIcon ?? "",
                "summary": n.summary ?? "",
                "body": n.body ?? "",
                "urgency": urgencyName(n),
                "time": Date.now(),
                "count": 1
            }]);
            nextKey += 1;
        }
        save();
    }

    // How many times the message on toast `id` repeated while its toast
    // was up. A burst count, not the history total: a toast saying x37
    // because the same line came 37 times last week would read as 37
    // just now.
    function toastCount(id) {
        return toastCounts[id] ?? 1;
    }

    // ---- grouping, for the centre ---------------------------------------
    //
    // Groups by app, newest group first, newest entry first inside each.
    // Derived from records every time they change; the centre never
    // keeps a second copy that could disagree with the file.
    readonly property var groups: {
        const byApp = {};
        const order = [];
        for (let i = records.length - 1; i >= 0; i--) {
            const r = records[i];
            const k = appKey(r.appName) || "unknown";
            let g = byApp[k];
            if (!g) {
                g = {
                    "key": k,
                    "appName": r.appName || "unknown",
                    "appIcon": r.appIcon ?? "",
                    "latest": r.time,
                    "items": [],
                    "total": 0,
                    "critical": false
                };
                byApp[k] = g;
                order.push(g);
            }
            g.items.push(r);
            g.total += (r.count ?? 1);
            if (r.urgency === "critical")
                g.critical = true;
            if (g.appIcon === "" && (r.appIcon ?? "") !== "")
                g.appIcon = r.appIcon;
        }
        return order;
    }

    // ---- actions ---------------------------------------------------------

    function hidePopup(id) {
        popupIds = popupIds.filter((x) => x !== id);
        releaseQueue = releaseQueue.concat([id]);
        releaseTimer.restart();
    }

    // A toast that was never kept (ignored app, transient, filtered)
    // has nothing left to show once it hides, but the server holds it
    // until someone closes it -- with a few chatty apps that is a slow
    // leak for as long as the bar runs. Release it after the collapse
    // animation (closing it at once would yank the toast mid-slide).
    // Kept ones stay alive so their action buttons work from the centre.
    property var releaseQueue: []

    Timer {
        id: releaseTimer

        interval: 400
        onTriggered: {
            const ids = notifs.releaseQueue;
            notifs.releaseQueue = [];
            for (const id of ids) {
                if (notifs.popupIds.indexOf(id) !== -1)
                    continue;
                if (notifs.records.some((r) => r.id === id))
                    continue;
                const n = notifs.live.find((x) => x.id === id);
                if (n !== undefined)
                    n.expire();
            }
        }
    }

    // Toast dismissal: drop the popup and release the live notification,
    // but KEEP the stored record -- history is only cleared by hand.
    function dismiss(n) {
        hidePopup(n.id);
        n.dismiss();
    }

    // Centre deletion: remove the stored record for good.
    function forget(rec) {
        records = records.filter((r) => r.key !== rec.key);
        save();
        const n = live.find((x) => x.id === rec.id);
        if (n !== undefined) {
            hidePopup(n.id);
            n.dismiss();
        }
    }

    // Everything from one app, without silencing it.
    function forgetApp(key) {
        records = records.filter((r) => (appKey(r.appName) || "unknown") !== key);
        save();
        for (const n of live.slice())
            if ((appKey(appNameOf(n)) || "unknown") === key) {
                hidePopup(n.id);
                n.dismiss();
            }
    }

    function forgetAll() {
        records = [];
        save();
        popupIds = [];
        for (const n of live.slice())
            n.dismiss();
    }

    // Stop keeping an app's notifications, and clear the ones already
    // kept -- "ignore this program" should leave nothing of it behind.
    // Toasts from it keep appearing.
    function ignoreApp(name) {
        const k = appKey(name);
        if (!canIgnore(k) || ignored.indexOf(k) !== -1)
            return;
        ignored = ignored.concat([k]).sort();
        records = records.filter((r) => appKey(r.appName) !== k);
        save();
    }

    // Only affects what happens from now on: entries removed by the
    // ignore are gone.
    function unignoreApp(key) {
        ignored = ignored.filter((x) => x !== key);
        save();
    }

    // Live object for a record, if it still exists (actions need it).
    function liveFor(rec) {
        return live.find((x) => x.id === rec.id) ?? null;
    }

    function timeAgo(ms) {
        void tick; // dependency so labels refresh
        if (!ms)
            return "";
        const s = Math.round((Date.now() - ms) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m ago";
        if (s < 86400)
            return Math.floor(s / 3600) + "h ago";
        const d = Math.floor(s / 86400);
        return d < 7 ? d + "d ago" : Qt.formatDateTime(new Date(ms), "d MMM");
    }

    // ---- server ------------------------------------------------------------

    NotificationServer {
        id: notifServer

        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => {
            n.tracked = true;

            // Re-sent after a config reload (keepOnReload): it was
            // recorded and shown the first time. Recording it again
            // would add +1 to its stack on every reload.
            if (n.lastGeneration)
                return;

            // Name it after the script that sent it, if it came from
            // plain notify-send. Entries for closed notifications are
            // dropped on the way so the map does not grow forever.
            const src = notifs.resolveSource(n);
            const names = {};
            for (const x of notifs.live)
                if (notifs.sourceNames[x.id] !== undefined)
                    names[x.id] = notifs.sourceNames[x.id];
            if (src !== "")
                names[n.id] = src;
            notifs.sourceNames = names;

            const app = notifs.appNameOf(n);
            if (notifs.shouldKeep(n, app))
                notifs.record(n, app);

            // One toast per message. An identical toast already on
            // screen is replaced by this one rather than stacked under
            // it; the "x2" on the new one says it happened again. The
            // old live object is released, or repeats would pile up in
            // memory for as long as the bar runs.
            const k = notifs.msgKey(app, n.summary, n.body);
            const dups = notifs.live.filter((x) => x.id !== n.id
                && notifs.msgKey(notifs.appNameOf(x), x.summary, x.body) === k);
            const dupIds = dups.map((x) => x.id);

            // Carry the count over only from a copy still on screen; once
            // its toast has gone, the next one starts again at 1.
            let burst = 1;
            for (const id of dupIds)
                if (notifs.popupIds.indexOf(id) !== -1)
                    burst = Math.max(burst, notifs.toastCount(id) + 1);

            // Cap simultaneous toasts; oldest folds away first.
            const ids = notifs.popupIds
                .filter((id) => dupIds.indexOf(id) === -1)
                .concat([n.id])
                .slice(-4);
            const counts = {};
            for (const id of ids)
                if (id === n.id)
                    counts[id] = burst;
                else if (notifs.toastCounts[id] !== undefined)
                    counts[id] = notifs.toastCounts[id];
            notifs.toastCounts = counts;
            // Toasts pushed out by the cap go through the same release
            // as ones that time out.
            const pushedOut = notifs.popupIds.filter((id) => ids.indexOf(id) === -1
                && dupIds.indexOf(id) === -1);
            notifs.popupIds = ids;
            if (pushedOut.length > 0) {
                notifs.releaseQueue = notifs.releaseQueue.concat(pushedOut);
                releaseTimer.restart();
            }

            for (const d of dups)
                d.dismiss();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: notifs.tick += 1
    }

    // ---- persistence -----------------------------------------------------
    //
    // File format: { "version": 2, "records": [...], "ignored": [...] }.
    // The old format was a bare array of records; it is still read, so
    // the history you have survives the upgrade and is rewritten in the
    // new shape on the first save.

    Process {
        id: storeLoad

        running: true
        command: ["sh", "-c", "cat '" + notifs.storeFile + "' 2>/dev/null || true"]

        stdout: StdioCollector {
            onStreamFinished: {
                let recs = [];
                let ign = [];
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) {
                        recs = parsed;
                    } else if (parsed && typeof parsed === "object") {
                        if (Array.isArray(parsed.records))
                            recs = parsed.records;
                        // "notify-send" is dropped: it stood for every
                        // script, and scripts are now told apart.
                        if (Array.isArray(parsed.ignored))
                            ign = parsed.ignored
                                .map((x) => ("" + x).toLowerCase())
                                .filter((x) => notifs.canIgnore(x));
                    }
                } catch (e) {
                    // Corrupt or empty file: start clean rather than
                    // losing the ability to log new ones.
                    recs = [];
                    ign = [];
                }

                for (const r of recs)
                    if (r.count === undefined)
                        r.count = 1;

                notifs.records = recs;
                notifs.ignored = ign;
                let maxKey = 0;
                for (const r of recs)
                    if (r.key > maxKey)
                        maxKey = r.key;
                notifs.nextKey = maxKey + 1;
                notifs.loaded = true;
            }
        }
    }

    // The JSON goes in over stdin, not as an argument. Linux caps a
    // single argv string at 128 KiB (MAX_ARG_STRLEN), and this history is
    // never trimmed -- a few hundred kept notifications in, an argv
    // write would start failing with E2BIG and history would silently
    // stop being saved. Temp file + rename, so a crash mid-write leaves
    // the previous file intact instead of a truncated one.
    //
    // The method is `put`, not `write`: Process already has a write()
    // (that is what sends stdin), and shadowing it is how you end up
    // calling yourself.
    Process {
        id: storeSave

        property var pending: null

        function put(json) {
            // A write is already running: queue instead of killing it
            // mid-write. Only the newest state matters, so a queued
            // write is simply replaced.
            if (running) {
                pending = json;
                return;
            }
            command = ["sh", "-c",
                'mkdir -p "$1" || exit 1; ' +
                't=$(mktemp "$1/.notifications.XXXXXX") || exit 1; ' +
                'trap \'rm -f "$t"\' EXIT; ' +
                'cat > "$t" && mv -f "$t" "$2" && trap - EXIT',
                "sh", notifs.storeDir, notifs.storeFile];
            stdinEnabled = true;
            running = true;
            write(json);
            // Closing stdin is the EOF that lets `cat` finish.
            stdinEnabled = false;
        }

        onExited: {
            if (pending !== null) {
                const next = pending;
                pending = null;
                put(next);
            }
        }
    }

    function save() {
        // Don't clobber the file with an empty list before the initial
        // load has finished.
        if (!loaded)
            return;
        storeSave.put(JSON.stringify({
            "version": 2,
            "records": records,
            "ignored": ignored
        }));
    }
}
