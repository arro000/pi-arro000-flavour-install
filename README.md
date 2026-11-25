<div align="center">
  <h1>Pi arro000 flavour</h1>
  <p><strong>Install Pi with arro000’s extensions, theme and settings.</strong></p>

  [![Platforms](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Termux-66D9EF?style=flat-square)](#requirements)
  [![Node.js](https://img.shields.io/badge/runtime-Node.js-A6E22E?style=flat-square)](#installation)
  [![MIT License](https://img.shields.io/badge/license-MIT-F92672?style=flat-square)](LICENSE)
</div>

## What gets installed

- **Hands-off setup:** installs Node.js and Pi without prompts, using [fnm](https://github.com/Schniz/fnm) on desktop and Termux packages on Android.
- **Live progress:** a rotating ASCII torus fills as each step completes, alongside live logs. Small or redirected terminals get plain text.
- **Curated setup:** installs [22 Pi packages](packages.json), including `pi-intercom`, and applies the [Pi](pi-settings.json) and [Open TUI](open-tui.json) presets.
- **RTK:** installs the [RTK OSS](https://github.com/rtk-ai/rtk) binary on supported desktop systems for `pi-rtk-optimizer`. The [RTK preset](rtk-settings.json) compacts build, test and lint output without rewriting commands or compacting file reads.

## Requirements

A regular user account and internet access. Linux/macOS need Bash and `curl` (`unzip` for fnm). Native Windows needs PowerShell; install [Git for Windows](https://git-scm.com/download/win) for Pi’s shell tools. Android needs a current [Termux](https://github.com/termux/termux-app#installation) build.

## Installation

If `npx` and Git are already available, run this on any supported platform:

```sh
npx --yes --allow-git=all github:arro000/pi-arro000-flavour-install
```

## Installation without Node.js

### Linux, macOS and WSL

Run in Bash (`tar` required):

```sh
(
  set -e
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  curl -fsSL https://github.com/arro000/pi-arro000-flavour-install/archive/refs/heads/main.tar.gz \
    -o "$work/source.tar.gz"
  tar -xzf "$work/source.tar.gz" -C "$work"
  bash "$work/pi-arro000-flavour-install-main/install.sh"
)
```

On Debian/Ubuntu (including Debian-based SBX images), if Node cannot find `libatomic.so.1`, the installer announces the fallback and uses `sudo` to install `libatomic1`. Enter your password if prompted. If `sudo` is unavailable or not permitted, run this inside the container as root, then retry the installer as a regular user:

```sh
apt-get update && apt-get install -y libatomic1
```

### Native Windows

Run in PowerShell:

```powershell
$work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zip = Join-Path $work 'source.zip'
    Invoke-WebRequest -UseBasicParsing 'https://github.com/arro000/pi-arro000-flavour-install/archive/refs/heads/main.zip' -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $work
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $work 'pi-arro000-flavour-install-main/install.ps1')
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
```

### Android (Termux)

```sh
pkg install -y git &&
  git clone https://github.com/arro000/pi-arro000-flavour-install.git &&
  bash pi-arro000-flavour-install/install.sh
```

Termux uses its native `nodejs` and `npm` packages instead of fnm. Windows and Termux install Pi in a dedicated npm prefix without replacing other Pi binaries. The installer adds its launcher directory to Bash and Zsh startup files or to the Windows user PATH. Open a new shell to pick it up. RTK has no upstream Android binary; Termux can use an existing `rtk` on `PATH` if you have one. Other native extensions may also have platform-specific limits.

## Updating

Close Pi and rerun the same installer command. It updates Pi, RTK where supported, and the configured flavour extensions, and installs only missing entries. In an interactive terminal, you can opt in to reapplying the RTK and Open TUI presets. The default is **No**, and non-interactive updates skip the presets. The Pi preset is not reapplied during updates, and unrelated extensions are not updated.

## Uninstall

Close Pi, then run:

```sh
pi-flavour-uninstall
```

This removes the launchers, RTK, the extensions added by tracked installations, and Pi itself if the flavour installed it from scratch. Settings, sessions, credentials, older untracked installations, and shared dependencies such as fnm, Node.js and system packages are kept.

## Quick start

1. Open a new shell and run `pi`. In the current shell, use the launcher path printed by the installer.
2. Run `/login` to connect a provider, then `/model` to select an available model.
3. Run `/rtk verify` to check RTK. With two Pi sessions open, use `/intercom` to pick a session and send a message. Incoming messages can trigger a turn by default.

## Privacy and safety

Close Pi before running the installer. Presets replace matching keys and keep unrelated values. First-time setup preserves an existing RTK configuration. No credentials, sessions, device IDs or trust decisions are bundled. Sign in separately with `/login`; access to the configured model depends on your account. Review the package list first: Pi extensions can execute code. A failed run stops without rolling back completed steps.

## Development

Run `bash test.sh` for the offline installer checks. The [Pages source](site/) reuses the terminal renderer and package list. To deploy, select **GitHub Actions** under **Settings → Pages** and run the [Pages workflow](.github/workflows/pages.yml).

[MIT](LICENSE) · Pi and its extensions retain their own licenses.
