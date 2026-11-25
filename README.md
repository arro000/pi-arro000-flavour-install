<div align="center">
  <h1>Pi arro000 flavour</h1>
  <p><strong>Install Pi with arro000’s extensions, theme and settings.</strong></p>

  [![Linux and macOS](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-66D9EF?style=flat-square)](#requirements)
  [![Node.js](https://img.shields.io/badge/runtime-Node.js-A6E22E?style=flat-square)](#installation)
  [![MIT License](https://img.shields.io/badge/license-MIT-F92672?style=flat-square)](LICENSE)
</div>

## Highlights

- **Hands-off setup:** installs the latest stable Node.js with [fnm](https://github.com/Schniz/fnm), sets it as fnm’s default, and installs or updates managed Pi without prompts.
- **Live progress:** a rotating ASCII torus fills as each step completes, alongside live logs. Small or redirected terminals get plain text.
- **Curated setup:** installs [21 Pi packages](packages.json) and applies the [Pi](pi-settings.json) and [Open TUI](open-tui.json) presets.

## Requirements

Linux or macOS, a regular user account, internet access, Bash and `curl`. Installing fnm also requires `unzip`.

## Installation

If `npx` is already available (requires Git; runs directly from GitHub, not the npm registry):

```sh
npx --yes --allow-git=all github:arro000/pi-arro000-flavour-install
```

Without Node or npm (requires `tar`):

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

Use the launch command printed at the end. Shell profiles are not modified. Run the installer again to update managed Pi. If an unsupported Pi installation blocks the official installer, it stops without replacing it.

## Privacy and safety

Close Pi before running the installer. The presets replace matching settings and keep unrelated values. No credentials, sessions, device IDs or trust decisions are bundled. Sign in separately with `/login`; access to the configured model depends on your account. Review the package list first: Pi extensions can execute code. A failed run stops without rolling back completed steps.

## Development

Run `bash test.sh` for the offline installer checks. The [Pages source](site/) reuses the terminal renderer and package list. To deploy, select **GitHub Actions** under **Settings → Pages** and run the [Pages workflow](.github/workflows/pages.yml).

[MIT](LICENSE) · Pi and its extensions retain their own licenses.
