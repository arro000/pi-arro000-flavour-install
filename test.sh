#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home" PI_CODING_AGENT_DIR="$work/home/.pi/agent" TERM=dumb
export PATH="$work/bin:$PATH"
mkdir -p "$work/bin"

cat > "$work/bin/curl" <<'MOCK'
#!/bin/sh
[ "$2" = https://pi.dev/install.sh ] && [ "$3" = -o ] || exit 90
cat > "$4" <<'INSTALLER'
set -eu
mkdir -p "$PI_CODING_AGENT_DIR/bin"
cat > "$PI_CODING_AGENT_DIR/bin/pi" <<'PI'
#!/bin/sh
if [ "$1" = --version ]; then echo 9.8.7; exit; fi
[ "$1" = install ] && [ "$3" = --no-approve ] || exit 91
printf '%s\n' "$2" >> "$HOME/packages"
[ "$2" != "${FAIL_PACKAGE:-}" ] || exit 42
PI
chmod +x "$PI_CODING_AGENT_DIR/bin/pi"
INSTALLER
MOCK
chmod +x "$work/bin/curl"

bash install.sh > "$work/log" 2>&1
grep -Fq '[23/23 - 100%] Pi 9.8.7 e 21 pacchetti installati.' "$work/log"
[[ $(wc -l < "$HOME/packages") -eq 21 ]]
[[ $(sort -u "$HOME/packages" | wc -l) -eq 21 ]]
grep -Fxq 'npm:@arro000/pi-monokai-contrast' "$HOME/packages"

rm "$HOME/packages"
status=0
FAIL_PACKAGE=npm:pi-goal-x bash install.sh > "$work/log" 2>&1 || status=$?
[[ $status -eq 42 && $(wc -l < "$HOME/packages") -eq 2 ]]
! grep -Fq '100%' "$work/log"
printf 'Test superati.\n'
