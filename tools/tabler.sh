#!/bin/sh
# Fetches the Tabler icons the shell uses into shell/icons/tabler, with
# Tabler's licence (MIT). Which ones: every glyph named in
# shell/notifications/glyphs.js. Run it after adding a name there.
#
#   tools/tabler.sh [version]      e.g. tools/tabler.sh 3.48.0
set -e
cd "$(dirname "$0")/.."
version=${1:-3.48.0}
dest=shell/icons/tabler
base=https://cdn.jsdelivr.net/npm/@tabler/icons@$version
mkdir -p "$dest"
# the glyph is the value of an exact entry (`: "name"`) or the second string
# of a prefix pair (`, "name"]`)
names=$(grep -oE '(: |, )"[a-z0-9-]+"(,|\])?' shell/notifications/glyphs.js | grep -oE '"[a-z0-9-]+"' | tr -d '"')
for name in $(printf '%s\n' $names bell | sort -u); do
    [ -f "$dest/$name.svg" ] && continue
    if curl -fsSL -m 20 -o "$dest/$name.svg.part" "$base/icons/outline/$name.svg" && grep -q '<svg' "$dest/$name.svg.part"; then
        mv "$dest/$name.svg.part" "$dest/$name.svg"
        echo "fetched $name"
    else
        rm -f "$dest/$name.svg.part"
    fi
done
curl -fsSL -m 20 -o "$dest/LICENSE" "$base/LICENSE"
echo "$version" > "$dest/VERSION"
