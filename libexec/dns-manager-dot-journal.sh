#!/bin/sh
# Experimental guarded, single-file journal. The caller must hold its mutation
# lock and arrange for recovery at boot. This does not manage UCI or services.
set -eu
action="${1:-}"; journal="${2:-}"
case "$journal" in */dns-manager-dot-journal) ;; *) echo 'Invalid journal path' >&2; exit 1;; esac
case "$action" in
    prepare)
        target="${3:-}"; intended="${4:-}"
        case "$target" in /*) ;; *) echo 'Target must be absolute' >&2; exit 1;; esac
        [ -f "$target" ] && [ ! -L "$target" ] && [ -f "$intended" ] && [ ! -L "$intended" ] || { echo 'Target or intended file unavailable' >&2; exit 1; }
        [ ! -e "$journal" ] && [ ! -L "$journal" ] || { echo 'Journal already exists' >&2; exit 1; }
        parent="$(dirname "$journal")"; [ -d "$parent" ] || exit 1
        umask 077
        stage="$(mktemp -d "$parent/.dot-journal.XXXXXX")" || exit 1
        trap 'rm -rf "$stage"' EXIT HUP INT TERM
        cp -p "$target" "$stage/before" && cp "$intended" "$stage/after" || exit 1
        printf '%s\n' 'DNS_MANAGER_DOT_JOURNAL=1' > "$stage/marker" || exit 1
        printf '%s\n' "$target" > "$stage/target" || exit 1
        [ ! -e "$journal" ] && [ ! -L "$journal" ] || exit 1
        mv "$stage" "$journal" || exit 1
        trap - EXIT HUP INT TERM
        ;;
    apply|recover|finish)
        [ -d "$journal" ] && [ ! -L "$journal" ] && [ -f "$journal/before" ] && [ ! -L "$journal/before" ] && [ -f "$journal/after" ] && [ ! -L "$journal/after" ] && [ -f "$journal/target" ] && [ ! -L "$journal/target" ] && [ -f "$journal/marker" ] && [ ! -L "$journal/marker" ] && grep -Fxq 'DNS_MANAGER_DOT_JOURNAL=1' "$journal/marker" || { echo 'Incomplete DoT journal' >&2; exit 1; }
        target="$(cat "$journal/target")"
        case "$target" in /*) ;; *) exit 1;; esac
        [ -f "$target" ] && [ ! -L "$target" ] || { echo 'Target unavailable; journal retained' >&2; exit 1; }
        if [ "$action" = finish ]; then
            cmp -s "$target" "$journal/after" || { echo 'Target changed; journal retained' >&2; exit 1; }
            rm -rf "$journal"
            exit 0
        fi
        if [ "$action" = apply ]; then
            cmp -s "$target" "$journal/before" || { echo 'Target changed before apply; journal retained' >&2; exit 1; }
            source="$journal/after"; expected="$journal/before"
        else
            if cmp -s "$target" "$journal/before"; then rm -rf "$journal"; exit 0; fi
            cmp -s "$target" "$journal/after" || { echo 'Target changed externally; journal retained' >&2; exit 1; }
            source="$journal/before"; expected="$journal/after"
        fi
        umask 077
        stage="$(mktemp "$target.dot.XXXXXX")" || exit 1
        trap 'rm -f "$stage"' EXIT HUP INT TERM
        cp -p "$source" "$stage" || exit 1
        cmp -s "$target" "$expected" || { echo 'Target changed during operation; journal retained' >&2; exit 1; }
        mv -f "$stage" "$target" || exit 1
        trap - EXIT HUP INT TERM
        [ "$action" != recover ] || rm -rf "$journal"
        ;;
    *) echo 'Invalid journal action' >&2; exit 1;;
esac
