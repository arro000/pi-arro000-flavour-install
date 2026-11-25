#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
node_bin=$(command -v node)
export MOCK_NODE="$work/bin/node" HOME="$work/home" PI_CODING_AGENT_DIR="$work/home/.pi/agent" TERM=dumb
export FNM_DIR="$work/fnm" PATH="$work/bin:/usr/bin:/bin"
export PI_MANAGED_INSTALL_ROOT="$work/other-install"
mkdir -p "$work/bin" "$PI_CODING_AGENT_DIR"
ln -s "$node_bin" "$MOCK_NODE"
printf '%s\n' '{"theme":"old","packages":["keep"],"custom":true}' > "$PI_CODING_AGENT_DIR/settings.json"
printf '%s\n' '{"toolView":{"mode":"native","custom":true}}' > "$PI_CODING_AGENT_DIR/open-tui.json"

cat > "$work/bin/curl" <<'MOCK'
#!/bin/sh
set -eu
[ "$3" = -o ] || exit 90
case "$2" in
https://fnm.vercel.app/install)
cat > "$4" <<'INSTALLER'
set -eu
[ "$*" = "--install-dir $FNM_DIR --skip-shell --force-no-brew" ]
mkdir -p "$FNM_DIR"
cat > "$FNM_DIR/fnm" <<'FNM'
#!/bin/sh
case "$*" in
'list-remote') printf '%s\n' 'v24.1.0 (Example)' 'v26.13.0' 'v27.0.0-alpha.1' ;;
'install v26.13.0') echo node-install >> "$HOME/actions" ;;
'default v26.13.0') echo node-default >> "$HOME/actions" ;;
'exec --using=default node -p process.execPath') echo "$MOCK_NODE" ;;
*) exit 93 ;;
esac
FNM
chmod +x "$FNM_DIR/fnm"
INSTALLER
;;
https://pi.dev/install.sh)
cat > "$4" <<'INSTALLER'
set -eu
if ( : </dev/tty ) 2>/dev/null; then exit 92; fi
[ -z "${PI_MANAGED_INSTALL_ROOT:-}" ]
[ "$(tail -n 1 "$HOME/actions")" = node-default ]
printf 'installer\n' >> "$HOME/actions"
mkdir -p "$PI_CODING_AGENT_DIR/bin" "$PI_CODING_AGENT_DIR/install"
: > "$PI_CODING_AGENT_DIR/install/managed-install.json"
cat > "$PI_CODING_AGENT_DIR/bin/pi" <<'PI'
#!/bin/sh
if ( : </dev/tty ) 2>/dev/null; then exit 92; fi
if [ "$1" = --version ]; then echo 9.8.7; exit; fi
if [ "$*" = 'update --self --no-approve' ]; then
  printf 'update\n' >> "$HOME/actions"
  exit
fi
[ "$1" = install ] && [ "$3" = --no-approve ] || exit 91
printf '%s\n' "$2" >> "$HOME/packages"
[ "$2" != "${FAIL_PACKAGE:-}" ] || exit 42
PI
chmod +x "$PI_CODING_AGENT_DIR/bin/pi"
INSTALLER
;;
*) exit 90 ;;
esac
MOCK
chmod +x "$work/bin/curl"

# npm's bin points to the Bash bootstrap through a symlink.
ln -s "$PWD/install.sh" "$work/bin/pi-arro000-flavour-install"
pi-arro000-flavour-install > "$work/log" 2>&1 || { cat "$work/log"; exit 1; }
grep -Fq '[100%] Pi and 21 packages ready.' "$work/log"
[[ $(cat "$HOME/actions") == $'node-install\nnode-default\ninstaller' ]]
[[ $(sort -u "$HOME/packages" | wc -l) -eq 21 ]]
"$node_bin" --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { torus } from './torus.mjs';
const read = file => JSON.parse(readFileSync(`${process.env.PI_CODING_AGENT_DIR}/${file}`));
const pi = read('settings.json');
assert.equal(pi.theme, 'monokai-contrast');
assert.deepEqual(pi.packages, ['keep']);
assert.equal(pi.custom, true);
assert.equal(read('open-tui.json').toolView.mode, 'compact');
assert.equal(read('open-tui.json').toolView.custom, true);
assert.match(torus(0, 0).join(''), /\./);
assert.doesNotMatch(torus(0, 1).join(''), /\./);
assert.notDeepEqual(torus(0, 1), torus(1, 1));
JS
rm "$HOME/packages"
bash install.sh > "$work/log" 2>&1
[[ $(tail -n 3 "$HOME/actions") == $'node-install\nnode-default\nupdate' ]]
[[ $(wc -l < "$HOME/packages") -eq 21 ]]
rm "$HOME/packages"
status=0
FAIL_PACKAGE=npm:pi-goal-x bash install.sh > "$work/log" 2>&1 || status=$?
[[ $status -eq 42 && $(wc -l < "$HOME/packages") -eq 2 ]]
! grep -Fq '100%' "$work/log"
printf '%s\n' 'not JSON' > "$PI_CODING_AGENT_DIR/open-tui.json"
status=0
bash install.sh > "$work/log" 2>&1 || status=$?
[[ $status -eq 1 && $(tail -n 1 "$HOME/actions") == node-default ]]
grep -Fxq 'not JSON' "$PI_CODING_AGENT_DIR/open-tui.json"
printf 'Installer tests passed.\n'
