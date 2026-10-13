#!/bin/sh
# Builds the shell's own Breeze window decoration: Breeze as released, in the
# version of the Plasma installed here, with rounded.patch on it (the corners
# stay on maximized and tiled windows; the radius is the one of
# kwin/roundcorners). The sources are fetched from download.kde.org.
#
#   kwin/breeze/build.sh [directory to build in]
#
# Says where the plugin is at the end. It belongs in the Qt plugin directory
# org.kde.kdecoration3, and is chosen with `library` in the group
# `org.kde.kdecoration2` of kwinrc. To be built again after a Plasma update.
set -e
here=$(cd "$(dirname "$0")" && pwd)
version=${BREEZE_VERSION:-$(kwin_wayland --version | sed 's/[^0-9.]//g')}
work=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/kde-quickshell/breeze}
mkdir -p "$work"
archive=$work/breeze-$version.tar.xz
if [ ! -s "$archive" ]; then
    curl -fsSL -m 120 -o "$archive.part" "https://download.kde.org/stable/plasma/$version/breeze-$version.tar.xz"
    mv "$archive.part" "$archive"
fi
# unpacked over what is there: the patched files are Breeze's own again
tar -xJf "$archive" -C "$work" --overwrite "breeze-$version/kdecoration" "breeze-$version/libbreezecommon"
patch -s -d "$work/breeze-$version" -p1 < "$here/rounded.patch"
cp "$here/breeze.json" "$work/breeze-$version/kdecoration/breeze.json"
cmake -S "$here" -B "$work/build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBREEZE_SOURCE_DIR="$work/breeze-$version" > "$work/cmake.log" 2>&1 || {
    cat "$work/cmake.log" >&2
    exit 1
}
cmake --build "$work/build"
echo "$work/build/bin/org.kde.kdecoration3/io.github.mak1a4.kde-quickshell.breeze.so"
