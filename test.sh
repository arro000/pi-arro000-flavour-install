#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
node_bin=$(command -v node)
export MOCK_NODE="$work/bin/node" HOME="$work/home" PI_CODING_AGENT_DIR="$work/home/.pi/agent" TERM=dumb
export FNM_DIR="$work/fnm" PATH="$work/bin:$HOME/.local/bin:/usr/bin:/bin"
export PI_MANAGED_INSTALL_ROOT="$work/other-install"
mkdir -p "$work/bin" "$PI_CODING_AGENT_DIR"
ln -s "$node_bin" "$MOCK_NODE"
printf '%s\n' '{"theme":"old","packages":["keep"],"custom":true}' > "$PI_CODING_AGENT_DIR/settings.json"
printf '%s\n' '{"toolView":{"mode":"native","custom":true}}' > "$PI_CODING_AGENT_DIR/open-tui.json"

# Publish a small fake release to the installer process and verify the archive path.
mkdir "$work/rtk-asset"
printf '#!/bin/sh\necho rtk 1.2.3\n' > "$work/rtk-asset/rtk"
tar -czf "$work/rtk.tar.gz" -C "$work/rtk-asset" rtk
export RTK_FIXTURE="$work/rtk.tar.gz"
cat > "$work/fetch-mock.mjs" <<'MOCK'
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const base = 'https://github.com/rtk-ai/rtk/releases';
const tag = 'v1.2.3';
const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
const target = process.platform === 'darwin' ? 'apple-darwin' : 'unknown-linux-musl';
const asset = `rtk-oss-${arch}-${target}.tar.gz`;
const bytes = readFileSync(process.env.RTK_FIXTURE);
globalThis.fetch = async url => {
  if (url === `${base}/latest`) return new Response(null, { status: 302, headers: { location: `${base}/tag/${tag}` } });
  if (url === `${base}/download/${tag}/checksums.txt`) return new Response(`${createHash('sha256').update(bytes).digest('hex')}  ${asset}\n`);
  assert.equal(url, `${base}/download/${tag}/${asset}`);
  return new Response(bytes);
};
MOCK
export NODE_OPTIONS="--import=$work/fetch-mock.mjs"

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
'exec --using=default node -p process.execPath')
  if [ "${FAIL_NODE:-}" ] && [ ! -f "$HOME/libatomic-installed" ]; then
    echo 'libatomic.so.1: cannot open shared object file' >&2
    exit 127
  fi
  echo "$MOCK_NODE" ;;
exec\ --using=default\ *)
  shift 2
  if [ "$1" = node ]; then shift; exec "$MOCK_NODE" "$@"; fi
  exec "$@" ;;
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
if [ "$1" = remove ]; then printf '%s\n' "$2" >> "$HOME/removed"; exit; fi
{ [ "$1" = install ] || [ "$1" = update ]; } && [ "$3" = --no-approve ] || exit 91
[ "$(rtk --version)" = 'rtk 1.2.3' ]
printf '%s %s\n' "$1" "$2" >> "$HOME/packages"
[ "$2" != "${FAIL_PACKAGE:-}" ] || exit 42
PI
chmod +x "$PI_CODING_AGENT_DIR/bin/pi"
INSTALLER
;;
*) exit 90 ;;
esac
MOCK
chmod +x "$work/bin/curl"

# npm's bin points to the Node launcher through a symlink.
ln -s "$PWD/launch.mjs" "$work/bin/pi-arro000-flavour-install"
pi-arro000-flavour-install > "$work/log" 2>&1 || { cat "$work/log"; exit 1; }
grep -Fq '[100%] Pi and 22 packages ready.' "$work/log"
[[ $(cat "$HOME/actions") == $'node-install\nnode-default\ninstaller' ]]
[[ $(sort -u "$HOME/packages" | wc -l) -eq 22 ]]
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
assert.deepEqual(read('extensions/pi-rtk-optimizer/config.json'), JSON.parse(readFileSync('rtk-settings.json')));
assert.match(torus(0, 0).join(''), /\./);
assert.doesNotMatch(torus(0, 1).join(''), /\./);
assert.notDeepEqual(torus(0, 1), torus(1, 1));
JS
# Seed configured entries with a mix of plain and filtered, pinned sources.
"$node_bin" --input-type=module <<'JS'
import { readFileSync, writeFileSync } from 'node:fs';
const dir = process.env.PI_CODING_AGENT_DIR;
const path = `${dir}/settings.json`;
const settings = JSON.parse(readFileSync(path));
settings.theme = 'my-theme';
settings.packages = JSON.parse(readFileSync('packages.json')).filter(source => source !== 'npm:pi-intercom');
settings.packages[0] = { source: `${settings.packages[0]}@1.2.3`, extensions: [] };
writeFileSync(path, JSON.stringify(settings));
writeFileSync(`${dir}/open-tui.json`, '{"header":true}');
JS
rtk_config="$PI_CODING_AGENT_DIR/extensions/pi-rtk-optimizer/config.json"
printf '%s\n' '{"mode":"rewrite","outputCompaction":{"compactGitOutput":true,"custom":true}}' > "$rtk_config"
cp "$rtk_config" "$work/rtk-before"
cp "$PI_CODING_AGENT_DIR/settings.json" "$work/pi-before"
cp "$PI_CODING_AGENT_DIR/open-tui.json" "$work/tui-before"
rm "$HOME/packages"
bash install.sh > "$work/log" 2>&1
[[ $(tail -n 3 "$HOME/actions") == $'node-install\nnode-default\nupdate' ]]
[[ $(grep -c '^update ' "$HOME/packages") -eq 21 ]]
grep -Fxq 'update npm:@aliou/pi-guardrails@1.2.3' "$HOME/packages"
grep -Fxq 'install npm:pi-intercom' "$HOME/packages"
[[ $(grep -c '^install ' "$HOME/packages") -eq 1 ]]
cmp "$work/pi-before" "$PI_CODING_AGENT_DIR/settings.json"
cmp "$work/tui-before" "$PI_CODING_AGENT_DIR/open-tui.json"
cmp "$rtk_config" "$work/rtk-before"

# Simulate TTY detection while feeding answers through a pipe.
cat > "$work/tty-mock.mjs" <<'MOCK'
Object.defineProperty(process.stdin, 'isTTY', { value: true });
Object.defineProperty(process.stderr, 'isTTY', { value: true });
MOCK
for answer in '' yes; do
  printf '%s\n' "$answer" | NODE_OPTIONS="$NODE_OPTIONS --import=$work/tty-mock.mjs" bash install.sh > "$work/log" 2>&1
  grep -Fq 'Apply the bundled RTK and Open TUI presets?' "$work/log"
  cmp "$work/pi-before" "$PI_CODING_AGENT_DIR/settings.json"
  if [[ -z $answer ]]; then
    cmp "$work/tui-before" "$PI_CODING_AGENT_DIR/open-tui.json"
    cmp "$work/rtk-before" "$rtk_config"
  fi
done
"$node_bin" --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = file => JSON.parse(readFileSync(`${process.env.PI_CODING_AGENT_DIR}/${file}`));
const rtk = read('extensions/pi-rtk-optimizer/config.json');
assert.equal(rtk.mode, 'suggest');
assert.equal(rtk.outputCompaction.compactGitOutput, false);
assert.equal(rtk.outputCompaction.custom, true);
assert.equal(read('open-tui.json').header, false);
JS
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
if [[ $(uname -s) == Linux ]]; then
  cat > "$work/bin/sudo" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/sudo-actions"
[ -z "${FAIL_SUDO:-}" ] || exit 1
case "$*" in
  'apt-get update') ;;
  'apt-get install -y libatomic1') touch "$HOME/libatomic-installed" ;;
  *) exit 1 ;;
esac
MOCK
  cp "$work/bin/sudo" "$work/bin/apt-get"
  chmod +x "$work/bin/sudo" "$work/bin/apt-get"
  cp "$work/tui-before" "$PI_CODING_AGENT_DIR/open-tui.json"
  if FAIL_NODE=1 FAIL_SUDO=1 bash install.sh > "$work/log" 2>&1; then exit 1; fi
  grep -Fq 'Could not install libatomic1 automatically.' "$work/log"
  : > "$HOME/sudo-actions"
  FAIL_NODE=1 bash install.sh > "$work/log" 2>&1
  grep -Fq 'Installing libatomic1 with sudo' "$work/log"
  grep -Fq '[100%] Pi and 22 packages ready.' "$work/log"
  [[ $(cat "$HOME/sudo-actions") == $'apt-get update\napt-get install -y libatomic1' ]]
fi
[[ $(bash -ic 'command -v pi' 2>/dev/null) == "$PI_CODING_AGENT_DIR/flavour-bin/pi" ]]
grep -Fq 'pi-arro000-flavour' "$HOME/.bashrc"
[[ $(command -v pi) == "$HOME/.local/bin/pi" ]]
[[ $(command -v pi-flavour-uninstall) == "$HOME/.local/bin/pi-flavour-uninstall" ]]
"$PI_CODING_AGENT_DIR/flavour-bin/pi" --version | grep -Fxq 9.8.7
"$PI_CODING_AGENT_DIR/flavour-bin/pi-flavour-uninstall" > "$work/log" 2>&1 || { cat "$work/log"; exit 1; }
[[ $(wc -l < "$HOME/removed") -eq 22 ]]
[[ ! -L $HOME/.local/bin/pi && ! -L $HOME/.local/bin/pi-flavour-uninstall ]]
[[ ! -e $PI_CODING_AGENT_DIR/install && ! -e $PI_CODING_AGENT_DIR/bin/pi ]]
[[ -f $PI_CODING_AGENT_DIR/settings.json && -x $FNM_DIR/fnm ]]
! grep -Fq 'pi-arro000-flavour' "$HOME/.bashrc"
printf 'Installer tests passed.\n'

# Model Termux's pkg + npm layout without installing anything on the host.
export PREFIX="$work/termux" PI_CODING_AGENT_DIR="$work/termux-agent"
mkdir -p "$PREFIX/bin" "$PREFIX/lib/node_modules/npm/bin"
ln -s "$node_bin" "$PREFIX/bin/node"
ln -s /bin/true "$PREFIX/bin/termux-info"
cat > "$PREFIX/bin/pkg" <<'MOCK'
#!/bin/sh
[ "$*" = 'install -y nodejs npm git' ] || exit 1
echo termux-node >> "$HOME/actions"
MOCK
chmod +x "$PREFIX/bin/pkg"
cat > "$PREFIX/lib/node_modules/npm/bin/npm-cli.js" <<'MOCK'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const prefix = path.join(process.env.PI_CODING_AGENT_DIR, 'flavour-pi');
assert.deepEqual(process.argv.slice(2), ['install', '--global', '--prefix', prefix, '--ignore-scripts',
  '--no-fund', '--no-audit', '@earendil-works/pi-coding-agent@latest']);
const cli = path.join(prefix, 'lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js');
fs.mkdirSync(path.dirname(cli), { recursive: true });
fs.writeFileSync(cli, `
const [command, source, approval] = process.argv.slice(2);
if (command === '--version') console.log('9.8.7');
else {
  require('node:assert/strict').deepEqual([command, approval], ['install', '--no-approve']);
  require('node:fs').appendFileSync(process.env.HOME + '/termux-packages', source + '\\n');
}`);
MOCK
bash install.sh > "$work/log" 2>&1 || { cat "$work/log"; exit 1; }
[[ $(tail -n 1 "$HOME/actions") == termux-node ]]
[[ $(wc -l < "$HOME/termux-packages") -eq 22 ]]
grep -Fq 'Run pi (open a new shell if needed)' "$work/log"
printf 'Termux bootstrap test passed.\n'
