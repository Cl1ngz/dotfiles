import QtQuick
import qs
import "Parse.js" as Parse

// Completion stats, in the shape Loop Habit Tracker uses: a heatmap, a
// bar chart and four numbers.
//
// Both charts are ONE Canvas each. A heatmap of ten years is ~3650
// cells; as QML Items that is 3650 scene-graph nodes to create, lay out
// and keep alive, which is slow to build and expensive to hold. Drawn
// into a single Canvas it is one node and a few milliseconds of 2D
// calls, repainted only when something actually changes.
//
// Nothing here re-reads or re-parses the file. Every number comes from
// store.stats.byDate, the table built once per file change, so flipping
// ranges and filters is pure arithmetic over a small object.
Item {
    id: statsView

    required property var store

    // week, month, quarter, year, 3 years, all
    property int range: 1
    readonly property var rangeNames: ["week", "month", "quarter", "year", "3 years", "all"]

    property string filterCat: ""
    property var filterImp: null
    property bool pickerOpen: false

    implicitHeight: col.implicitHeight

    // The accent for every chart: the category's own colour when one is
    // selected, as the spec asks, otherwise the theme accent.
    readonly property color tone: {
        if (filterCat !== "" && filterCat !== "uncategorized") {
            for (const c of store.config.categories)
                if (c.name === filterCat) return c.color;
        }
        if (filterImp !== null) {
            for (const i of store.config.importance)
                if (i.level === filterImp) return i.color;
        }
        return Colors.accent;
    }

    // ---- date helpers ------------------------------------------------

    function pad2(n) { return n < 10 ? "0" + n : "" + n; }
    function iso(d) {
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
    }
    function fromIso(s) { const p = s.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]); }
    function addDays(d, n) { return Parse.addDays(d, n); }

    function startOfWeek(d) { return Parse.startOfWeek(d); }

    readonly property var todayDate: new Date()

    // Inclusive [start, end] for the selected range.
    readonly property var span: {
        const end = new Date(todayDate);
        end.setHours(0, 0, 0, 0);
        let start;
        switch (range) {
        case 0: start = startOfWeek(end); break;
        case 1: start = new Date(end.getFullYear(), end.getMonth(), 1); break;
        case 2: start = new Date(end.getFullYear(), end.getMonth() - 2, 1); break;
        case 3: start = new Date(end.getFullYear(), 0, 1); break;
        case 4: start = new Date(end.getFullYear() - 2, 0, 1); break;
        default:
            start = store.stats.first ? fromIso(store.stats.first)
                                      : new Date(end.getFullYear(), 0, 1);
            start = new Date(start.getFullYear(), 0, 1);
            break;
        }
        return { start: start, end: end };
    }

    function countFor(dateStr) {
        return Parse.countOn(store.stats, dateStr,
                             filterCat === "" ? null : filterCat, filterImp);
    }

    // ---- aggregates ----------------------------------------------------

    // Both of these come from Parse.js, where they are unit-tested,
    // rather than being written out again in QML.
    readonly property var agg: Parse.aggregateRange(
        store.stats, iso(span.start), iso(span.end),
        filterCat === "" ? null : filterCat, filterImp)

    // Counted back from today regardless of the range: a streak is a
    // fact about now, and truncating it at the range start would show
    // "3" in week view for a streak that is really 40 days long.
    readonly property int streakNow: Parse.currentStreak(
        store.stats, filterCat === "" ? null : filterCat, filterImp)

    // Bars: per day for week and month, per week for quarter and year,
    // per month beyond that. Anything else and a ten-year view would be
    // 3650 bars in a 690px box.
    readonly property string barUnit:
        range <= 1 ? "day" : (range <= 3 ? "week" : "month")

    readonly property var bars: Parse.bucketBars(agg.days, barUnit)

    // Heatmap shape. A week or month reads best as a calendar; a year
    // as GitHub's 7x53; several years as one row each, aggregated by
    // week, because 3x365 cells side by side are unreadable.
    readonly property string heatMode:
        range <= 1 ? "calendar" : (range <= 3 ? "github" : "years")

    onRangeChanged: repaintAll()
    onFilterCatChanged: repaintAll()
    onFilterImpChanged: repaintAll()
    onWidthChanged: repaintAll()
    // The canvas is sized from heatGeom, so a geometry change and a
    // repaint have to happen together or the drawing lags its box.
    onHeatGeomChanged: heat.requestPaint()

    Connections {
        target: statsView.store
        function onRefreshed() { statsView.repaintAll(); }
    }

    function repaintAll() {
        heat.requestPaint();
        barsCanvas.requestPaint();
    }

    // Five steps, like a contribution graph: empty plus four weights.
    // Scaled against the busiest day in view so a quiet month still
    // shows contrast instead of four shades of nearly-nothing.
    function cellColor(n) {
        if (n <= 0) return Colors.surface0;
        const m = Math.max(1, agg.max);
        const step = Math.min(4, Math.ceil((n / m) * 4));
        return Qt.alpha(tone, 0.18 + 0.26 * step);
    }

    // Inline components have to be declared at the top level of the
    // file's root object -- nested inside a Row this silently fails to
    // load the whole file.
    component Stat: Rectangle {
        id: statBox
        property string value: ""
        property string caption: ""
        width: (statsView.width - 24) / 4
        height: 52
        radius: 10
        color: Colors.surface0
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: statBox.value
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: Colors.textMain
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: statBox.caption
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                color: Colors.textFaint
            }
        }
    }

    // Heatmap geometry, computed once and read by both the Canvas
    // height and its paint handler, so the box can never be a different
    // size from the thing inside it.
    readonly property int heatGap: 3
    readonly property int heatLabelW: 24
    readonly property int heatLabelH: 15

    readonly property var heatGeom: {
        const w = Math.max(100, width);
        if (heatMode === "calendar") {
            // Whole calendar month (or week), Monday first. Showing the
            // full month rather than stopping at today keeps the grid a
            // stable shape and makes "the rest of the month" visible.
            const gridStart = Parse.startOfWeek(span.start);
            const gridEnd = range === 0
                ? Parse.addDays(gridStart, 6)
                : new Date(span.start.getFullYear(), span.start.getMonth() + 1, 0);
            const weeks = Math.max(1, Math.ceil(
                ((gridEnd - gridStart) / 86400000 + 1) / 7));
            const cell = Math.max(14, Math.min(26,
                Math.floor((w - heatLabelW - heatGap * 6) / 7)));
            return { mode: "calendar", cell: cell, weeks: weeks,
                     gridStart: gridStart,
                     height: heatLabelH + weeks * (cell + heatGap) + 2 };
        }
        if (heatMode === "github") {
            const gridStart = Parse.startOfWeek(span.start);
            const weeks = Math.max(1, Math.ceil(
                ((span.end - gridStart) / 86400000 + 1) / 7));
            const cell = Math.max(5, Math.min(13,
                Math.floor((w - heatLabelW) / weeks) - heatGap));
            return { mode: "github", cell: cell, weeks: weeks,
                     gridStart: gridStart,
                     height: heatLabelH + 7 * (cell + heatGap) + 2 };
        }
        const years = Math.max(1, span.end.getFullYear() - span.start.getFullYear() + 1);
        const cell = Math.max(5, Math.min(14, Math.floor((w - heatLabelW) / 53) - 1));
        return { mode: "years", cell: cell, years: years,
                 height: heatLabelH + years * (cell + 8) + 2 };
    }

    // ---- layout ---------------------------------------------------------

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        // range picker
        Flow {
            width: col.width
            spacing: 5
            Repeater {
                model: statsView.rangeNames
                Chip {
                    required property var modelData
                    required property int index
                    label: modelData
                    tint: Colors.accent
                    active: statsView.range === index
                    onClicked: statsView.range = index
                }
            }
        }

        // Category through a picker, importance as chips: there are
        // five levels at most, and any number of categories.
        Item {
            width: col.width
            implicitHeight: Math.max(statCatPicker.implicitHeight, statImpFlow.implicitHeight, 26)

            Picker {
                id: statCatPicker
                width: 200
                anchors.left: parent.left
                anchors.top: parent.top
                placeholder: "all categories"
                options: statsView.store.config.categories
                            .map((c) => ({ name: c.name, color: c.color }))
                current: statsView.filterCat === "" ? null : statsView.filterCat
                open: statsView.pickerOpen
                onToggled: statsView.pickerOpen = !statsView.pickerOpen
                onPicked: (v) => {
                    statsView.filterCat = v === null ? "" : v;
                    statsView.pickerOpen = false;
                }
            }

            // Flow, not Row: a Row would run off the edge of the
            // card if the importance list ever grew past a handful.
            Flow {
                id: statImpFlow
                anchors.left: statCatPicker.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 5
                Chip {
                    label: "any !"
                    active: statsView.filterImp === null
                    onClicked: statsView.filterImp = null
                }
                Repeater {
                    model: statsView.store.config.importance
                    Chip {
                        required property var modelData
                        label: "!" + modelData.level
                        tint: modelData.color
                        active: statsView.filterImp === modelData.level
                        onClicked: statsView.filterImp =
                            (statsView.filterImp === modelData.level ? null : modelData.level)
                    }
                }
            }
        }

        // Both filters at once is deliberately not supported by the
        // cache -- say so rather than quietly showing a wrong number.
        Text {
            visible: statsView.filterCat !== "" && statsView.filterImp !== null
            width: col.width
            text: "⚠  Category and importance together is an estimate: the cache "
                + "counts them separately."
            wrapMode: Text.WordWrap
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            color: Colors.warn
        }

        // ---- numbers ---------------------------------------------------

        Row {
            width: col.width
            spacing: 8

            Stat { value: "" + statsView.agg.total; caption: "done" }
            Stat { value: "" + statsView.streakNow; caption: "streak now" }
            Stat { value: "" + statsView.agg.longest; caption: "longest" }
            Stat {
                value: "" + statsView.agg.best.count
                caption: statsView.agg.best.date
                    ? "best \u00b7 " + statsView.agg.best.date.slice(5) : "best day"
            }
        }

        // ---- heatmap ----------------------------------------------------

        Canvas {
            id: heat
            width: col.width
            // Sized from what is actually drawn. A fixed height left a
            // month view -- two rows of squares -- sitting in a 150px
            // box with a third of the card empty underneath it.
            height: statsView.heatGeom.height
            renderStrategy: Canvas.Cooperative

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.font = "9px 'JetBrainsMono Nerd Font'";
                ctx.textBaseline = "middle";

                const g = statsView.heatGeom;
                const gap = statsView.heatGap;
                const labelW = statsView.heatLabelW;
                const labelH = statsView.heatLabelH;
                const step = g.cell + gap;

                if (g.mode === "calendar") {
                    const dows = ["M", "T", "W", "T", "F", "S", "S"];
                    ctx.fillStyle = Colors.textFaint;
                    for (let c = 0; c < 7; c++)
                        ctx.fillText(dows[c], labelW + c * step + g.cell / 2 - 3, 7);

                    for (let w = 0; w < g.weeks; w++) {
                        for (let c = 0; c < 7; c++) {
                            const d = Parse.addDays(g.gridStart, w * 7 + c);
                            const key = statsView.iso(d);
                            // Days of the month that have not happened
                            // yet are drawn as outlines, so the shape of
                            // the month stays readable instead of the
                            // grid just stopping mid-row.
                            const inMonth = statsView.range === 0
                                || d.getMonth() === statsView.span.start.getMonth();
                            if (!inMonth) continue;

                            const future = d > statsView.span.end;
                            const n = future ? 0 : statsView.countFor(key);
                            const x = labelW + c * step;
                            const y = labelH + w * step;

                            ctx.beginPath();
                            ctx.roundedRect(x, y, g.cell, g.cell, 4, 4);
                            if (future) {
                                ctx.strokeStyle = Qt.alpha(Colors.outline, 0.5);
                                ctx.lineWidth = 1;
                                ctx.stroke();
                            } else {
                                ctx.fillStyle = statsView.cellColor(n);
                                ctx.fill();
                            }

                            // Today gets a ring, so "where am I" needs
                            // no counting.
                            if (key === statsView.iso(statsView.span.end)) {
                                ctx.strokeStyle = statsView.tone;
                                ctx.lineWidth = 1;
                                ctx.beginPath();
                                ctx.roundedRect(x + 0.5, y + 0.5,
                                                g.cell - 1, g.cell - 1, 4, 4);
                                ctx.stroke();
                            }

                            ctx.fillStyle = future ? Qt.alpha(Colors.textFaint, 0.5)
                                          : n > 0 ? Colors.base : Colors.textFaint;
                            ctx.fillText("" + d.getDate(), x + 4, y + g.cell / 2);
                        }
                    }
                } else if (g.mode === "github") {
                    for (let w = 0; w < g.weeks; w++) {
                        for (let c = 0; c < 7; c++) {
                            const d = Parse.addDays(g.gridStart, w * 7 + c);
                            if (d < statsView.span.start || d > statsView.span.end) continue;
                            ctx.fillStyle =
                                statsView.cellColor(statsView.countFor(statsView.iso(d)));
                            ctx.beginPath();
                            ctx.roundedRect(labelW + w * step, labelH + c * step,
                                            g.cell, g.cell, 2, 2);
                            ctx.fill();
                        }
                    }

                    // A month tick each time the month changes, so a
                    // year of squares is readable without counting.
                    ctx.fillStyle = Colors.textFaint;
                    let lastMonth = -1;
                    for (let w = 0; w < g.weeks; w++) {
                        const d = Parse.addDays(g.gridStart, w * 7);
                        if (d.getMonth() !== lastMonth) {
                            lastMonth = d.getMonth();
                            ctx.fillText(
                                ["Jan","Feb","Mar","Apr","May","Jun",
                                 "Jul","Aug","Sep","Oct","Nov","Dec"][lastMonth],
                                labelW + w * step, 7);
                        }
                    }
                } else {
                    // One row per year, each cell a week. Weekly totals
                    // are scaled against the busiest WEEK, not the
                    // busiest day, or every cell saturates.
                    const y0 = statsView.span.start.getFullYear();
                    let weekMax = 1;
                    const rows = [];

                    for (let y = y0; y < y0 + g.years; y++) {
                        const cursor = Parse.startOfWeek(new Date(y, 0, 1));
                        const row = [];
                        for (let w = 0; w < 53; w++) {
                            let sum = 0;
                            let any = false;
                            for (let k = 0; k < 7; k++) {
                                const d = Parse.addDays(cursor, w * 7 + k);
                                if (d.getFullYear() !== y) continue;
                                if (d > statsView.span.end) continue;
                                any = true;
                                sum += statsView.countFor(statsView.iso(d));
                            }
                            row.push(any ? sum : -1);
                            if (sum > weekMax) weekMax = sum;
                        }
                        rows.push(row);
                    }

                    for (let r = 0; r < rows.length; r++) {
                        const rowY = labelH + r * (g.cell + 8);
                        ctx.fillStyle = Colors.textFaint;
                        ctx.fillText("" + (y0 + r), 0, rowY + g.cell / 2);
                        for (let w = 0; w < 53; w++) {
                            const v = rows[r][w];
                            if (v < 0) continue;
                            ctx.fillStyle = v <= 0 ? Colors.surface0
                                : Qt.alpha(statsView.tone,
                                    0.18 + 0.26 * Math.min(4, Math.ceil((v / weekMax) * 4)));
                            ctx.beginPath();
                            ctx.roundedRect(labelW + w * (g.cell + 1), rowY,
                                            g.cell, g.cell, 2, 2);
                            ctx.fill();
                        }
                    }
                }
            }
        }

        // ---- bars --------------------------------------------------------

        Item {
            width: col.width
            height: 104

            Text {
                id: barTitle
                text: "PER " + statsView.barUnit.toUpperCase()
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.letterSpacing: 1
                color: Colors.textFaint
            }

            Canvas {
                id: barsCanvas
                anchors.top: barTitle.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                renderStrategy: Canvas.Cooperative

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.font = "9px 'JetBrainsMono Nerd Font'";

                    const data = statsView.bars;
                    if (data.length === 0) return;

                    const axisH = 14;
                    const plotH = height - axisH;
                    let max = 0;
                    for (const b of data) if (b.count > max) max = b.count;

                    const slot = width / data.length;
                    const barW = Math.max(2, Math.min(26, slot - 3));

                    // Baseline
                    ctx.strokeStyle = Colors.outline;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(0, plotH + 0.5);
                    ctx.lineTo(width, plotH + 0.5);
                    ctx.stroke();

                    if (max === 0) {
                        ctx.fillStyle = Colors.textFaint;
                        ctx.fillText("nothing completed in this range", 2, plotH / 2);
                        return;
                    }

                    // A faint line at the peak gives the bars a scale
                    // instead of leaving them floating.
                    ctx.strokeStyle = Qt.alpha(Colors.outline, 0.6);
                    ctx.beginPath();
                    ctx.moveTo(0, 8.5);
                    ctx.lineTo(width, 8.5);
                    ctx.stroke();
                    ctx.fillStyle = Colors.textFaint;
                    ctx.fillText("" + max, 2, 6);

                    // Roughly one label per 44px, so a year of weeks
                    // does not smear into a grey band.
                    const everyN = Math.max(1, Math.ceil(data.length
                        / Math.max(1, Math.floor(width / 44))));

                    for (let i = 0; i < data.length; i++) {
                        const b = data[i];
                        const x = Math.round(i * slot + (slot - barW) / 2);

                        if (b.count === 0) {
                            // An empty bucket is drawn as a sliver
                            // rather than nothing: a chart of mostly
                            // blank space reads as broken, and this
                            // shows the day existed and was empty.
                            ctx.fillStyle = Colors.surface0;
                            ctx.beginPath();
                            ctx.roundedRect(x, plotH - 2, barW, 2, 1, 1);
                            ctx.fill();
                        } else {
                            const h = Math.max(3,
                                Math.round((b.count / max) * (plotH - 12)));
                            ctx.fillStyle = Qt.alpha(statsView.tone, 0.85);
                            ctx.beginPath();
                            ctx.roundedRect(x, plotH - h, barW, h, 3, 3);
                            ctx.fill();

                            // Value on top, when the bars are wide
                            // enough that it will not collide.
                            if (barW >= 14) {
                                ctx.fillStyle = Colors.textFaint;
                                ctx.fillText("" + b.count, x + barW / 2 - 3, plotH - h - 4);
                            }
                        }

                        if (i % everyN === 0) {
                            ctx.fillStyle = Colors.textFaint;
                            ctx.fillText(b.label, x, height - 3);
                        }
                    }
                }
            }
        }

        Text {
            visible: statsView.agg.total === 0
            width: col.width
            text: "Nothing completed in this range."
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            color: Colors.textFaint
        }
    }
}
