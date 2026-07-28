pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Quickshell IS the notification daemon here: NotificationServer
// implements org.freedesktop.Notifications on DBus. dunst/mako must
// not be running -- only one process can own the name.
//
// This singleton owns the server, arrival timestamps (the protocol has
// none), and which notifications are currently showing as toasts.
Singleton {
    id: notifs

    readonly property var server: notifServer
    readonly property var all: notifServer.trackedNotifications.values

    // notification id -> arrival Date.now()
    property var times: ({})
    // ids currently visible as toast popups
    property var popupIds: []
    // bumped every 30s so "Xm ago" labels re-evaluate
    property int tick: 0

    readonly property var popupList:
        all.filter((n) => popupIds.indexOf(n.id) !== -1)

    NotificationServer {
        id: notifServer
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => {
            n.tracked = true;
            const t = Object.assign({}, notifs.times);
            t[n.id] = Date.now();
            notifs.times = t;
            // Cap simultaneous toasts; oldest folds away first.
            notifs.popupIds = notifs.popupIds.concat([n.id]).slice(-4);
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: notifs.tick += 1
    }

    function hidePopup(id) {
        popupIds = popupIds.filter((x) => x !== id);
    }

    function dismiss(n) {
        hidePopup(n.id);
        n.dismiss();
    }

    function dismissAll() {
        popupIds = [];
        // Iterate a copy: dismissing mutates the tracked list.
        for (const n of all.slice()) n.dismiss();
    }

    function timeAgo(id) {
        void tick; // dependency so labels refresh
        const t = times[id];
        if (t === undefined) return "";
        const s = Math.round((Date.now() - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        return Math.floor(s / 86400) + "d ago";
    }
}
