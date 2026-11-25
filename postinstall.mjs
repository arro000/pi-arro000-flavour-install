import { spawnSync } from 'node:child_process';
import { constants } from 'node:fs';
import { access, copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const windows = process.platform === 'win32';
const self = fileURLToPath(import.meta.url);
const quote = value => "'" + value.replaceAll("'", "'\"'\"'") + "'";
const cmd = value => '"' + value.replaceAll('%', '%%') + '"';
const read = async path => readFile(path, 'utf8').catch(error => {
  if (error.code !== 'ENOENT') throw error;
  return '';
});

export async function ownership(tools, ownedPi, requireExisting = false) {
  await mkdir(tools, { recursive: true });
  const path = join(tools, '.flavour.json');
  const text = requireExisting ? await readFile(path, 'utf8') : await read(path);
  const state = text ? JSON.parse(text) : { ownedPi, packages: [], profiles: [] };
  const save = () => writeFile(path, JSON.stringify(state), { mode: 0o600 });
  await save();
  return { state, save };
}

function userPath(tools, action) {
  const script = `$dir=$env:PI_FLAVOUR_BIN; $path=[Environment]::GetEnvironmentVariable('Path','User');
    $parts=@($path -split ';' | Where-Object { $_ });
    if ($env:PI_FLAVOUR_PATH_ACTION -eq 'add') {
      if ($parts -contains $dir) { exit 0 }
      $parts=@($dir)+$parts; Write-Output added
    } else { $parts=@($parts | Where-Object { $_ -ne $dir }) }
    [Environment]::SetEnvironmentVariable('Path',($parts -join ';'),'User')`;
  return execute('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {
    encoding: 'utf8', env: { ...process.env, PI_FLAVOUR_BIN: tools, PI_FLAVOUR_PATH_ACTION: action }
  }).stdout.trim();
}

function execute(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options, ...(options.encoding ? { stdio: ['ignore', 'pipe', 'inherit'] } : {}) });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? result.signal}`);
  return result;
}

export async function installCommands({ agent, tools, fnm, pi, npmInstall, termux, state, save }) {
  const uninstall = join(tools, 'uninstall.mjs');
  const runtime = termux ? quote(process.execPath) : `${quote(fnm)} exec --using=default`;
  const posix = (command, args) => `#!/bin/sh\nexport PI_CODING_AGENT_DIR=${quote(agent)}\n`
    + `export PATH=${quote(tools)}:"$PATH"\n`
    + (process.env.FNM_DIR ? `export FNM_DIR=${quote(process.env.FNM_DIR)}\n` : '')
    + `exec ${runtime}${!termux && command ? ` ${command}` : ''} ${args.map(quote).join(' ')} "$@"\n`;
  const batch = path => `@echo off\r\nset "PI_CODING_AGENT_DIR=${cmd(agent).slice(1, -1)}"\r\n`
    + `set "PATH=${cmd(tools).slice(1, -1)};%PATH%"\r\n`
    + (process.env.FNM_DIR ? `set "FNM_DIR=${cmd(process.env.FNM_DIR).slice(1, -1)}"\r\n` : '')
    + `${cmd(fnm)} exec --using=default node ${cmd(path)} %*\r\n`;
  await copyFile(self, uninstall);
  const cli = windows ? batch(pi) : posix(npmInstall ? 'node' : '', [pi]);
  const cleanup = windows ? batch(uninstall) : posix('node', [uninstall]);
  await writeFile(join(tools, windows ? 'pi.cmd' : 'pi'), cli, { mode: 0o755 });
  await writeFile(join(tools, windows ? 'pi-flavour-uninstall.cmd' : 'pi-flavour-uninstall'), cleanup, { mode: 0o755 });
  if (windows) {
    if (userPath(tools, 'add') === 'added') state.windowsPath = true;
  } else {
    const home = homedir();
    const bashLogin = await firstExisting(['.bash_profile', '.bash_login', '.profile'].map(file => join(home, file)));
    const files = [join(home, '.bashrc'), bashLogin ?? join(home, '.profile')];
    if (process.env.SHELL?.endsWith('/zsh')) files.push(join(process.env.ZDOTDIR || home, '.zshrc'));
    const line = `case ":$PATH:" in *:${quote(tools)}:*) ;; *) export PATH=${quote(tools)}:"$PATH" ;; esac # pi-arro000-flavour`;
    for (const path of files) {
      const before = await read(path);
      if (before.split('\n').includes(line)) continue;
      await writeFile(path, `${before}${before && !before.endsWith('\n') ? '\n' : ''}${line}\n`);
      state.profiles.push({ path, line });
      await save();
    }
  }
  await save();
}

async function firstExisting(paths) {
  for (const path of paths) {
    try { await access(path, constants.F_OK); return path; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

async function uninstall() {
  const tools = dirname(self);
  const agent = dirname(tools);
  const { state, save } = await ownership(tools, false, true);
  const launcher = join(tools, windows ? 'pi.cmd' : 'pi');
  // Invoke Pi through the same runtime as the installed launcher, without parsing shell text.
  const pi = state.pi;
  if (state.packages.length) {
    while (state.packages.length) {
      const source = state.packages[0];
      const args = ['remove', source, '--no-approve'];
      execute(state.npmInstall ? process.execPath : pi, state.npmInstall ? [pi, ...args] : args,
        { env: { ...process.env, PI_CODING_AGENT_DIR: agent } });
      state.packages.shift();
      await save();
    }
  }
  if (state.ownedPi) {
    await rm(join(agent, state.npmInstall ? 'flavour-pi' : 'install'), { recursive: true, force: true });
    if (!state.npmInstall) await rm(join(agent, 'bin', 'pi'), { force: true });
  }
  if (state.windowsPath) userPath(tools, 'remove');
  for (const { path, line } of state.profiles) {
    const before = await read(path);
    const after = before.split('\n').filter(value => value !== line).join('\n');
    if (before !== after) await writeFile(path, after);
  }
  await rm(launcher, { force: true });
  for (const file of ['rtk', 'rtk.exe', 'pi-flavour-uninstall', 'pi-flavour-uninstall.cmd', 'uninstall.mjs', '.flavour.json']) {
    await rm(join(tools, file), { force: true });
  }
  console.log('Flavour removed. Settings, sessions, credentials, and shared runtimes were kept.');
}

if (process.argv[1] && self === process.argv[1]) await uninstall();
