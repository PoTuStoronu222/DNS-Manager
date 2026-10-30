#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^publish_versioned_assets\(\) \{/,/^}/' dns-manager-luci.sh > "$tmp/publish.sh"
[ -s "$tmp/publish.sh" ] || exit 1
. "$tmp/publish.sh"
err() { printf '%s\n' "$*" >&2; }
VIEW_DIR="$tmp/views"; RESOURCE_DIR="$tmp/resources"; COMMON_FILE="$RESOURCE_DIR/common.js"
MENU_FILE="$tmp/menu.json"; _menu_stage="$tmp/menu.stage"; ASSET_VERSION=v2_14
mkdir -p "$VIEW_DIR" "$RESOURCE_DIR"
printf '%s\n' 'common first' > "$COMMON_FILE"
for page in dashboard doh slots devices network time catalog log; do
    printf '%s\n' "'require dns-manager.common as DM';" "// $page" > "$VIEW_DIR/$page.js"
done
make_menu() {
    : > "$_menu_stage"
    for page in dashboard doh slots devices network time catalog log; do
        printf '"path": "dns-manager/%s"\n' "$page" >> "$_menu_stage"
    done
}
asset_id() { sed -n 's|.*"path": "dns-manager/\(v[0-9a-f_]*\)/dashboard".*|\1|p' "$MENU_FILE"; }
make_menu; publish_versioned_assets
first="$(asset_id)"; [ -n "$first" ]
[ -f "$RESOURCE_DIR/$first/common.js" ]
for page in dashboard doh slots devices network time catalog log; do
    grep -Fq "'require dns-manager.$first.common as DM';" "$VIEW_DIR/$first/$page.js"
    grep -Fq "\"path\": \"dns-manager/$first/$page\"" "$MENU_FILE"
done
# An update with the same version but changed code also gets a new URL.
printf '%s\n' 'common second' > "$COMMON_FILE"
make_menu; publish_versioned_assets
second="$(asset_id)"; [ "$first" != "$second" ]
[ -f "$RESOURCE_DIR/$first/common.js" ] && [ -f "$VIEW_DIR/$first/dashboard.js" ]
# Failure to publish a page must not switch the menu.
rm -f "$VIEW_DIR/log.js"
make_menu
if publish_versioned_assets 2>/dev/null; then exit 1; fi
[ "$(asset_id)" = "$second" ]
printf '%s\n' "'require dns-manager.common as DM';" '// log' > "$VIEW_DIR/log.js"
printf '%s\n' 'common third' > "$COMMON_FILE"
make_menu; publish_versioned_assets
third="$(asset_id)"; [ "$second" != "$third" ]
[ -f "$RESOURCE_DIR/$second/common.js" ] && [ ! -e "$RESOURCE_DIR/$first" ]
[ -f "$VIEW_DIR/$second/dashboard.js" ] && [ ! -e "$VIEW_DIR/$first" ]
printf '%s\n' '// changed log view' >> "$VIEW_DIR/log.js"
make_menu; publish_versioned_assets
fourth="$(asset_id)"; [ "$third" != "$fourth" ]
[ -f "$VIEW_DIR/$third/log.js" ] && [ -f "$VIEW_DIR/$fourth/log.js" ]
# Upgrade from 2.14: both the view URL and its dependency URL must change,
# even when an old browser response for every old URL remains cached.
ASSET_VERSION=v2_15
printf '%s\n' 'common for next release' > "$COMMON_FILE"
make_menu; publish_versioned_assets
fifth="$(asset_id)"; [ "$fourth" != "$fifth" ]
case "$fourth:$fifth" in v2_14_*:v2_15_*) ;; *) exit 1;; esac
for page in dashboard doh slots devices network time catalog log; do
    grep -Fq "\"path\": \"dns-manager/$fifth/$page\"" "$MENU_FILE"
    grep -Fq "'require dns-manager.$fifth.common as DM';" "$VIEW_DIR/$fifth/$page.js"
done
grep -Fxq 'common third' "$RESOURCE_DIR/$fourth/common.js"
grep -Fxq 'common for next release' "$RESOURCE_DIR/$fifth/common.js"
printf '%s\n' 'OK: versioned LuCI assets, safe publication and cleanup'
