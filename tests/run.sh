#!/bin/sh
# Runs Scion's regression tests (tests/cases.txt) under Wine on Linux, from out/tests (tests/build.sh).
# Usage: sh tests/run.sh [FILTER]   FILTER: only the tests whose name contains it. SCION_SKIP: an extended regular
# expression of test names to skip.
# The window and Metal tests need a display (Wine's null driver gives windows no size) and Vulkan: with no DISPLAY,
# an Xvfb is started on :88; Mesa's lavapipe provides software Vulkan (docs/testing.md).
cd "$(dirname "$0")/.." || exit 1
R=$(pwd); SCION=${SCION:-$R/bin/scion.exe}
case $SCION in *.exe) RUN=wine;; *) RUN=;; esac   # SCION=bin-linux/scion: the native Linux host (#10), no Wine
cd out/tests || { echo "out/tests is missing: run tests/build.sh first"; exit 1; }
export WINEDEBUG=${WINEDEBUG:--all}
if [ -z "$DISPLAY" ]; then
  pgrep -f "Xvfb :88" >/dev/null || (Xvfb :88 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &); sleep 2; export DISPLAY=:88
fi
# a wineserver started without a display would hide the GPU from Vulkan
[ -n "$RUN" ] && { wineserver -k 2>/dev/null; wineserver -w 2>/dev/null; }
pass=0 fail=0 skip=0
run_case() {  # NAME EXPECTED ENV ARGS (its variables are global in sh: c_* keeps them apart from the loop's)
  c_name=$1 c_want=$2 c_env=$3
  [ -n "$SCION_SKIP" ] && echo "$c_name" | grep -qE "$SCION_SKIP" && { skip=$((skip+1)); return; }   # e.g. SCION_SKIP='Metal|MSL'
  eval "set -- $4"   # arguments may be "quoted"
  for c_a in "$@"; do case $c_a in apps/*) [ -e "$c_a" ] || { skip=$((skip+1)); return; };; esac; done
  case $1 in
    install|uninstall) ;;
    *.app) [ -d "$1/Contents/MacOS" ] || { skip=$((skip+1)); return; };;
    *) [ -e "$1" ] || { skip=$((skip+1)); return; };;
  esac
  [ "$c_env" = - ] && c_env=
  got=$(env $c_env timeout 900 $RUN "$SCION" "$@" </dev/null 2>&1)
  case "$got" in
    *"$c_want"*) echo "OK   $c_name"; pass=$((pass+1));;
    *) echo "FAIL $c_name"; echo "$got" | grep -v "^X connection" | tail -5 | sed 's/^/     /'; fail=$((fail+1));;
  esac
}
trim() { sed 's/^ *//; s/ *$//'; }
while IFS='|' read -r name want envs args; do
  case $name in ''|'#'*) continue;; esac
  name=$(echo "$name" | trim) want=$(echo "$want" | trim) envs=$(echo "$envs" | trim) args=$(echo "$args" | trim)
  case $name in *"$1"*) ;; *) continue;; esac
  case "$name$envs$args" in
    *'{arch}'*) for a in x86_64 arm64; do
        run_case "$(echo "$name" | sed "s/{arch}/$a/g")" "$want" "$(echo "$envs" | sed "s/{arch}/$a/g")" "$(echo "$args" | sed "s/{arch}/$a/g")"
      done;;
    *) run_case "$name" "$want" "$envs" "$args";;
  esac
done < "$R/tests/cases.txt"
echo "passed: $pass, failed: $fail, skipped: $skip"
exit $fail
