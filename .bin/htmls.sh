#!/usr/bin/env bash

current_dir="${1:-$(pwd)}"

while true; do
    entries=()

    # Add .. if not root
    if [ "$current_dir" != "/" ]; then
        entries+=("..")
    fi

    # Add directories
    while IFS= read -r dir; do
        entries+=("${dir##*/}/")
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d)

    # Add HTML files
    while IFS= read -r html; do
        entries+=("${html##*/}")
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -iname "*.html" -o -iname "*.htm")

    if [ ${#entries[@]} -eq 0 ]; then
        echo "No HTML files or directories here."
        exit 0
    fi

    # Let user pick
    selection=$(printf "%s\n" "${entries[@]}" | fzf --prompt="🌐 $current_dir > " \
        --height=40% --layout=reverse --border --exit-0)

    [ -z "$selection" ] && break

    # Remove trailing slash if present
    sel_path="$current_dir/${selection%/}"

    if [ -d "$sel_path" ]; then
        current_dir="$sel_path"
    elif [ -f "$sel_path" ]; then
        xdg-open "$sel_path"
    else
        echo "Invalid selection."
    fi
done
