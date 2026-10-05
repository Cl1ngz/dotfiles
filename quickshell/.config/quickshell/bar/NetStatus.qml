import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Network pill + panel on NetworkManager (nmcli).
//
// Page 1: radio/networking switches, connected devices with IP info,
// wifi list (connect / disconnect / inline password), VPN toggles.
// Page 2: a full connection editor (GENERAL / WI-FI / SECURITY / IPV4 /
// IPV6) built on `nmcli con mod` -- loads current values, saves only
// what changed, and re-activates the connection to apply.
Pill {
    id: netPill

    // ---- state -------------------------------------------------------
    property bool wifiEnabled: true
    property bool networkingEnabled: true
    property var devices: []
    property var devInfo: ({})
    property var wifiNetworks: []
    property var savedNames: []
    property var vpns: []
    property string expandedSsid: ""
    property string busyText: ""

    // Last nmcli failure, verbatim. Every action went through a Process
    // with no stdout/stderr attached, so a refused connection produced
    // exactly nothing on screen -- the pill just stopped saying
    // "connecting". nmcli's own message is the useful diagnostic
    // ("Secrets were required but not provided", "Not authorized to
    // control networking"), so it is shown as-is rather than replaced
    // with a generic failure line.
    property string errText: ""
    // Set when the error looks like a missing polkit agent, which no
    // amount of retrying fixes.
    property bool errIsAuth: false

    // Password reveal, shared by the network list and the editor's
    // SECURITY tab.
    property string revealSsid: ""
    property string revealPsk: ""
    property string revealNote: ""
    property bool revealCanRoot: false
    // Raw facts from the last reveal attempt, for the copy button.
    property string revealDiag: ""

    // editor state
    property string editName: ""
    property string editType: ""       // wifi | ethernet | other
    property bool editWasActive: false
    property int editTab: 0
    property var origValues: ({})
    property var editValues: ({})
    // The connection's current secret, and the box showing it. They
    // start equal; a save happens only if the box has been changed.
    property string curSecret: ""
    property string pwField: ""
    property bool pwShow: false
    property string secretNote: ""
    property string secretKey: ""   // e.g. 802-1x.password

    readonly property var activeDevs: devices.filter(
        (d) => d.state === "connected" && (d.type === "wifi" || d.type === "ethernet"))
    readonly property var connectedWifi: wifiNetworks.find((n) => n.inUse) ?? null

    function terseSplit(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === '\\' && i + 1 < line.length) { cur += line[i + 1]; i++; continue; }
            if (c === ':') { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function signalIcon(sig) {
        if (sig >= 75) return "󰤨";
        if (sig >= 50) return "󰤥";
        if (sig >= 25) return "󰤢";
        return "󰤟";
    }

    // ---- editor schema -----------------------------------------------
    // type: text | bool | choice. Bool values are nmcli yes/no strings.
    readonly property var editSchema: [
        { name: "GENERAL", fields: [
            { key: "connection.autoconnect", label: "autoconnect", type: "bool" },
            { key: "connection.autoconnect-priority", label: "priority", type: "text", hint: "0" },
            { key: "connection.metered", label: "metered", type: "choice", options: ["unknown", "yes", "no"] }
        ]},
        { name: "WI-FI", wifiOnly: true, fields: [
            { key: "802-11-wireless.bssid", label: "bssid pin", type: "text", hint: "AA:BB:CC:DD:EE:FF" },
            { key: "802-11-wireless.band", label: "band", type: "choice", options: ["", "a", "bg"] },
            { key: "802-11-wireless.cloned-mac-address", label: "cloned mac", type: "text", hint: "random | stable | MAC" },
            { key: "802-11-wireless.mtu", label: "mtu", type: "text", hint: "auto" },
            { key: "802-11-wireless.hidden", label: "hidden net", type: "bool" }
        ]},
        // Two different connections wear this tab. A home network has a
        // PSK and nothing else; an 802.1X network (eduroam, corporate)
        // has no PSK at all and instead needs an identity, an EAP
        // method and an inner auth. Showing a "NEW PSK" box for the
        // second kind is just a field that cannot do anything.
        // eapOnly/pskOnly pick which rows apply, from key-mgmt.
        { name: "SECURITY", wifiOnly: true, fields: [
            { key: "802-1x.eap", label: "eap method", type: "choice", eapOnly: true,
              options: ["peap", "ttls", "tls", "pwd", "leap"] },
            { key: "802-1x.identity", label: "identity", type: "text", eapOnly: true,
              hint: "user@uni.edu.pl" },
            { key: "802-1x.anonymous-identity", label: "anon identity", type: "text",
              eapOnly: true, hint: "optional outer identity" },
            { key: "802-1x.phase2-auth", label: "inner auth", type: "choice", eapOnly: true,
              options: ["mschapv2", "pap", "gtc", "md5", "chap"] },
            { key: "802-1x.ca-cert", label: "ca cert", type: "text", eapOnly: true,
              hint: "path to the CA .pem" },
            { key: "802-1x.domain-suffix-match", label: "domain match", type: "text",
              eapOnly: true, hint: "RADIUS server domain" },
            // nmcli reports and accepts pmf as a number, so the options
            // are numbers and the labels are for reading.
            { key: "802-11-wireless-security.pmf", label: "pmf", type: "choice",
              options: ["0", "1", "2", "3"],
              valueLabels: ({ "": "(default)", "0": "default", "1": "disable",
                              "2": "optional", "3": "required" }) },
            // Loaded and saved like any other key, but drawn by the
            // button in the SECURITY body rather than a generic row.
            { key: "802-1x.password-flags", label: "pw flags", type: "text",
              eapOnly: true, hidden: true },
            { key: "802-11-wireless-security.psk-flags", label: "psk flags",
              type: "text", pskOnly: true, hidden: true }
        ]},
        { name: "IPV4", fields: [
            { key: "ipv4.method", label: "method", type: "choice", options: ["auto", "manual", "link-local", "shared"] },
            { key: "ipv4.addresses", label: "addresses", type: "text", hint: "192.168.1.50/24" },
            { key: "ipv4.gateway", label: "gateway", type: "text", hint: "192.168.1.1" },
            { key: "ipv4.dns", label: "dns", type: "text", hint: "1.1.1.1,9.9.9.9" },
            { key: "ipv4.ignore-auto-dns", label: "ignore auto dns", type: "bool" },
            { key: "ipv4.never-default", label: "never default rt", type: "bool" }
        ]},
        { name: "IPV6", fields: [
            { key: "ipv6.method", label: "method", type: "choice", options: ["auto", "dhcp", "manual", "disabled", "link-local"] },
            { key: "ipv6.addresses", label: "addresses", type: "text", hint: "2001:db8::5/64" },
            { key: "ipv6.gateway", label: "gateway", type: "text", hint: "" },
            { key: "ipv6.dns", label: "dns", type: "text", hint: "" }
        ]}
    ]
    readonly property var editTabs: editSchema.filter((t) => !t.wifiOnly || editType === "wifi")
    readonly property var editKeys: {
        const ks = [];
        for (const t of editSchema) for (const f of t.fields) ks.push(f.key);
        return ks;
    }

    // key-mgmt of the open connection: wpa-psk, sae (WPA3), wpa-eap,
    // owe, none. Drives which SECURITY rows are shown.
    property string editKeyMgmt: ""
    readonly property bool editIsEap:
        editKeyMgmt === "wpa-eap" || editKeyMgmt === "wpa-eap-suite-b-192"

    function visibleFields(tab) {
        const fs = (tab ?? ({ fields: [] })).fields ?? [];
        return fs.filter((f) => f.hidden !== true
                             && (f.eapOnly !== true || editIsEap)
                             && (f.pskOnly !== true || !editIsEap));
    }

    function openEditor(name) {
        editName = name;
        editTab = 0;
        origValues = ({});
        editValues = ({});
        editKeyMgmt = "";
        curSecret = "";
        pwField = "";
        pwShow = false;
        secretNote = "";
        secretKey = "";
        revealPsk = "";
        revealNote = "";
        revealCanRoot = false;
        editLoad.load(name);
    }

    function setEditValue(key, value) {
        const v = Object.assign({}, editValues);
        v[key] = value;
        editValues = v;
    }

    // Join a network by BUILDING the profile, not by asking
    // NetworkManager to work the AP out for itself.
    //
    // `nmcli dev wifi connect <ssid> password <pw>` fails with "Failed
    // to determine AP security information" whenever it cannot read the
    // security of a matching AP out of its scan cache: a scan that has
    // gone stale, an AP that stopped beaconing for a moment, a hidden
    // SSID, or a band the card was not on during the last scan. The
    // password is irrelevant to that error -- it never got as far as
    // authenticating.
    //
    // The scan row already tells us the security ("WPA2", "WPA3",
    // "WPA2 802.1X", "WEP", ""), so key-mgmt can be stated outright and
    // the guesswork disappears. Only if `con add` itself fails do we
    // fall back to the old command.
    function joinWifi(ssid, pass, security, hidden) {
        const script =
            'ssid="$1"; pw="$2"; sec="$3"; hid="$4"; ' +
            'case "$sec" in ' +
            '  *SAE*|*WPA3*) km=sae ;; ' +
            '  *802.1X*|*802.1x*) km=eap ;; ' +
            '  *WPA*) km=wpa-psk ;; ' +
            '  *WEP*) km=wep ;; ' +
            '  *) km=open ;; ' +
            'esac; ' +
            // Bail out BEFORE the delete: an 802.1X network needs the
            // enterprise form (joinWifiEap), and deleting first would
            // throw away a working profile to achieve nothing.
            'if [ "$km" = eap ]; then ' +
            '  echo "802.1X network -- use the enterprise fields." >&2; exit 2; fi; ' +
            'nmcli con delete id "$ssid" >/dev/null 2>&1; ' +
            'set -- con add type wifi con-name "$ssid" ssid "$ssid"; ' +
            'if [ "$hid" = yes ]; then set -- "$@" 802-11-wireless.hidden yes; fi; ' +
            'case "$km" in ' +
            '  sae) set -- "$@" wifi-sec.key-mgmt sae wifi-sec.psk "$pw" ' +
            '       wifi-sec.psk-flags 0 ;; ' +
            '  wpa-psk) set -- "$@" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pw" ' +
            '       wifi-sec.psk-flags 0 ;; ' +
            '  wep) set -- "$@" wifi-sec.key-mgmt none wifi-sec.wep-key0 "$pw" ' +
            '       wifi-sec.wep-key-flags 0 ;; ' +
            'esac; ' +
            'if nmcli "$@" >/dev/null 2>&1; then exec nmcli con up id "$ssid"; fi; ' +
            // con add refused the profile: let nmcli try it its own way
            // so its message is the one that reaches the panel.
            'nmcli con delete id "$ssid" >/dev/null 2>&1; ' +
            'if [ "$km" = open ]; then exec nmcli dev wifi connect "$ssid"; fi; ' +
            'exec nmcli dev wifi connect "$ssid" password "$pw"';
        netAction.runSh(script, [ssid, pass, security ?? "", hidden ? "yes" : "no"],
                        "connecting");
    }

    // The enterprise counterpart. An 802.1X network has no shared key,
    // so there is nothing for `dev wifi connect ... password ...` to do:
    // the profile has to carry an EAP method, an identity and an inner
    // auth before it can associate. Built here rather than sending you
    // to nm-connection-editor for the one network type the panel could
    // not do itself.
    //
    // password-flags 0 keeps the password in the profile. Left at the
    // default it is agent-owned, NetworkManager asks a secret agent on
    // every connect, and with no agent running the connection silently
    // never comes up.
    function joinWifiEap(ssid, eap, identity, anon, phase2, pass, domain, caCert) {
        const script =
            'ssid="$1"; eap="$2"; ident="$3"; anon="$4"; ph2="$5"; ' +
            'pw="$6"; dom="$7"; ca="$8"; ' +
            'nmcli con delete id "$ssid" >/dev/null 2>&1; ' +
            'set -- con add type wifi con-name "$ssid" ssid "$ssid" ' +
            '  wifi-sec.key-mgmt wpa-eap ' +
            '  802-1x.eap "$eap" ' +
            '  802-1x.identity "$ident" ' +
            '  802-1x.password "$pw" ' +
            '  802-1x.password-flags 0; ' +
            'if [ -n "$anon" ]; then ' +
            '  set -- "$@" 802-1x.anonymous-identity "$anon"; fi; ' +
            'if [ -n "$dom" ]; then ' +
            '  set -- "$@" 802-1x.domain-suffix-match "$dom"; fi; ' +
            'if [ -n "$ca" ]; then set -- "$@" 802-1x.ca-cert "$ca"; fi; ' +
            // phase2 only exists for the tunnelled methods; setting it
            // on tls or pwd makes nmcli reject the whole profile.
            'case "$eap" in peap|ttls) ' +
            '  set -- "$@" 802-1x.phase2-auth "$ph2" ;; esac; ' +
            'nmcli "$@" >/dev/null || exit 1; ' +
            'exec nmcli con up id "$ssid"';
        netAction.runSh(script,
            [ssid, eap, identity, anon ?? "", phase2, pass, domain ?? "", caCert ?? ""],
            "connecting");
    }

    // Enterprise form state. Held here rather than in the delegate so a
    // list refresh (every 10s while the panel is open) cannot wipe what
    // is half-typed.
    property string eapMethod: "peap"
    property string eapPhase2: "mschapv2"
    property string eapIdentity: ""
    property string eapAnon: ""
    property string eapPassword: ""
    property string eapDomain: ""
    property string eapCa: ""
    property bool eapShowPw: false

    function resetEapForm() {
        eapMethod = "peap";
        eapPhase2 = "mschapv2";
        eapIdentity = "";
        eapAnon = "";
        eapPassword = "";
        eapDomain = "";
        eapCa = "";
        eapShowPw = false;
    }

    function saveEdit() {
        const args = ["nmcli", "con", "mod", editName];
        for (const k of editKeys) {
            if (editValues[k] !== undefined && editValues[k] !== origValues[k])
                args.push(k, editValues[k]);
        }
        // The password box holds the CURRENT secret, so it is written
        // only when it differs from what was loaded. secretKey is
        // whichever setting this connection actually uses:
        // 802-1x.password for enterprise, ...security.psk otherwise.
        if (pwField !== curSecret && secretKey !== "")
            args.push(secretKey, pwField);
        if (args.length === 4) { editName = ""; return; }   // nothing changed
        editSave.wasActive = editWasActive;
        editSave.conName = editName;
        busyText = "saving";
        editSave.command = args;
        editSave.running = true;
    }

    // ---- pill --------------------------------------------------------
    icon: {
        if (!networkingEnabled) return "󰖪";
        const eth = devices.find((d) => d.type === "ethernet" && d.state === "connected");
        if (eth !== undefined) return "󰈀";
        if (!wifiEnabled) return "󰖪";
        if (connectedWifi !== null) return signalIcon(connectedWifi.signal);
        return "󰖩";
    }
    label: connectedWifi !== null ? connectedWifi.ssid : ""
    toggleableLabel: true
    labelVisible: false
    tint: !networkingEnabled ? Colors.danger
        : activeDevs.length > 0 ? Colors.textMain
        : Colors.textFaint

    onClicked: (button) => {
        if (button === Qt.RightButton) {
            netAction.run(["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"], "wifi radio");
            return;
        }
        overlay.visible = !overlay.visible;
    }

    // ---- processes ---------------------------------------------------

    Process {
        id: refreshProcess
        command: ["sh", "-c",
            'nmcli radio wifi; nmcli networking; ' +
            'echo @@@; ' +
            'nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev; ' +
            'echo @@@; ' +
            'for d in $(nmcli -t -f DEVICE,TYPE,STATE dev | awk -F: \'$2~/^(ethernet|wifi)$/ && $3=="connected"{print $1}\'); do ' +
            'echo "DEV:$d"; nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show "$d" 2>/dev/null; done; ' +
            'echo @@@; ' +
            'nmcli -t -f SIGNAL,IN-USE,SECURITY,SSID dev wifi list 2>/dev/null; ' +
            'echo @@@; ' +
            'nmcli -t -f NAME,TYPE,ACTIVE con show | grep -E \':(vpn|wireguard):\' ; ' +
            'echo @@@; ' +
            'nmcli -t -f NAME con show']
        stdout: StdioCollector {
            onStreamFinished: netPill.parseRefresh(text)
        }
        function refresh() { running = false; running = true; }
    }

    function parseRefresh(text) {
        const sec = text.split('@@@');

        const radios = sec[0].trim().split('\n');
        wifiEnabled = (radios[0] ?? "").trim() === "enabled";
        networkingEnabled = (radios[1] ?? "").trim() === "enabled";

        const devs = [];
        for (const line of (sec[1] ?? "").trim().split('\n')) {
            if (line === "") continue;
            const p = terseSplit(line);
            if (p.length < 3 || p[1] === "loopback") continue;
            devs.push({ dev: p[0], type: p[1], state: p[2], connection: p.slice(3).join(":") });
        }
        devices = devs;

        const info = {};
        let cur = "";
        for (const line of (sec[2] ?? "").trim().split('\n')) {
            if (line.startsWith("DEV:")) {
                cur = line.substring(4);
                info[cur] = { ips: [], gateway: "", dns: [] };
                continue;
            }
            if (cur === "") continue;
            const ci = line.indexOf(':');
            if (ci === -1) continue;
            const key = line.substring(0, ci);
            const val = line.substring(ci + 1);
            if (key.startsWith("IP4.ADDRESS")) info[cur].ips.push(val);
            else if (key.startsWith("IP4.GATEWAY") && val !== "") info[cur].gateway = val;
            else if (key.startsWith("IP4.DNS")) info[cur].dns.push(val);
        }
        devInfo = info;

        const bySsid = {};
        for (const line of (sec[3] ?? "").trim().split('\n')) {
            if (line === "") continue;
            const p = terseSplit(line);
            if (p.length < 4) continue;
            const ssid = p.slice(3).join(":");
            if (ssid === "") continue;
            const entry = { signal: parseInt(p[0]) || 0, inUse: p[1] === "*", security: p[2], ssid: ssid };
            const prev = bySsid[ssid];
            if (prev === undefined || entry.inUse || entry.signal > prev.signal)
                bySsid[ssid] = Object.assign(entry, { inUse: entry.inUse || (prev?.inUse ?? false) });
        }
        wifiNetworks = Object.values(bySsid).sort(
            (a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));

        const vlist = [];
        for (const line of (sec[4] ?? "").trim().split('\n')) {
            if (line === "") continue;
            const p = terseSplit(line);
            if (p.length < 3) continue;
            vlist.push({ name: p[0], type: p[1], active: p[2] === "yes" });
        }
        vpns = vlist;

        savedNames = (sec[5] ?? "").trim().split('\n')
            .filter((l) => l !== "")
            .map((l) => terseSplit(l)[0]);
    }

    Process {
        id: netAction
        // nmcli writes failures to stderr and progress to stdout; keep
        // both, because `con up` reports "Error: Connection activation
        // failed" on stderr while `dev wifi connect` sometimes explains
        // itself on stdout.
        property string outBuf: ""
        property string errBuf: ""

        function run(cmd, label) {
            running = false;
            netPill.busyText = label;
            netPill.errText = "";
            netPill.errIsAuth = false;
            outBuf = "";
            errBuf = "";
            command = cmd;
            running = true;
        }
        function runSh(script, args, label) {
            run(["sh", "-c", script, "--"].concat(args), label);
        }

        stdout: StdioCollector { onStreamFinished: netAction.outBuf = text }
        stderr: StdioCollector { onStreamFinished: netAction.errBuf = text }

        onExited: (code) => {
            netPill.busyText = "";
            if (code !== 0) {
                // Last non-empty line: nmcli prefixes with "Error: " and
                // may precede it with progress chatter.
                const lines = (errBuf + "\n" + outBuf).split("\n")
                    .map((l) => l.trim()).filter((l) => l !== "");
                const msg = lines.length > 0
                    ? lines[lines.length - 1]
                    : "nmcli exited " + code + " with no message";
                netPill.errText = msg.replace(/^Error:\s*/, "");
                const low = msg.toLowerCase();
                netPill.errIsAuth = low.indexOf("not authorized") !== -1
                    || low.indexOf("insufficient privileges") !== -1
                    || low.indexOf("access denied") !== -1;
            }
            refreshProcess.refresh();
        }
    }

    // Reveal the saved key for one network.
    //
    // `nmcli -s -g 802-11-wireless-security.psk` is the documented way,
    // but it lies by omission in three separate situations, all of which
    // look identical from QML -- an empty string:
    //
    //   1. Reading secrets goes through polkit. With no agent answering,
    //      NetworkManager returns the field EMPTY rather than failing,
    //      so nmcli exits 0 with no output.
    //   2. psk-flags=1 (agent-owned) means the key is in the login
    //      keyring, not in the connection profile. NetworkManager never
    //      had it to give.
    //   3. The profile name is not always the SSID ("MyWifi 1", or a
    //      profile renamed by hand), so `con show <ssid>` was simply
    //      asking about a connection that does not exist.
    //
    // So this resolves the real profile name first, then tries nmcli,
    // then the keyfile directly, and finally reports psk-flags and
    // key-mgmt so the panel can say WHICH of the three it hit instead of
    // claiming there is no key.
    Process {
        id: revealLoad
        property string resolved: ""
        property string keyfile: ""

        function load(name) {
            running = false;
            netPill.revealSsid = name;
            netPill.revealPsk = "…";
            netPill.revealNote = "";
            netPill.revealCanRoot = false;
            resolved = "";
            keyfile = "";
            command = ["sh", "-c",
                'name="$1"; ' +
                // Profile named exactly after the SSID: the usual case.
                'if nmcli -g connection.id con show "$name" >/dev/null 2>&1; then ' +
                '  target="$name"; ' +
                'else ' +
                // Otherwise find the wifi profile whose ssid matches.
                '  target=$(nmcli -t -f NAME con show | sed "s/\\\\\\\\:/:/g" | ' +
                '    while IFS= read -r n; do ' +
                '      s=$(nmcli -g 802-11-wireless.ssid con show "$n" 2>/dev/null); ' +
                '      if [ "$s" = "$name" ]; then printf %s "$n"; break; fi; ' +
                '    done); ' +
                'fi; ' +
                'if [ -z "$target" ]; then echo "NOPROFILE"; exit 0; fi; ' +
                'printf "NAME:%s\\n" "$target"; ' +
                // stderr goes to a temp file instead of /dev/null: when
                // the secret comes back empty, nmcli's own complaint is
                // the only thing that says why, and discarding it was
                // the reason the note could only guess.
                'tmp=$(mktemp 2>/dev/null || echo /tmp/.qs-net-psk.$$); ' +
                'psk=$(nmcli -s -g 802-11-wireless-security.psk con show "$target" 2>"$tmp"); ' +
                'rc=$?; ' +
                'err=$(tr "\\n" " " < "$tmp"); rm -f "$tmp"; ' +
                'printf "RC:%s\\n" "$rc"; ' +
                'if [ -n "$err" ]; then printf "ERR:%s\\n" "$err"; fi; ' +
                'if [ -n "$psk" ]; then printf "PSK:%s\\n" "$psk"; exit 0; fi; ' +
                // The login keyring, where anything created by a GUI
                // tool keeps its secret (psk-flags=1). This is the step
                // that makes the panel match nm-connection-editor.
                'uuid=$(nmcli -g connection.uuid con show "$target" 2>/dev/null); ' +
                'if command -v secret-tool >/dev/null 2>&1 && [ -n "$uuid" ]; then ' +
                '  k=$(secret-tool lookup xdg:schema ' +
                '        org.freedesktop.NetworkManager.Connection ' +
                '        connection-uuid "$uuid" ' +
                '        setting-name 802-11-wireless-security ' +
                '        setting-key psk 2>/dev/null); ' +
                '  if [ -n "$k" ]; then printf "PSK:%s\\n" "$k"; exit 0; fi; ' +
                '  printf "KEYRING:miss\\n"; ' +
                'else printf "KEYRING:no-secret-tool\\n"; fi; ' +
                // Keyfile read: works without polkit if the file happens
                // to be group-readable, which some setups do.
                'kf="/etc/NetworkManager/system-connections/$target.nmconnection"; ' +
                'printf "KEYFILE:%s\\n" "$kf"; ' +
                'if [ -r "$kf" ]; then ' +
                '  psk=$(sed -n "s/^psk=//p" "$kf" | head -n1); ' +
                '  if [ -n "$psk" ]; then printf "PSK:%s\\n" "$psk"; exit 0; fi; ' +
                '  printf "KFREAD:yes-but-no-psk-line\\n"; ' +
                'else printf "KFREAD:unreadable\\n"; fi; ' +
                'printf "FLAGS:%s\\n" "$(nmcli -g 802-11-wireless-security.psk-flags con show "$target" 2>/dev/null)"; ' +
                'printf "KEYMGMT:%s\\n" "$(nmcli -g 802-11-wireless-security.key-mgmt con show "$target" 2>/dev/null)"; ' +
                // Whether NM thinks this caller may read secrets at all.
                // With auth-polkit=false every row reads "yes".
                'printf "PERM:%s\\n" "$(nmcli -t general permissions 2>/dev/null | ' +
                '  grep -i "settings.modify.own\\|settings.modify.system" | tr "\\n" " ")"',
                "--", name];
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let psk = "";
                let flags = "";
                let keymgmt = "";
                let errLine = "";
                let perms = "";
                let kfread = "";
                let keyring = "";
                let rc = "";
                let noProfile = false;

                for (const raw of text.split("\n")) {
                    const line = raw.trim();
                    if (line === "NOPROFILE") { noProfile = true; continue; }
                    const ci = line.indexOf(":");
                    if (ci === -1) continue;
                    const tag = line.substring(0, ci);
                    const val = line.substring(ci + 1);
                    if (tag === "PSK") psk = val;
                    else if (tag === "NAME") revealLoad.resolved = val;
                    else if (tag === "KEYFILE") revealLoad.keyfile = val;
                    else if (tag === "FLAGS") flags = val.trim();
                    else if (tag === "KEYMGMT") keymgmt = val.trim();
                    else if (tag === "ERR") errLine = val.trim();
                    else if (tag === "PERM") perms = val.trim();
                    else if (tag === "KFREAD") kfread = val.trim();
                    else if (tag === "KEYRING") keyring = val.trim();
                    else if (tag === "RC") rc = val.trim();
                }

                // Kept verbatim so the "copy diagnosis" button hands
                // over something complete rather than my summary of it.
                netPill.revealDiag = "profile=" + revealLoad.resolved
                    + "\nrc=" + rc + " flags=" + flags + " key-mgmt=" + keymgmt
                    + "\nkeyfile=" + kfread + " keyring=" + keyring
                    + "\nstderr=" + (errLine === "" ? "(none)" : errLine)
                    + "\nperms=" + (perms === "" ? "(none)" : perms);

                if (psk !== "") {
                    netPill.revealPsk = psk;
                    netPill.revealNote = "";
                    return;
                }
                if (noProfile) {
                    netPill.revealPsk = "—";
                    netPill.revealNote = "No saved profile for this network.";
                    return;
                }

                netPill.revealPsk = "—";
                if (keymgmt === "wpa-eap" || keymgmt === "wpa-eap-suite-b-192") {
                    netPill.revealNote = "Enterprise (802.1X): there is no PSK, "
                        + "the credentials are per-user.";
                } else if (keyring === "no-secret-tool") {
                    netPill.revealNote = "The key is agent-owned (in your login "
                        + "keyring, not in NetworkManager). Install libsecret so "
                        + "the keyring can be read: pacman -S libsecret";
                } else if (flags === "1") {
                    netPill.revealNote = "psk-flags=1 (agent-owned), and the login "
                        + "keyring has no entry for it — it may be locked, or "
                        + "held by a different keyring daemon than the one this "
                        + "session can reach.";
                } else if (flags === "2") {
                    netPill.revealNote = "psk-flags=2 (not-saved): NetworkManager "
                        + "asks for this key every time, so nothing is stored.";
                } else if (flags === "4") {
                    netPill.revealNote = "psk-flags=4 (not-required): open network.";
                } else if (errLine !== "") {
                    // nmcli actually said something. Show it rather
                    // than assuming which case this is.
                    netPill.revealNote = "nmcli: " + errLine;
                    netPill.revealCanRoot = revealLoad.keyfile !== "";
                } else if (perms.indexOf("auth") !== -1) {
                    // "...modify.system:auth" means polkit is still in
                    // the loop and would have to prompt.
                    netPill.revealNote = "NetworkManager still wants polkit "
                        + "authorization (permissions say \"auth\", not \"yes\").\n"
                        + "Add /etc/NetworkManager/conf.d/99-no-polkit.conf with "
                        + "[main] auth-polkit=false, then:\n"
                        + "  sudo systemctl reload NetworkManager";
                    netPill.revealCanRoot = revealLoad.keyfile !== "";
                } else {
                    // Permissions say yes, nmcli said nothing, flags
                    // say the key should be in the profile -- and it
                    // still came back empty. Out of theories: hand over
                    // the raw facts instead of inventing a reason.
                    netPill.revealNote = "nmcli returned an empty key with no error "
                        + "and no polkit refusal. Raw result:\n"
                        + netPill.revealDiag;
                    netPill.revealCanRoot = revealLoad.keyfile !== "";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && netPill.revealPsk === "…")
                    netPill.revealNote = text.trim();
            }
        }
    }

    // Last resort: read the keyfile as root with sudo -n.
    //
    // Deliberately NOT pkexec: pkexec IS polkit, and with no agent it
    // queues an invisible prompt on whatever terminal launched the
    // shell -- four unanswered ones is what tripped pam_faillock
    // before. `sudo -n` never prompts: it either succeeds because a
    // NOPASSWD rule or a live timestamp allows it, or it fails
    // instantly with "a password is required".
    Process {
        id: revealRoot
        function run() {
            if (revealLoad.keyfile === "") return;
            running = false;
            netPill.revealPsk = "…";
            command = ["sudo", "-n", "sed", "-n", "s/^psk=//p", revealLoad.keyfile];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split("\n")[0] ?? "";
                if (v !== "") {
                    netPill.revealPsk = v;
                    netPill.revealNote = "";
                    netPill.revealCanRoot = false;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "" && netPill.revealPsk === "…") {
                    netPill.revealPsk = "—";
                    netPill.revealNote = "sudo: " + text.trim().split("\n")[0]
                        + "\nsudo -n cannot prompt. Use the auth-polkit=false "
                        + "drop-in instead, or read the file in a terminal.";
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && netPill.revealPsk === "…") {
                netPill.revealPsk = "—";
                netPill.revealNote = "sudo -n exited " + code
                    + " (no passwordless rule for this).";
            }
        }
    }

    // Load every property of one connection; keep only schema keys.
    Process {
        id: editLoad
        function load(name) {
            running = false;
            command = ["nmcli", "-t", "con", "show", name];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const vals = {};
                let ctype = "";
                let active = false;
                for (const line of text.split('\n')) {
                    const ci = line.indexOf(':');
                    if (ci === -1) continue;
                    const key = line.substring(0, ci);
                    const val = line.substring(ci + 1).replace(/\\:/g, ":");
                    if (key === "connection.type")
                        ctype = val === "802-11-wireless" ? "wifi"
                              : val === "802-3-ethernet" ? "ethernet" : val;
                    if (key === "GENERAL.STATE") active = val === "activated";
                    if (key === "802-11-wireless-security.key-mgmt")
                        netPill.editKeyMgmt = (val === "--" ? "" : val);
                    if (netPill.editKeys.indexOf(key) !== -1)
                        vals[key] = (val === "--" ? "" : val);
                }
                netPill.editType = ctype;
                netPill.editWasActive = active;
                netPill.origValues = vals;
                netPill.editValues = Object.assign({}, vals);
                if (ctype === "wifi") secretLoad.load(netPill.editName);
            }
        }
    }

    // Load the connection's stored secret the way nm-connection-editor
    // does, which is why that dialog can tick "Show password" while
    // `nmcli -s` returns nothing:
    //
    //   - A SYSTEM-owned secret (psk-flags=0) lives in the profile and
    //     comes back from nmcli, given authorization.
    //   - An AGENT-owned secret (psk-flags=1, the default for anything
    //     created by a GUI) was never in the profile at all. It is in
    //     the login keyring, and nm-connection-editor reads it from
    //     there through libsecret -- no polkit involved, which is why
    //     it works for you and the panel did not.
    //
    // secret-tool is that same keyring, from the shell. The schema NM
    // stores under is org.freedesktop.NetworkManager.Connection, keyed
    // by the connection UUID plus the setting name and key.
    Process {
        id: secretLoad
        function load(name) {
            running = false;
            netPill.curSecret = "";
            netPill.pwField = "";
            netPill.secretNote = "";
            command = ["sh", "-c",
                'name="$1"; ' +
                'uuid=$(nmcli -g connection.uuid con show "$name" 2>/dev/null); ' +
                'km=$(nmcli -g 802-11-wireless-security.key-mgmt con show "$name" 2>/dev/null); ' +
                'case "$km" in ' +
                '  wpa-eap*) sn=802-1x; sk=password ;; ' +
                '  *) sn=802-11-wireless-security; sk=psk ;; ' +
                'esac; ' +
                'printf "SETTING:%s.%s\\n" "$sn" "$sk"; ' +
                // 1. the profile itself
                'v=$(nmcli -s -g "$sn.$sk" con show "$name" 2>/dev/null); ' +
                'if [ -n "$v" ]; then printf "SRC:profile\\nVAL:%s\\n" "$v"; exit 0; fi; ' +
                // 2. the login keyring, where GUI-made profiles put it
                'if command -v secret-tool >/dev/null 2>&1 && [ -n "$uuid" ]; then ' +
                '  v=$(secret-tool lookup xdg:schema ' +
                '        org.freedesktop.NetworkManager.Connection ' +
                '        connection-uuid "$uuid" setting-name "$sn" ' +
                '        setting-key "$sk" 2>/dev/null); ' +
                '  if [ -n "$v" ]; then printf "SRC:keyring\\nVAL:%s\\n" "$v"; exit 0; fi; ' +
                '  printf "SRC:none\\n"; ' +
                'else printf "SRC:nosecrettool\\n"; fi; ' +
                'printf "FLAGS:%s\\n" "$(nmcli -g "$sn.$sk-flags" con show "$name" 2>/dev/null)"',
                "--", name];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let val = "";
                let src = "";
                let flags = "";
                let setting = "";
                for (const raw of text.split("\n")) {
                    const line = raw.trim();
                    const ci = line.indexOf(":");
                    if (ci === -1) continue;
                    const tag = line.substring(0, ci);
                    const v = line.substring(ci + 1);
                    if (tag === "VAL") val = v;
                    else if (tag === "SRC") src = v.trim();
                    else if (tag === "FLAGS") flags = v.trim();
                    else if (tag === "SETTING") setting = v.trim();
                }
                netPill.secretKey = setting;
                netPill.curSecret = val;
                netPill.pwField = val;
                if (val !== "") {
                    netPill.secretNote = src === "keyring"
                        ? "read from the login keyring" : "stored in the profile";
                } else if (src === "nosecrettool") {
                    netPill.secretNote = "not in the profile, and secret-tool is "
                        + "not installed to read the keyring (pacman -S libsecret)";
                } else if (flags === "2") {
                    netPill.secretNote = "flags=2 (not-saved): nothing is stored "
                        + "anywhere, it is asked for each time";
                } else {
                    netPill.secretNote = "not found in the profile or the keyring";
                }
            }
        }
    }

    Process {
        id: editSave
        property bool wasActive: false
        property string conName: ""
        onExited: (code) => {
            netPill.busyText = "";
            if (code === 0) {
                if (wasActive)
                    netAction.runSh('nmcli con up id "$1"', [conName], "re-applying");
                netPill.editName = "";
            }
            refreshProcess.refresh();
        }
    }

    Timer { id: rescanSettle; interval: 3000; onTriggered: refreshProcess.refresh() }
    Timer {
        interval: 10000
        repeat: true
        running: overlay.visible
        onTriggered: refreshProcess.refresh()
    }

    // ---- shared mini components --------------------------------------

    component SectionLabel: Text {
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1
        color: Colors.textFaint
    }

    component MiniSwitch: Rectangle {
        property bool checked: false
        signal toggled()
        width: 36
        height: 18
        radius: 9
        color: checked ? Colors.accent : Colors.surface1
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 12; height: 12; radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: parent.checked ? parent.width - width - 3 : 3
            color: parent.checked ? Colors.accentFg : Colors.textFaint
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: parent.toggled() }
    }

    component MiniButton: Rectangle {
        property string label: ""
        property color tint: Colors.textMain
        signal clicked()
        implicitWidth: mbLabel.implicitWidth + 16
        implicitHeight: 22
        radius: 6
        color: mbMouse.containsMouse ? Colors.surface1 : Colors.surface0
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: mbLabel
            anchors.centerIn: parent
            text: parent.label
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            color: parent.tint
        }
        MouseArea { id: mbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
    }

    component MiniInput: Rectangle {
        property alias text: mi.text
        property alias echoMode: mi.echoMode
        property string placeholder: ""
        signal submitted()
        signal edited()
        function focusInput() { mi.forceActiveFocus(); }
        height: 26
        radius: 7
        color: Colors.mantle
        border.width: 1
        border.color: mi.activeFocus ? Qt.alpha(Colors.accent, 0.7) : Colors.outline
        Behavior on border.color { ColorAnimation { duration: 130 } }
        TextInput {
            id: mi
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: Colors.textMain
            clip: true
            onTextEdited: parent.edited()
            Keys.onReturnPressed: parent.submitted()
            Keys.onEnterPressed: parent.submitted()
            Text {
                visible: mi.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.placeholder
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: Colors.textFaint
            }
        }

        // The panel is a layer-shell window with keyboardFocus OnDemand:
        // the compositor hands it the keyboard on click, but the click
        // has to land somewhere that takes QML focus first. Without
        // this, typing in the password box did nothing at all. accepted
        // = false lets the press through to the TextInput underneath so
        // cursor placement and selection still work.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: (mouse) => { mi.forceActiveFocus(); mouse.accepted = false; }
        }
    }

    // ---- panel -------------------------------------------------------

    PanelWindow {
        id: overlay
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-network"
        color: "transparent"
        visible: false
        exclusiveZone: 0

        onVisibleChanged: {
            if (visible) refreshProcess.refresh();
            else {
                netPill.expandedSsid = "";
                netPill.editName = "";
                // Don't leave a plaintext key on screen for the next open.
                netPill.revealSsid = "";
                netPill.revealPsk = "";
                netPill.revealNote = "";
                netPill.revealCanRoot = false;
                netPill.errText = "";
                netPill.resetEapForm();
            }
        }

        MouseArea { anchors.fill: parent; onClicked: overlay.visible = false }

        Rectangle {
            id: panelCard
            x: Math.max(8, Math.min(
                netPill.mapToItem(null, 0, 0).x + netPill.width / 2 - width / 2,
                overlay.width - width - 8))
            y: 6
            width: netPill.editName !== "" ? 470 : 400
            implicitHeight: Math.min(panelFlick.contentHeight + 28, overlay.height - 40)
            radius: 14
            color: Colors.base
            border.width: 1
            border.color: Colors.outline
            clip: true
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            opacity: overlay.visible ? 1 : 0
            scale: overlay.visible ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            Flickable {
                id: panelFlick
                anchors.fill: parent
                anchors.margins: 14
                contentHeight: netPill.editName !== "" ? editorColumn.implicitHeight : panelColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // ==========================================================
                // PAGE 2: connection editor
                // ==========================================================
                Column {
                    id: editorColumn
                    visible: netPill.editName !== ""
                    width: panelFlick.width
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 24
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            MiniButton { label: "< back"; onClicked: netPill.editName = "" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: netPill.editName
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Colors.textMain
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: netPill.busyText !== ""
                            text: netPill.busyText
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            color: Colors.warn
                        }
                    }

                    // tab bar
                    Row {
                        spacing: 4
                        Repeater {
                            model: netPill.editTabs
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool active: netPill.editTab === index
                                implicitWidth: tabT.implicitWidth + 18
                                implicitHeight: 24
                                radius: 8
                                color: active ? Colors.accent
                                     : tabM.containsMouse ? Colors.surface1
                                     : Colors.surface0
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Text {
                                    id: tabT
                                    anchors.centerIn: parent
                                    text: parent.modelData.name
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: parent.active ? Font.DemiBold : Font.Normal
                                    color: parent.active ? Colors.accentFg : Colors.textDim
                                }
                                MouseArea {
                                    id: tabM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: netPill.editTab = parent.index
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Colors.outline }

                    // field rows for the active tab
                    Repeater {
                        model: netPill.visibleFields(netPill.editTabs[netPill.editTab])

                        Item {
                            id: fieldRow
                            required property var modelData
                            readonly property string fval: netPill.editValues[modelData.key] ?? ""
                            readonly property bool dirty: fval !== (netPill.origValues[modelData.key] ?? "")

                            width: editorColumn.width
                            height: 30

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 130
                                text: fieldRow.modelData.label + (fieldRow.dirty ? " *" : "")
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: fieldRow.dirty ? Colors.warn : Colors.textDim
                            }

                            // bool
                            MiniSwitch {
                                visible: fieldRow.modelData.type === "bool"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: fieldRow.fval === "yes"
                                onToggled: netPill.setEditValue(fieldRow.modelData.key,
                                    fieldRow.fval === "yes" ? "no" : "yes")
                            }

                            // choice (click cycles)
                            //
                            // Some settings read back as a number and
                            // are written as a number too (pmf: 0..3),
                            // so the raw value is useless as a label.
                            // valueLabels, when the field has one, maps
                            // the stored value to something readable
                            // without changing what gets saved.
                            MiniButton {
                                visible: fieldRow.modelData.type === "choice"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                label: {
                                    const vl = fieldRow.modelData.valueLabels;
                                    if (vl !== undefined && vl[fieldRow.fval] !== undefined)
                                        return vl[fieldRow.fval];
                                    return fieldRow.fval === "" ? "(default)" : fieldRow.fval;
                                }
                                onClicked: {
                                    const opts = fieldRow.modelData.options;
                                    // indexOf is -1 when NetworkManager
                                    // reported a value outside the list;
                                    // -1 + 1 = 0 starts the cycle at the
                                    // first option, which is what we want.
                                    const idx = opts.indexOf(fieldRow.fval);
                                    netPill.setEditValue(fieldRow.modelData.key,
                                        opts[(idx + 1) % opts.length]);
                                }
                            }

                            // text
                            MiniInput {
                                visible: fieldRow.modelData.type === "text"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 138
                                placeholder: fieldRow.modelData.hint ?? ""
                                text: fieldRow.fval
                                onEdited: netPill.setEditValue(fieldRow.modelData.key, text)
                            }
                        }
                    }

                    // SECURITY tab body (psk)
                    Column {
                        visible: (netPill.editTabs[netPill.editTab] ?? ({})).name === "SECURITY"
                        width: parent.width
                        spacing: 8

                        // The password box, loaded the way
                        // nm-connection-editor loads it: the field holds
                        // the CURRENT secret, "show password" reveals it,
                        // and a save happens only if you change it.
                        SectionLabel {
                            text: netPill.editIsEap ? "802.1X PASSWORD" : "PSK"
                        }

                        Row {
                            width: parent.width
                            spacing: 6

                            MiniInput {
                                id: pwBox
                                width: parent.width - 120
                                echoMode: netPill.pwShow ? TextInput.Normal
                                                         : TextInput.Password
                                placeholder: netPill.curSecret === ""
                                    ? "not stored \u2014 type to set one" : "password"
                                text: netPill.pwField
                                onEdited: netPill.pwField = text
                            }
                            MiniButton {
                                anchors.verticalCenter: pwBox.verticalCenter
                                label: (netPill.pwShow ? "\u25cf " : "\u25cb ") + "show"
                                tint: netPill.pwShow ? Colors.accent : Colors.textFaint
                                onClicked: netPill.pwShow = !netPill.pwShow
                            }
                            MiniButton {
                                anchors.verticalCenter: pwBox.verticalCenter
                                visible: netPill.pwField !== ""
                                label: "copy"
                                onClicked: Quickshell.execDetached(
                                    ["sh", "-c", 'printf %s "$1" | wl-copy', "--",
                                     netPill.pwField])
                            }
                        }

                        Text {
                            visible: netPill.secretNote !== ""
                            width: parent.width
                            text: netPill.secretNote
                                + (netPill.pwField !== netPill.curSecret
                                   ? "  \u2014  changed, will be written on save" : "")
                            wrapMode: Text.WordWrap
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            lineHeight: 1.3
                            color: netPill.curSecret === "" ? Colors.warn : Colors.textFaint
                        }

                        // Where a newly saved secret goes. Agent-owned is
                        // NetworkManager asking a secret agent for it on
                        // every connect -- with no agent running, that is
                        // a connection that silently never comes up.
                        Item {
                            width: parent.width
                            height: 20
                            MiniButton {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property string fkey: netPill.editIsEap
                                    ? "802-1x.password-flags"
                                    : "802-11-wireless-security.psk-flags"
                                readonly property bool stored:
                                    (netPill.editValues[fkey] ?? "") === "0"
                                label: (stored ? "\u25cf " : "\u25cb ")
                                       + "keep the password in the profile, not the keyring"
                                tint: stored ? Colors.accent : Colors.textFaint
                                onClicked: netPill.setEditValue(fkey, stored ? "1" : "0")
                            }
                        }

                        // Worth saying out loud on a campus network:
                        // without a CA cert and a domain match, the
                        // client accepts whatever RADIUS server answers,
                        // and anyone can stand up an AP with this SSID
                        // and collect the MSCHAPv2 exchange.
                        Text {
                            visible: netPill.editIsEap
                                     && (netPill.editValues["802-1x.ca-cert"] ?? "") === ""
                                     && (netPill.editValues["802-1x.domain-suffix-match"] ?? "") === ""
                            width: parent.width
                            text: "\u26a0  No CA cert and no domain match: this profile "
                                + "trusts any RADIUS server that answers for this SSID. "
                                + "Set at least domain match to your provider's server "
                                + "domain."
                            wrapMode: Text.WordWrap
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            lineHeight: 1.3
                            color: Colors.warn
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Colors.outline }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        MiniButton { label: "cancel"; onClicked: netPill.editName = "" }
                        MiniButton {
                            label: netPill.editWasActive ? "save & re-apply" : "save"
                            tint: Colors.accent
                            onClicked: netPill.saveEdit()
                        }
                    }

                    Text {
                        text: "* modified -- changes persist in this connection profile"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        color: Colors.textFaint
                    }
                }

                // ==========================================================
                // PAGE 1: overview
                // ==========================================================
                Column {
                    id: panelColumn
                    visible: netPill.editName === ""
                    width: panelFlick.width
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 24
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Network"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Colors.textMain
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: netPill.busyText !== ""
                                text: netPill.busyText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                color: Colors.warn
                            }
                        }
                    }

                    // nmcli's own failure message. Previously nothing was
                    // shown at all when an action failed.
                    Rectangle {
                        visible: netPill.errText !== ""
                        width: panelColumn.width
                        implicitHeight: errCol.implicitHeight + 16
                        radius: 9
                        color: Qt.alpha(Colors.danger, 0.12)
                        border.width: 1
                        border.color: Qt.alpha(Colors.danger, 0.45)

                        Column {
                            id: errCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 4

                            Item {
                                width: parent.width
                                height: errMsg.implicitHeight
                                Text {
                                    id: errMsg
                                    anchors.left: parent.left
                                    anchors.right: errClose.left
                                    anchors.rightMargin: 6
                                    text: "⚠  " + netPill.errText
                                    wrapMode: Text.WordWrap
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    color: Colors.danger
                                }
                                MiniButton {
                                    id: errClose
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    label: "dismiss"
                                    onClicked: netPill.errText = ""
                                }
                            }

                            // Almost always the real cause when nmcli
                            // refuses: NetworkManager handed the request
                            // to polkit and nothing answered. Taking
                            // polkit out of NetworkManager entirely is
                            // the fix that needs no agent.
                            Text {
                                visible: netPill.errIsAuth
                                width: parent.width
                                text: "NetworkManager asked polkit for authorization.\n"
                                    + "Write /etc/NetworkManager/conf.d/99-no-polkit.conf:\n"
                                    + "  [main]\n"
                                    + "  auth-polkit=false\n"
                                    + "then: sudo systemctl reload NetworkManager\n"
                                    + "Check with: nmcli general permissions"
                                wrapMode: Text.WordWrap
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                lineHeight: 1.3
                                color: Colors.textDim
                            }
                        }
                    }

                    Row {
                        spacing: 18
                        Row {
                            spacing: 7
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Wi-Fi"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textDim
                            }
                            MiniSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: netPill.wifiEnabled
                                onToggled: netAction.run(
                                    ["nmcli", "radio", "wifi", netPill.wifiEnabled ? "off" : "on"], "wifi radio")
                            }
                        }
                        Row {
                            spacing: 7
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Networking"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                color: Colors.textDim
                            }
                            MiniSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: netPill.networkingEnabled
                                onToggled: netAction.run(
                                    ["nmcli", "networking", netPill.networkingEnabled ? "off" : "on"], "networking")
                            }
                        }
                    }

                    SectionLabel { visible: netPill.activeDevs.length > 0; text: "CONNECTED" }

                    Repeater {
                        model: netPill.activeDevs

                        Rectangle {
                            id: devRow
                            required property var modelData
                            readonly property var info: netPill.devInfo[modelData.dev]
                                ?? ({ ips: [], gateway: "", dns: [] })

                            width: panelColumn.width
                            implicitHeight: devCol.implicitHeight + 20
                            radius: 10
                            color: Colors.mantle
                            border.width: 1
                            border.color: Colors.outline

                            Column {
                                id: devCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 4

                                Item {
                                    width: parent.width
                                    height: 16
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 7
                                        Text {
                                            text: devRow.modelData.type === "ethernet" ? "󰈀" : "󰖩"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            color: Colors.accent
                                        }
                                        Text {
                                            text: devRow.modelData.connection + "  \u00b7  " + devRow.modelData.dev
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: Colors.textMain
                                        }
                                    }
                                    MiniButton {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: "edit"
                                        onClicked: netPill.openEditor(devRow.modelData.connection)
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: "ip  " + (devRow.info.ips.join(", ") || "\u2014")
                                        + "\ngw  " + (devRow.info.gateway || "\u2014")
                                        + "\ndns " + (devRow.info.dns.join(", ") || "\u2014")
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    lineHeight: 1.3
                                    color: Colors.textDim
                                }
                            }
                        }
                    }

                    Item {
                        visible: netPill.wifiEnabled
                        width: parent.width
                        height: 16
                        SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: "WI-FI NETWORKS" }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            MiniButton {
                                label: hiddenBox.visible ? "cancel" : "hidden…"
                                onClicked: {
                                    hiddenBox.visible = !hiddenBox.visible;
                                    if (hiddenBox.visible) hiddenSsid.focusInput();
                                }
                            }
                            MiniButton {
                                label: "rescan"
                                onClicked: {
                                    netAction.run(["nmcli", "dev", "wifi", "rescan"], "scanning");
                                    rescanSettle.restart();
                                }
                            }
                        }
                    }

                    // A hidden network is not in the scan list at all, so
                    // it can only be joined by typing the SSID. `hidden
                    // yes` is what makes NetworkManager probe for it
                    // instead of waiting to see it beaconed.
                    Column {
                        id: hiddenBox
                        visible: false
                        width: panelColumn.width
                        spacing: 6

                        Row {
                            width: parent.width
                            spacing: 6
                            MiniInput {
                                id: hiddenSsid
                                width: (parent.width - 6) * 0.45
                                placeholder: "hidden SSID"
                                onSubmitted: hiddenPass.focusInput()
                            }
                            MiniInput {
                                id: hiddenPass
                                width: parent.width - hiddenSsid.width - 6 - 52
                                echoMode: TextInput.Password
                                placeholder: "password (blank = open)"
                                onSubmitted: hiddenGo.clicked()
                            }
                            MiniButton {
                                id: hiddenGo
                                anchors.verticalCenter: hiddenSsid.verticalCenter
                                label: "join"
                                tint: Colors.accent
                                onClicked: {
                                    if (hiddenSsid.text === "") return;
                                    // A hidden AP is never in the scan
                                    // cache, so security has to be
                                    // assumed: WPA unless no password
                                    // was given.
                                    netPill.joinWifi(
                                        hiddenSsid.text, hiddenPass.text,
                                        hiddenPass.text === "" ? "" : "WPA2", true);
                                    hiddenPass.text = "";
                                    hiddenBox.visible = false;
                                }
                            }
                        }
                    }

                    Repeater {
                        model: netPill.wifiEnabled ? netPill.wifiNetworks : []

                        Rectangle {
                            id: wifiRow
                            required property var modelData
                            readonly property bool secured:
                                modelData.security !== "" && modelData.security !== "--"
                            readonly property bool known:
                                netPill.savedNames.indexOf(modelData.ssid) !== -1
                            readonly property bool askingPassword:
                                netPill.expandedSsid === modelData.ssid
                            readonly property bool revealed:
                                netPill.revealSsid === modelData.ssid
                            // The scan row's SECURITY column reads
                            // "WPA2 802.1X" for an enterprise network.
                            readonly property bool isEap:
                                (modelData.security ?? "").toUpperCase()
                                    .indexOf("802.1X") !== -1

                            width: panelColumn.width
                            implicitHeight: wifiCol.implicitHeight + 16
                            radius: 9
                            color: modelData.inUse ? Qt.alpha(Colors.accent, 0.10)
                                 : wifiMouse.containsMouse ? Colors.surface0
                                 : "transparent"
                            border.width: modelData.inUse ? 1 : 0
                            border.color: Qt.alpha(Colors.accent, 0.4)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Column {
                                id: wifiCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6

                                Item {
                                    width: parent.width
                                    height: 18
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        Text {
                                            text: netPill.signalIcon(wifiRow.modelData.signal)
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 13
                                            color: wifiRow.modelData.inUse ? Colors.accent : Colors.textDim
                                        }
                                        Text {
                                            text: wifiRow.modelData.ssid
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            font.weight: wifiRow.modelData.inUse ? Font.DemiBold : Font.Normal
                                            color: wifiRow.modelData.inUse ? Colors.accent : Colors.textMain
                                        }
                                        Text {
                                            visible: wifiRow.secured
                                            text: "󰌾"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: Colors.textFaint
                                        }
                                    }
                                    Row {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        MiniButton {
                                            visible: wifiRow.known && wifiRow.secured
                                                     && wifiMouse.containsMouse
                                            label: wifiRow.revealed ? "hide" : "pass"
                                            onClicked: {
                                                if (wifiRow.revealed) {
                                                    netPill.revealSsid = "";
                                                    netPill.revealPsk = "";
                                                    netPill.revealNote = "";
                                                    netPill.revealCanRoot = false;
                                                } else {
                                                    revealLoad.load(wifiRow.modelData.ssid);
                                                }
                                            }
                                        }
                                        MiniButton {
                                            visible: wifiRow.known && wifiMouse.containsMouse
                                            label: "edit"
                                            onClicked: netPill.openEditor(wifiRow.modelData.ssid)
                                        }
                                        MiniButton {
                                            visible: wifiRow.known && wifiMouse.containsMouse
                                            label: "forget"
                                            tint: Colors.danger
                                            onClicked: netAction.runSh(
                                                'nmcli con delete id "$1"',
                                                [wifiRow.modelData.ssid], "forgetting")
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: wifiMouse.containsMouse || wifiRow.modelData.inUse
                                            text: wifiRow.modelData.inUse ? "disconnect"
                                                : wifiRow.known ? "connect"
                                                : wifiRow.isEap ? "802.1X\u2026"
                                                : wifiRow.secured ? "pass\u2026" : "connect"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            color: Colors.textFaint
                                        }
                                    }
                                }

                                // Saved key for a known network, plus why it
                                // is not readable when it is not.
                                Rectangle {
                                    visible: wifiRow.revealed
                                    width: parent.width
                                    implicitHeight: pskCol.implicitHeight + 12
                                    radius: 7
                                    color: Colors.mantle
                                    border.width: 1
                                    border.color: Colors.outline

                                    Column {
                                        id: pskCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 6
                                        spacing: 5

                                        Item {
                                            width: parent.width
                                            height: 20
                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 2
                                                anchors.right: pskBtns.left
                                                anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: netPill.revealPsk
                                                elide: Text.ElideRight
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                                color: netPill.revealNote === ""
                                                    ? Colors.textMain : Colors.textFaint
                                            }
                                            Row {
                                                id: pskBtns
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 5
                                                MiniButton {
                                                    visible: netPill.revealCanRoot
                                                    label: "read as root"
                                                    tint: Colors.warn
                                                    onClicked: revealRoot.run()
                                                }
                                                MiniButton {
                                                    visible: netPill.revealNote !== ""
                                                             && netPill.revealDiag !== ""
                                                    label: "copy diagnosis"
                                                    onClicked: Quickshell.execDetached(
                                                        ["sh", "-c", 'printf %s "$1" | wl-copy',
                                                         "--", netPill.revealDiag])
                                                }
                                                MiniButton {
                                                    visible: netPill.revealNote === ""
                                                             && netPill.revealPsk !== "…"
                                                    label: "copy"
                                                    onClicked: Quickshell.execDetached(
                                                        ["sh", "-c", 'printf %s "$1" | wl-copy',
                                                         "--", netPill.revealPsk])
                                                }
                                            }
                                        }

                                        Text {
                                            visible: netPill.revealNote !== ""
                                            width: parent.width
                                            text: netPill.revealNote
                                            wrapMode: Text.WordWrap
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            lineHeight: 1.3
                                            color: Colors.warn
                                        }
                                    }
                                }

                                // WPA-PSK / open: one password box.
                                Row {
                                    id: passRow
                                    visible: wifiRow.askingPassword && !wifiRow.isEap
                                    width: parent.width
                                    spacing: 6

                                    // Focus follows the box opening, so the
                                    // password can be typed without a second
                                    // click into the field.
                                    onVisibleChanged: if (visible) passInput.focusInput()

                                    MiniInput {
                                        id: passInput
                                        width: parent.width - 110
                                        echoMode: passShow.on ? TextInput.Normal
                                                              : TextInput.Password
                                        placeholder: "password"
                                        onSubmitted: passGo.clicked()
                                    }
                                    MiniButton {
                                        id: passShow
                                        property bool on: false
                                        anchors.verticalCenter: passInput.verticalCenter
                                        label: on ? "hide" : "show"
                                        onClicked: { on = !on; passInput.focusInput(); }
                                    }
                                    MiniButton {
                                        id: passGo
                                        anchors.verticalCenter: passInput.verticalCenter
                                        label: "join"
                                        tint: Colors.accent
                                        onClicked: {
                                            if (passInput.text === "") return;
                                            netPill.joinWifi(
                                                wifiRow.modelData.ssid,
                                                passInput.text,
                                                wifiRow.modelData.security,
                                                false);
                                            passInput.text = "";
                                            netPill.expandedSsid = "";
                                        }
                                    }
                                }

                                // 802.1X: no shared key exists, so the
                                // profile has to be built from an EAP
                                // method, an identity and an inner auth
                                // before it can associate at all.
                                Column {
                                    id: eapForm
                                    visible: wifiRow.askingPassword && wifiRow.isEap
                                    width: parent.width
                                    spacing: 6

                                    onVisibleChanged: if (visible) eapIdent.focusInput()

                                    Row {
                                        width: parent.width
                                        spacing: 6
                                        MiniButton {
                                            label: "eap: " + netPill.eapMethod
                                            onClicked: {
                                                const o = ["peap", "ttls", "tls", "pwd"];
                                                netPill.eapMethod =
                                                    o[(o.indexOf(netPill.eapMethod) + 1) % o.length];
                                            }
                                        }
                                        MiniButton {
                                            visible: netPill.eapMethod === "peap"
                                                     || netPill.eapMethod === "ttls"
                                            label: "inner: " + netPill.eapPhase2
                                            onClicked: {
                                                const o = ["mschapv2", "pap", "gtc", "chap", "md5"];
                                                netPill.eapPhase2 =
                                                    o[(o.indexOf(netPill.eapPhase2) + 1) % o.length];
                                            }
                                        }
                                    }

                                    MiniInput {
                                        id: eapIdent
                                        width: parent.width
                                        placeholder: "identity / username"
                                        text: netPill.eapIdentity
                                        onEdited: netPill.eapIdentity = text
                                        onSubmitted: eapPw.focusInput()
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: 6
                                        MiniInput {
                                            id: eapPw
                                            width: parent.width - 110
                                            echoMode: netPill.eapShowPw ? TextInput.Normal
                                                                        : TextInput.Password
                                            placeholder: "password"
                                            text: netPill.eapPassword
                                            onEdited: netPill.eapPassword = text
                                            onSubmitted: eapGo.clicked()
                                        }
                                        MiniButton {
                                            anchors.verticalCenter: eapPw.verticalCenter
                                            label: netPill.eapShowPw ? "hide" : "show"
                                            onClicked: {
                                                netPill.eapShowPw = !netPill.eapShowPw;
                                                eapPw.focusInput();
                                            }
                                        }
                                        MiniButton {
                                            id: eapGo
                                            anchors.verticalCenter: eapPw.verticalCenter
                                            label: "join"
                                            tint: Colors.accent
                                            onClicked: {
                                                if (netPill.eapIdentity === ""
                                                    || netPill.eapPassword === "") return;
                                                netPill.joinWifiEap(
                                                    wifiRow.modelData.ssid,
                                                    netPill.eapMethod,
                                                    netPill.eapIdentity,
                                                    netPill.eapAnon,
                                                    netPill.eapPhase2,
                                                    netPill.eapPassword,
                                                    netPill.eapDomain,
                                                    netPill.eapCa);
                                                netPill.expandedSsid = "";
                                                netPill.resetEapForm();
                                            }
                                        }
                                    }

                                    // Optional, and folded away until
                                    // asked for: most people need only
                                    // identity + password, but on a
                                    // campus network the server checks
                                    // are the difference between this
                                    // profile and a safe one.
                                    MiniButton {
                                        id: eapMore
                                        property bool on: false
                                        label: (on ? "\u25bc " : "\u25b6 ")
                                               + "anonymous identity, server checks"
                                        onClicked: on = !on
                                    }

                                    MiniInput {
                                        visible: eapMore.on
                                        width: parent.width
                                        placeholder: "anonymous identity (optional)"
                                        text: netPill.eapAnon
                                        onEdited: netPill.eapAnon = text
                                    }
                                    MiniInput {
                                        visible: eapMore.on
                                        width: parent.width
                                        placeholder: "domain match, e.g. radius.pb.edu.pl"
                                        text: netPill.eapDomain
                                        onEdited: netPill.eapDomain = text
                                    }
                                    MiniInput {
                                        visible: eapMore.on
                                        width: parent.width
                                        placeholder: "CA certificate path (optional)"
                                        text: netPill.eapCa
                                        onEdited: netPill.eapCa = text
                                    }

                                    Text {
                                        visible: netPill.eapDomain === "" && netPill.eapCa === ""
                                        width: parent.width
                                        text: "\u26a0  Without a domain match or CA cert this "
                                            + "profile trusts any RADIUS server answering for "
                                            + "this SSID."
                                        wrapMode: Text.WordWrap
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        lineHeight: 1.3
                                        color: Colors.warn
                                    }
                                }
                            }

                            MouseArea {
                                id: wifiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                z: -1
                                onClicked: {
                                    const m = wifiRow.modelData;
                                    if (m.inUse) {
                                        netAction.runSh('nmcli con down id "$1"', [m.ssid], "disconnecting");
                                    } else if (wifiRow.known) {
                                        // Saved profile: bring it up as-is. No
                                        // fallback to `dev wifi connect` here --
                                        // that is what produced "Failed to
                                        // determine AP security information" and
                                        // buried the real reason `con up` failed.
                                        netAction.runSh('nmcli con up id "$1"',
                                                        [m.ssid], "connecting");
                                    } else if (!wifiRow.secured) {
                                        netPill.joinWifi(m.ssid, "", m.security, false);
                                    } else {
                                        netPill.expandedSsid = wifiRow.askingPassword ? "" : m.ssid;
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel { text: "VPN" }

                    Text {
                        visible: netPill.vpns.length === 0
                        text: "No VPN profiles in NetworkManager.\nImport one: nmcli con import type wireguard file <conf>"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        lineHeight: 1.3
                        color: Colors.textFaint
                    }

                    Repeater {
                        model: netPill.vpns

                        Item {
                            required property var modelData
                            width: panelColumn.width
                            height: 26

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text {
                                    text: parent.parent.modelData.name
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    color: parent.parent.modelData.active ? Colors.accent : Colors.textMain
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.modelData.type
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    color: Colors.textFaint
                                }
                            }

                            MiniSwitch {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: parent.modelData.active
                                onToggled: netAction.runSh(
                                    parent.modelData.active
                                        ? 'nmcli con down id "$1"'
                                        : 'nmcli con up id "$1"',
                                    [parent.modelData.name],
                                    parent.modelData.active ? "vpn down" : "vpn up")
                            }
                        }
                    }
                }
            }
        }
    }
}
