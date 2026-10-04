import QtQuick
import org.kde.milou as Milou

// KRunner's search, without KRunner's window: the result model Plasma's own
// KRunner uses (from Milou), which runs the runner plugins enabled in System
// Settings > Search > KRunner inside this process. Loaded by the CommandPalette
// singleton through a Loader, because the import is optional.
//
// `matches` is the model's content as plain objects, in the model's order
// (best category first) except that open windows and answers go first, for a
// view that knows nothing about KRunner.
Item {
    id: root

    property string query: ""
    readonly property bool querying: model.querying
    // false from a change of the query until the model has answered it, at
    // least in part; until then `matches` still belong to the previous query
    property bool fresh: true
    // the model has reported something since the query changed
    property bool answered: true
    property var matches: []

    // a match that, instead of doing something, wants the query replaced
    signal queryRequested(string text)

    onQueryChanged: {
        fresh = query.trim() === "";
        answered = fresh;
        if (fresh)
            matches = [];
    }

    // The model's content changed, or it finished querying. Results arrive
    // runner by runner; one rebuild per burst.
    function changed() {
        answered = true;
        Qt.callLater(rebuild);
    }

    // Row of the match `id`: `row` if `matches` is in the model's order and
    // the model has not changed since it was built.
    function locate(row, id) {
        const idAt = at => model.data(model.index(at, 0), Milou.ResultsModel.IdRole);
        if (row < model.rowCount() && idAt(row) === id)
            return row;
        for (let at = 0; at < model.rowCount(); at++)
            if (idAt(at) === id)
                return at;
        return -1;
    }

    // Runs a match, or one of its actions (`action` >= 0). True if that did
    // something and the palette can close.
    function run(row, id, action) {
        const at = locate(row, id);
        if (at < 0)
            return false;
        const index = model.index(at, 0);
        return action >= 0 ? model.runAction(index, action) : model.run(index);
    }

    function rebuild() {
        const count = model.rowCount();
        // While a query runs KRunner may have nothing yet (it keeps the
        // previous rows, or none). The previous results stay up until the
        // first new ones arrive, so the list does not collapse and regrow
        // with every letter typed.
        if (!answered || (count === 0 && model.querying))
            return;
        const list = [];
        for (let row = 0; row < count; row++) {
            const index = model.index(row, 0);
            const id = model.data(index, Milou.ResultsModel.IdRole) ?? "";
            const title = String(model.data(index, Qt.DisplayRole) ?? "");
            const subtitle = String(model.data(index, Milou.ResultsModel.SubtextRole) ?? "");
            // An icon name where the runner gave one, else a QIcon, which may
            // be empty (browser tabs and history have none). Script cannot
            // tell an empty QIcon from a real one, so the view gets a stand-in
            // to show when the icon turns out not to be usable.
            const icon = model.data(index, Qt.DecorationRole) ?? "";
            const isUrl = /^[a-z][a-z0-9+.-]*:\/\//i.test(subtitle);
            const actions = model.data(index, Milou.ResultsModel.ActionsRole) ?? [];
            const actionList = [];
            for (let n = 0; n < actions.length; n++)
                actionList.push({
                    text: actions[n].text,
                    icon: actions[n].iconSource
                });
            list.push({
                // what the view knows a result by when the list is replaced:
                // some runners reuse one id for whatever they currently
                // answer (the unit converter)
                key: id + "\n" + title + "\n" + subtitle,
                kind: "match",
                id: id,
                title: title,
                subtitle: subtitle,
                icon: icon,
                symbolic: false,
                fallbackIcon: isUrl ? "internet-web-browser" : "search-symbolic",
                category: String(model.data(index, Milou.ResultsModel.CategoryRole) ?? ""),
                actions: actionList,
                // the calculator's and the unit converter's: not something to
                // open, but the answer to what was typed
                answer: /^(calculator_|unitconverter$)/.test(id),
                // KWin's runner: an open window (or a desktop) to switch to
                window: id.startsWith("windows_")
            });
        }
        // KRunner ranks categories by use. Two kinds of result go first
        // whatever it thinks: open windows, always (switching to what is
        // already running comes before starting or searching anything), then
        // answers, which it can leave below three browser history entries
        // that happen to contain "2+3*4".
        const rest = list.filter(match => !match.window && !match.answer);
        matches = list.filter(match => match.window).concat(list.filter(match => match.answer && !match.window), rest);
        fresh = true;
    }

    Milou.ResultsModel {
        id: model

        limit: 24
        queryString: root.query

        onRowsInserted: root.changed()
        onRowsRemoved: root.changed()
        onRowsMoved: root.changed()
        onModelReset: root.changed()
        onLayoutChanged: root.changed()
        onDataChanged: root.changed()
        onQueryingChanged: {
            if (!querying)
                root.changed();
        }
        onQueryStringChangeRequested: (queryString, pos) => root.queryRequested(queryString)
    }
}
