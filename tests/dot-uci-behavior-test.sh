#!/bin/sh
# Optional real-UCI experiment; all configuration and delta paths are temporary.
set -eu
uci_bin="${DOT_UCI_LAUNCHER:-uci}"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
mkdir "$t/conf" "$t/ext" "$t/ours"
reset_fixture() {
    rm -f "$t/ext/dotlab" "$t/ours/dotlab"
    cat > "$t/conf/dotlab" <<'EOF'
config state 'main'
    option selected 'old'
    option other 'initial'
EOF
}
u() { "$uci_bin" -c "$t/conf" "$@"; }
reset_fixture
u -t "$t/ext" set dotlab.main.other=external_pending
u -p "$t/ext" -t "$t/ours" set dotlab.main.selected=new
u -p "$t/ext" -t "$t/ours" commit dotlab
[ "$(u -t "$t/ours" get dotlab.main.other)" = external_pending ] && [ -s "$t/ext/dotlab" ] || { echo 'Unexpected UCI delta behavior' >&2; exit 1; }
reset_fixture
u -t "$t/ours" set dotlab.main.selected=new
u -t "$t/ext" set dotlab.main.other=external_committed
u -t "$t/ext" commit dotlab
u -t "$t/ours" commit dotlab
[ "$(u -t "$t/ours" get dotlab.main.other)" = external_committed ] || { echo 'Concurrent unrelated commit was lost' >&2; exit 1; }
reset_fixture
u -t "$t/ours" set dotlab.main.selected=new
u -t "$t/ext" set dotlab.main.selected=external
u -t "$t/ext" commit dotlab
u -t "$t/ours" commit dotlab
[ "$(u -t "$t/ours" get dotlab.main.selected)" = new ] || { echo 'Unexpected same-key conflict behavior' >&2; exit 1; }
echo 'OK: real UCI delta experiment confirmed pending-delta import and same-key last-writer behavior'
