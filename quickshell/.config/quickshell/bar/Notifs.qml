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
// Note the file is under the state dir, not /tmp: /tmp is tmpfs here
// and would be wiped on every boot, which is the opposite of the point.
Singleton {
    id: notifs

    // ---- history filtering -------------------------------------------
    // Apps whose notifications are worth SEEING but not worth KEEPING:
    // bluetooth connect/disconnect spam, volume/brightness popups from
    // other tools, and so on. Matched case-insensitively as a substring
    // of the app name, so "blueman" also catches "blueman-applet".
    // These still appear as toasts; they just never reach the center.
    readonly property var noHistoryApps: [
        "blueman",
        "networkmanager",
        "spotify"      // now-playing spam; drop this line to keep them
    ]

    // Critical notifications are always kept, even from the apps above:
    // a critical message is by definition one worth finding later.
    function shouldKeep(n) {
        if (n.urgency === NotificationUrgency.Critical) return true;
        // The freedesktop "transient" hint means "do not persist" -- most
        // status-blip notifications set it, so honour it directly.
        if (n.transient === true) return false;
        const app = (n.appName ?? "").toLowerCase();
        if (app === "") return true;
        return !noHistoryApps.some((skip) => app.indexOf(skip) !== -1);
    }

    readonly property string storeDir: Quickshell.statePath("")
    readonly property string storeFile: Quickshell.statePath("notifications.json")

    readonly property var server: notifServer
    readonly property var live: notifServer.trackedNotifications.values

    // Persisted history, newest last. Each record:
    //   { key, id, appName, appIcon, summary, body, urgency, time }
    // key is a monotonic local id: dbus ids get reused across restarts,
    // so they cannot identify a stored entry on their own.
    property var records: []
    property int nextKey: 1
    property bool loaded: false

    // ids currently visible as toast popups (live only, never persisted)
    property var popupIds: []
    // bumped every 30s so "Xm ago" labels re-evaluate
    property int tick: 0

    readonly property var popupList:
        live.filter((n) => popupIds.indexOf(n.id) !== -1)

    NotificationServer {
        id: notifServer
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => {
            n.tracked = true;

            if (notifs.shouldKeep(n)) notifs.record(n);

            // Cap simultaneous toasts; oldest folds away first.
            notifs.popupIds = notifs.popupIds.concat([n.id]).slice(-4);
        }
    }

    function record(n) {
            const rec = {
                key: notifs.nextKey,
                id: n.id,
                appName: n.appName ?? "",
                appIcon: n.appIcon ?? "",
                summary: n.summary ?? "",
                body: n.body ?? "",
                urgency: n.urgency === NotificationUrgency.Critical ? "critical"
                       : n.urgency === NotificationUrgency.Low ? "low" : "normal",
                time: Date.now()
            };
            notifs.nextKey += 1;
            notifs.records = notifs.records.concat([rec]);
            notifs.save();
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: notifs.tick += 1
    }

    // ---- persistence -------------------------------------------------

    Process {
        id: storeLoad
        running: true
        command: ["sh", "-c", "cat '" + notifs.storeFile + "' 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                let recs = [];
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) recs = parsed;
                } catch (e) {
                    // Corrupt or empty file: start clean rather than
                    // throwing away the ability to log new ones.
                    recs = [];
                }
                notifs.records = recs;
                let maxKey = 0;
                for (const r of recs) if (r.key > maxKey) maxKey = r.key;
                notifs.nextKey = maxKey + 1;
                notifs.loaded = true;
            }
        }
    }

    Process {
        id: storeSave
        property var pending: null

        function write(json) {
            // A write is already running: queue instead of killing it
            // mid-write, which would truncate the history file.
            if (running) { pending = json; return; }
            command = ["sh", "-c",
                'mkdir -p "$1" && printf %s "$2" > "$3"', "sh",
                notifs.storeDir, json, notifs.storeFile];
            running = true;
        }

        onExited: {
            if (pending !== null) {
                const next = pending;
                pending = null;
                write(next);
            }
        }
    }

    function save() {
        // Don't clobber the file with an empty list before the initial
        // load has finished.
        if (!loaded) return;
        storeSave.write(JSON.stringify(records));
    }

    // ---- actions -----------------------------------------------------

    function hidePopup(id) {
        popupIds = popupIds.filter((x) => x !== id);
    }

    // Toast dismissal: drop the popup and release the live notification,
    // but KEEP the stored record -- history is only cleared by hand.
    function dismiss(n) {
        hidePopup(n.id);
        n.dismiss();
    }

    // Center deletion: remove the stored record for good.
    function forget(rec) {
        records = records.filter((r) => r.key !== rec.key);
        save();
        const n = live.find((x) => x.id === rec.id);
        if (n !== undefined) { hidePopup(n.id); n.dismiss(); }
    }

    function forgetAll() {
        records = [];
        save();
        popupIds = [];
        for (const n of live.slice()) n.dismiss();
    }

    // Live object for a record, if it still exists (actions need it).
    function liveFor(rec) {
        return live.find((x) => x.id === rec.id) ?? null;
    }

    function timeAgo(ms) {
        void tick; // dependency so labels refresh
        if (!ms) return "";
        const s = Math.round((Date.now() - ms) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        const d = Math.floor(s / 86400);
        return d < 7 ? d + "d ago" : Qt.formatDateTime(new Date(ms), "d MMM");
    }
}
