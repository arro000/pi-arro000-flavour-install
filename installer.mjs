import { spawn } from 'node:child_process';
import { constants, existsSync } from 'node:fs';
import { access, lstat, mkdir, mkdtemp, readFile, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { delimiter, dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { setTimeout as delay } from 'node:timers/promises';
import { stripVTControlCharacters } from 'node:util';
import { setupRtk } from './rtk.mjs';
import { height, torus } from './torus.mjs';

const bundled = async name => JSON.parse(await readFile(new URL(name, import.meta.url), 'utf8'));
const packages = await bundled('packages.json');
const agent = resolve(process.env.PI_CODING_AGENT_DIR || join(homedir(), '.pi', 'agent'));
const windows = process.platform === 'win32';
const termux = process.argv[2] === '--termux';
const npmInstall = windows || termux;
const prefix = join(agent, 'flavour-pi');
const tools = join(agent, 'flavour-bin');
const piPackage = '@earendil-works/pi-coding-agent';
const modules = windows ? ['node_modules'] : ['lib', 'node_modules'];
const pi = npmInstall ? join(prefix, ...modules, piPackage, 'dist', 'bundle', 'cli.js') : join(agent, 'bin', 'pi');
const managed = !npmInstall && existsSync(join(agent, 'install', 'managed-install.json'));
const env = { ...process.env, PATH: `${tools}${delimiter}${join(agent, 'bin')}${delimiter}${process.env.PATH}`,
  PI_CODING_AGENT_DIR: agent, PI_LEGACY_INSTALL: '0', CI: 'true' };
// A parent Pi session can export a managed root unrelated to the target agent.
delete env.PI_MANAGED_INSTALL_ROOT;
const screen = process.stderr;
const animated = screen.isTTY && process.env.TERM !== 'dumb' && screen.columns >= 68 && screen.rows >= 16;
let total = packages.length + 3;
const lines = [];
let child, interrupted, prompt, frame = 0, done = 0;

function log(line) {
  line = stripVTControlCharacters(line).replace(/[^ -~]/g, ' ');
  if (!timer) screen.write(`${line}\n`);
  lines.push(line);
  if (lines.length > 25) lines.shift();
}

function draw() {
  const width = screen.columns - 1;
  if (width < 1 || screen.rows < 2) return;
  const title = `[${Math.floor(100 * done / total)}%] Pi flavour installer`;
  const latest = lines.slice(-height);
  const rows = width < 67 || screen.rows < 16
    ? lines.slice(-(screen.rows - 1)).map(line => line.slice(0, width))
    : ['Toroid'.padEnd(38) + '| Latest logs', ...torus(frame++, done / total)
      .map((row, i) => `${row}| ${(latest[i] || '').slice(0, width - 40)}`)];
  screen.write(`\x1b[H${[title.slice(0, width), ...rows].join('\x1b[K\n')}\x1b[K\x1b[J`);
}

for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143]]) {
  process.on(signal, () => {
    interrupted = code;
    prompt?.close();
    if (child?.pid) {
      try { if (windows) child.kill(signal); else process.kill(-child.pid, signal); }
      catch (error) { if (error.code !== 'ESRCH') log(error.message); }
    }
  });
}

function run(command, args, capture = false) {
  if (interrupted) throw new Error('Installation interrupted');
  return new Promise((resolve, reject) => {
    // No controlling terminal: the official installer uses /dev/tty for its menus.
    child = spawn(command, args, { env, detached: !windows, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    createInterface({ input: child.stdout }).on('line', line => {
      if (capture) output += `${line}\n`;
      log(line);
    });
    createInterface({ input: child.stderr }).on('line', log);
    child.once('error', reject);
    child.once('close', (code, signal) => {
      child = undefined;
      if (code === 0 && !interrupted) resolve(output);
      else reject(Object.assign(new Error(`${command} exited with ${signal || code}`), { code }));
    });
  });
}

const runPi = args => npmInstall ? run(process.execPath, [pi, ...args]) : run(pi, args);

async function step(label, action) {
  log(`[${done + 1}/${total}] ${label}`);
  await action();
  done++;
}

async function settings(path) {
  let text;
  try { text = await readFile(path, 'utf8'); }
  catch (error) {
    if (error.code === 'ENOENT') {
      try { await lstat(path); }
      catch (missing) { if (missing.code === 'ENOENT') return {}; throw missing; }
    }
    throw error;
  }
  const value = JSON.parse(text);
  if (!object(value)) throw new Error(`Expected a JSON object in ${path}`);
  return value;
}

const object = value => value && typeof value === 'object' && !Array.isArray(value);
function merge(current, preset) {
  return { ...current, ...Object.fromEntries(Object.entries(preset).map(([key, value]) => [key,
    object(value) && Object.hasOwn(current, key) && object(current[key]) ? merge(current[key], value) : value])) };
}

async function apply(path, preset) {
  const next = merge(await settings(path), preset);
  const target = existsSync(path) ? await realpath(path) : path;
  const temp = await mkdtemp(join(dirname(target), '.flavour-'));
  try {
    const file = join(temp, 'settings.json');
    await writeFile(file, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
    await rename(file, target);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}

// A configured source can be an object with filters or a version-pinned npm spec.
function npmSources(settings) {
  return new Map((settings.packages ?? []).flatMap(entry => {
    const source = typeof entry === 'string' ? entry : entry?.source;
    const name = /^npm:(@[^/]+\/[^@]+|[^@]+)(?:@.+)?$/.exec(source)?.[1];
    return name ? [[`npm:${name}`, source]] : [];
  }));
}

async function confirmPresets() {
  if (!process.stdin.isTTY || !screen.isTTY) return false;
  prompt = createInterface({ input: process.stdin, output: screen });
  try {
    const answer = await new Promise(resolve => {
      prompt.once('close', () => resolve(''));
      prompt.once('SIGINT', () => { interrupted = 130; prompt.close(); });
      prompt.question('Apply the bundled RTK and Open TUI presets? Matching settings will be replaced. [y/N] ', resolve);
    });
    return /^y(?:es)?$/i.test(answer.trim());
  } finally {
    prompt.close();
    prompt = undefined;
  }
}

let timer;
try {
  const configured = npmSources(await settings(join(agent, 'settings.json')));
  const tui = join(agent, 'open-tui.json');
  const rtkSettings = join(agent, 'extensions', 'pi-rtk-optimizer', 'config.json');
  const initialized = existsSync(tui) && configured.has('npm:pi-open-tui') && configured.has('npm:@arro000/pi-monokai-contrast');
  const updating = managed || existsSync(pi) || initialized;
  const applyPresets = !updating || await confirmPresets();
  if (interrupted) throw new Error('Installation interrupted');
  if (!applyPresets) total--;
  await settings(tui);
  const applyRtk = applyPresets && (updating || !(await lstat(rtkSettings).catch(error => {
    if (error.code !== 'ENOENT') throw error;
  })));
  if (applyRtk) await settings(rtkSettings);
  if (animated) {
    screen.write('\x1b[?1049h\x1b[?25l');
    timer = setInterval(draw, 100);
    draw();
  }
  const piStep = npmInstall ? 'Install or update Pi via npm' : managed ? 'Update managed Pi' : 'Install Pi';
  await step(piStep, async () => {
    if (npmInstall) {
      const npmRoot = termux ? join(process.env.PREFIX, 'lib') : dirname(process.execPath);
      const npm = join(npmRoot, 'node_modules', 'npm', 'bin', 'npm-cli.js');
      await run(process.execPath, [npm, 'install', '--global', '--prefix', prefix, '--ignore-scripts',
        '--no-fund', '--no-audit', `${piPackage}@latest`]);
    } else if (managed) await runPi(['update', '--self', '--no-approve']);
    else {
      const temp = await mkdtemp(join(tmpdir(), 'pi-flavour-'));
      try {
        const script = join(temp, 'pi-install.sh');
        await run('curl', ['-fsSL', 'https://pi.dev/install.sh', '-o', script]);
        await run('sh', [script]);
      } finally {
        await rm(temp, { recursive: true, force: true });
      }
    }
    await access(pi, npmInstall ? constants.R_OK : constants.X_OK);
    await runPi(['--version']);
  });
  await step('Install or update RTK', () => setupRtk(tools, termux, run, log));
  for (const source of packages) {
    const existing = configured.get(source);
    await step(`${existing ? 'Update' : 'Install'} ${source}`,
      () => runPi([existing ? 'update' : 'install', existing ?? source, '--no-approve']));
  }
  if (applyPresets) await step('Apply configuration presets', async () => {
    await mkdir(agent, { recursive: true });
    if (!updating) await apply(join(agent, 'settings.json'), await bundled('pi-settings.json'));
    await apply(tui, await bundled('open-tui.json'));
    if (applyRtk) {
      await mkdir(dirname(rtkSettings), { recursive: true });
      await apply(rtkSettings, await bundled('rtk-settings.json'));
    }
  });
  if (animated) { draw(); await delay(350); }
} catch (error) {
  log(error.message);
  process.exitCode = Number.isInteger(error.code) && error.code > 0 ? error.code : 1;
} finally {
  if (timer) {
    clearInterval(timer);
    screen.write('\x1b[?25h\x1b[?1049l');
    screen.write(`${lines.join('\n')}\n`);
  }
  if (interrupted) process.exitCode = interrupted;
}

if (!process.exitCode) {
  const quote = value => "'" + value.replaceAll("'", windows ? "''" : "'\"'\"'") + "'";
  let launch = `node ${quote(pi)}`;
  if (!termux) {
    const fnm = quote(process.argv[2]);
    launch = `${windows ? '& ' : ''}${fnm} exec --using=default ${windows ? 'node ' : ''}${quote(pi)}`;
  }
  launch = windows ? `$env:Path = ${quote(`${tools};`)} + $env:Path; ${launch}`
    : `PATH=${quote(tools)}:"$PATH" ${launch}`;
  process.stdout.write(`[100%] Pi and ${packages.length} packages ready.\nLaunch: ${launch}\n`);
}
