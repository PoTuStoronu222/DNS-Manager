#!/bin/sh
set -eu
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
awk '/^ensure_dnssec_dependencies\(\) \{/,/^}/' dns-manager.sh > "$t/function"
. "$t/function"
CFG_DIR="$t/config"; PACKAGE_OWNERSHIP="$CFG_DIR/owned"; PKG_MGR=apk
HAVE_DIG=1; HAVE_OD=1; UPDATE_FAIL=0; ADD_FAIL=0; updates=0; installs=''; discovered=0
command() { case "$1:$2" in -v:dig) [ "$HAVE_DIG" = 1 ];; -v:od) [ "$HAVE_OD" = 1 ];; *) return 1;; esac; }
od() { return "${OD_FAIL:-0}"; }
warn_msg() { :; }; run_discovery() { discovered=$((discovered+1)); }
package_is_installed() { case " $installs " in *" $1 "*) return 0;; *) return 1;; esac; }
apk() {
    case "$1" in
        update) updates=$((updates+1)); [ "$UPDATE_FAIL" = 0 ];;
        add) [ "$ADD_FAIL" = 0 ] || return 1; installs="$installs $2"; case "$2" in bind-dig) HAVE_DIG=1;; coreutils-od) HAVE_OD=1;; esac;;
        *) return 1;;
    esac
}
opkg() { if [ "$1" = install ]; then apk add "$2"; else apk "$@"; fi; }
ensure_dnssec_dependencies >/dev/null || exit 1
[ "$updates" = 0 ] && [ -z "$installs" ] || { echo 'FAIL: installed packages when tools already present' >&2; exit 1; }
HAVE_DIG=0; HAVE_OD=0; ensure_dnssec_dependencies >/dev/null || exit 1
[ "$HAVE_DIG:$HAVE_OD:$updates" = '1:1:1' ] && grep -qx bind-dig "$PACKAGE_OWNERSHIP" && grep -qx coreutils-od "$PACKAGE_OWNERSHIP" || { echo 'FAIL: missing tools not installed and recorded' >&2; exit 1; }
PKG_MGR=opkg; HAVE_OD=0; ensure_dnssec_dependencies >/dev/null || { echo 'FAIL: opkg installation' >&2; exit 1; }; PKG_MGR=apk
HAVE_OD=0; UPDATE_FAIL=1; if ensure_dnssec_dependencies >/dev/null; then echo 'FAIL: failed package update accepted' >&2; exit 1; fi
UPDATE_FAIL=0; ADD_FAIL=1; if ensure_dnssec_dependencies >/dev/null; then echo 'FAIL: failed package install accepted' >&2; exit 1; fi
HAVE_OD=1; ADD_FAIL=0; OD_FAIL=1; if ensure_dnssec_dependencies >/dev/null; then echo 'FAIL: incompatible od accepted' >&2; exit 1; fi
echo 'OK: DNSSEC dependencies are installed only if missing and failures stop before DNS changes'
