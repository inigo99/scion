#!/bin/sh
# Runs Scion's regression tests (tests/cases.txt) under Wine on Linux, from out/tests (tests/build.sh).
# Usage: sh tests/run.sh [FILTER]   FILTER: only the tests whose name contains it. SCION_SKIP: an extended regular
# expression of test names to skip.
# The window and Metal tests need a display (Wine's null driver gives windows no size) and Vulkan: with no DISPLAY,
# an Xvfb is started on :88; Mesa's lavapipe provides software Vulkan (docs/testing.md).
cd "$(dirname "$0")/.." || exit 1
R=$(pwd); SCION=${SCION:-$R/bin/scion.exe}
case $SCION in *.exe) RUN=wine;; *) RUN=;; esac   # SCION=bin/scion: the native Linux host, no Wine
# the native host's `scion install` writes .desktop files: into a scratch folder, not your desktop
[ -n "$RUN" ] || { XDG_DATA_HOME=$(mktemp -d); export XDG_DATA_HOME; }
cd out/tests || { echo "out/tests is missing: run tests/build.sh first"; exit 1; }
export WINEDEBUG=${WINEDEBUG:--all}
if [ -z "$DISPLAY" ]; then
  pgrep -f "Xvfb :88" >/dev/null || (Xvfb :88 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &); sleep 2; export DISPLAY=:88
fi
# a wineserver started without a display would hide the GPU from Vulkan
[ -n "$RUN" ] && { wineserver -k 2>/dev/null; wineserver -w 2>/dev/null; }
# Tests run in parallel, JOBS at a time (default: the number of CPUs); `scion install` and `scion uninstall` run last, in
# order. Each writes its result to $RES/<index>; they are reported in the order of cases.txt.
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}
RES=$(mktemp -d); trap 'rm -rf "$RES"; [ -n "$RUN" ] || rm -rf "$XDG_DATA_HOME"' EXIT
mkfifo "$RES/slots"; exec 3<>"$RES/slots"; rm "$RES/slots"; i=0; while [ $i -lt $JOBS ]; do echo >&3; i=$((i+1)); done   # one token per free slot
run_case() {  # INDEX NAME EXPECTED ENV ARGS -> $RES/INDEX: OK, FAIL (with the end of the output) or SKIP
  c_out=$RES/$1 c_name=$2 c_want=$3 c_env=$4
  [ -n "$SCION_SKIP" ] && echo "$c_name" | grep -qE "$SCION_SKIP" && { echo SKIP > "$c_out"; return; }   # e.g. SCION_SKIP='Metal|MSL'
  eval "set -- $5"   # arguments may be "quoted"
  for c_a in "$@"; do case $c_a in apps/*) [ -e "$c_a" ] || { echo SKIP > "$c_out"; return; };; esac; done
  case $1 in
    install|uninstall) ;;
    *.app) [ -d "$1/Contents/MacOS" ] || { echo SKIP > "$c_out"; return; };;
    *) [ -e "$1" ] || { echo SKIP > "$c_out"; return; };;
  esac
  [ "$c_env" = - ] && c_env=
  got=$(env $c_env timeout 900 $RUN "$SCION" "$@" </dev/null 2>&1)
  case "$got" in
    *"$c_want"*) echo "OK   $c_name" > "$c_out";;
    *) { echo "FAIL $c_name"; echo "$got" | grep -v "^X connection" | tail -5 | sed 's/^/     /'; } > "$c_out";;
  esac
}
trim() { sed 's/^ *//; s/ *$//'; }
n=0
queue() {  # NAME EXPECTED ENV ARGS
  n=$((n+1))
  case $4 in install*|uninstall*) echo "$n|$1|$2|$3|$4" >> "$RES/serial"; return;; esac
  read -r _ <&3
  (run_case $n "$@" 3>&-; echo >&3) &
}
while IFS='|' read -r name want envs args; do
  case $name in ''|'#'*) continue;; esac
  name=$(echo "$name" | trim) want=$(echo "$want" | trim) envs=$(echo "$envs" | trim) args=$(echo "$args" | trim)
  case $name in *"$1"*) ;; *) continue;; esac
  case "$name$envs$args" in
    *'{arch}'*) for a in x86_64 arm64; do
        queue "$(echo "$name" | sed "s/{arch}/$a/g")" "$want" "$(echo "$envs" | sed "s/{arch}/$a/g")" "$(echo "$args" | sed "s/{arch}/$a/g")"
      done;;
    *) queue "$name" "$want" "$envs" "$args";;
  esac
done < "$R/tests/cases.txt"
wait
[ -f "$RES/serial" ] && while IFS='|' read -r i name want envs args; do run_case "$i" "$name" "$want" "$envs" "$args" 3>&-; done < "$RES/serial"
pass=0 fail=0 skip=0 i=0
while [ $i -lt $n ]; do
  i=$((i+1))
  case $(head -c 4 "$RES/$i") in OK*) pass=$((pass+1));; FAIL) fail=$((fail+1));; *) skip=$((skip+1)); continue;; esac
  cat "$RES/$i"
done
echo "passed: $pass, failed: $fail, skipped: $skip"
exit $fail
