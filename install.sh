#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help && $# == 1 ]]; then
  echo 'Usage: pi-arro000-flavour-install (or bash install.sh)'
  exit 0
fi
if [[ $# != 0 ]]; then
  echo 'Unexpected arguments. Use --help for usage.' >&2
  exit 2
fi
if [[ $EUID == 0 || $(uname -s) != Linux && $(uname -s) != Darwin ]]; then
  echo 'Run as a regular user on Linux or macOS.' >&2
  exit 1
fi
command -v curl >/dev/null || { echo 'curl is required.' >&2; exit 1; }

# npm links its bin into .bin; resolve that link before looking for the JS entrypoint.
entry=${BASH_SOURCE[0]}
while [[ -L $entry ]]; do
  target=$(readlink "$entry")
  if [[ $target == /* ]]; then entry=$target; else entry=$(dirname "$entry")/$target; fi
done
dir=$(cd -- "$(dirname -- "$entry")" && pwd -P)

fnm=$(command -v fnm || true)
if [[ -z $fnm ]]; then
  case $(uname -s) in
    Darwin) fnm_dir="$HOME/Library/Application Support/fnm" ;;
    Linux) fnm_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fnm" ;;
  esac
  fnm_dir=${FNM_DIR:-$fnm_dir}
  if [[ -z ${FNM_DIR:-} && ! -x $fnm_dir/fnm && -x $HOME/.fnm/fnm ]]; then fnm_dir="$HOME/.fnm"; fi
  fnm="$fnm_dir/fnm"
  if [[ ! -x $fnm ]]; then
    command -v unzip >/dev/null || { echo 'unzip is required to install fnm.' >&2; exit 1; }
    temp=$(mktemp -d)
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://fnm.vercel.app/install -o "$temp/fnm.sh"
    TMPDIR="$temp" bash "$temp/fnm.sh" --install-dir "$fnm_dir" --skip-shell --force-no-brew </dev/null
    rm -rf -- "$temp"
    trap - EXIT
    [[ -x $fnm ]] || { echo 'fnm installation failed.' >&2; exit 1; }
  fi
fi

version=$("$fnm" list-remote </dev/null | awk '$1 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ { version = $1 } END { print version }')
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Could not resolve the latest Node.js release.' >&2; exit 1; }
"$fnm" install "$version" </dev/null
"$fnm" default "$version" </dev/null
node_bin=$("$fnm" exec --using=default node -p 'process.execPath')
export PATH="$(dirname -- "$node_bin"):$PATH"
exec "$node_bin" "$dir/installer.mjs" "$fnm"
