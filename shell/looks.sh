#!/bin/sh
# Lists the looks the theme switcher offers: every theme with each of its
# backgrounds, and a theme without a background once, by itself.
#
#   looks.sh <shell's themes directory> <user's themes directory> <cache directory>
#
# Prints a JSON list of { theme, file, path, thumb, colors }: `colors` as the
# theme's file gives them (the user's file of a name before the shell's),
# `thumb` a small picture of the background, made here with ffmpeg if it is
# not there yet or older than the background (a video's is its frame two
# seconds in). So the first run takes a while, and the list comes when the
# pictures are there.

bundled=$1
own=$2
cache=$3
mkdir -p "$cache"

{
    for file in "$bundled"/*.json "$own"/*.json; do
        [ -f "$file" ] && basename "$file" .json
    done
} | sort -u | while read -r theme; do
    source="$own/$theme.json"
    [ -f "$source" ] || source="$bundled/$theme.json"
    colors=$(jq -c '.colors // {}' "$source" 2> /dev/null) || colors='{}'
    [ -n "$colors" ] || colors='{}'

    found=
    for path in "$own/backgrounds/$theme"/*; do
        [ -f "$path" ] || continue
        case "$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')" in
            *.png | *.jpg | *.jpeg | *.webp | *.gif) seek= ;;
            *.mp4 | *.webm | *.mkv | *.mov) seek="-ss 2" ;;
            *) continue ;;
        esac
        found=1
        name=$(basename "$path")
        thumb="$cache/$theme-${name%.*}.jpg"
        if [ ! -s "$thumb" ] || [ "$path" -nt "$thumb" ]; then
            # shellcheck disable=SC2086
            ffmpeg -v error -y $seek -i "$path" -frames:v 1 \
                -vf 'scale=640:360:force_original_aspect_ratio=increase,crop=640:360' "$thumb.new.jpg" < /dev/null &&
                mv "$thumb.new.jpg" "$thumb"
        fi
        jq -c -n --arg theme "$theme" --arg file "$name" --arg path "$path" --arg thumb "$thumb" --argjson colors "$colors" \
            '{theme: $theme, file: $file, path: $path, thumb: $thumb, colors: $colors}'
    done
    [ -n "$found" ] || jq -c -n --arg theme "$theme" --argjson colors "$colors" \
        '{theme: $theme, file: "", path: "", thumb: "", colors: $colors}'
done | jq -c -s .
