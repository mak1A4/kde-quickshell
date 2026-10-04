#!/bin/sh
# Klipper's clipboard history, for the command palette. Klipper (part of
# plasmashell) stays the only one that records and stores it; this reads its
# store and puts an entry back on the clipboard.
#
#   clipboard.sh list [<word>...]
#       The history as JSON, most recently used first; with words, only the
#       text entries containing all of them. Per entry: uuid, a preview of
#       the text, its length and number of lines, the time it was last used,
#       and for an image the file it is stored in.
#   clipboard.sh copy <uuid>
#       Puts that entry on the clipboard again. Klipper notices and moves it
#       to the top of its history.
#
# The store (Plasma 6): history3.sqlite with one row per entry (`main`) and
# one per MIME type it was offered as (`aux`), and each type's bytes in a
# file, data/<uuid>/<data_uuid>. Opened read-only; Klipper has it open too.

store="${XDG_DATA_HOME:-$HOME/.local/share}/klipper"
db="file:$store/history3.sqlite?mode=ro"

sql() {
    sqlite3 -readonly "$@"
}

list() {
    where="1"
    for word; do
        # for a quoted SQL string, and as plain text inside LIKE
        quoted=$(printf %s "$word" | sed "s/'/''/g; s/[\\\\%_]/\\\\&/g")
        # images have no text; "image" and the like find them
        where="$where AND (m.text LIKE '%$quoted%' ESCAPE '\\' OR (m.mimetypes LIKE 'image/%' AND 'image picture png screenshot' LIKE '%$quoted%' ESCAPE '\\'))"
    done
    sql -json "$db" "
        SELECT m.uuid,
               substr(m.text, 1, 300) AS text,
               coalesce(length(m.text), 0) AS length,
               coalesce(length(rtrim(m.text, char(10))) - length(replace(rtrim(m.text, char(10)), char(10), '')) + 1, 0) AS lines,
               coalesce(m.last_used_time, m.added_time) AS time,
               (SELECT m.uuid || '/' || a.data_uuid FROM aux a WHERE a.uuid = m.uuid AND a.mimetype = 'image/png') AS image
        FROM main m
        WHERE $where AND (coalesce(m.text, '') <> '' OR m.mimetypes LIKE '%image/png%')
        ORDER BY time DESC
        LIMIT 200" | sed "s|\"image\":\"|&$store/data/|"
}

# An image as PNG, anything else as its plain text: the bytes Klipper stored.
copy() {
    case $1 in *[!0-9a-f]*|"") echo "clipboard.sh: not an entry: $1" >&2; exit 2 ;; esac
    for type in image/png "text/plain;charset=utf-8" text/plain; do
        file=$(sql "$db" "SELECT data_uuid FROM aux WHERE uuid = '$1' AND mimetype = '$type'")
        if [ -n "$file" ] && [ -f "$store/data/$1/$file" ]; then
            wl-copy --type "$type" < "$store/data/$1/$file"
            return
        fi
    done
    echo "clipboard.sh: nothing to copy for $1" >&2
    exit 1
}

command=$1; shift
case $command in
    list) list "$@" ;;
    copy) copy "$@" ;;
    *) echo "clipboard.sh: unknown command '$command'" >&2; exit 2 ;;
esac
