import { spawn } from 'node:child_process';
import { constants, existsSync } from 'node:fs';
import { access, lstat, mkdir, mkdtemp, readFile, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { setTimeout as delay } from 'node:timers/promises';
import { stripVTControlCharacters } from 'node:util';
import { height, torus } from './torus.mjs';

const bundled = async name => JSON.parse(await readFile(new URL(name, import.meta.url), 'utf8'));
const packages = await bundled('packages.json');
const agent = resolve(process.env.PI_CODING_AGENT_DIR || join(homedir(), '.pi', 'agent'));
const pi = join(agent, 'bin', 'pi');
const managed = existsSync(join(agent, 'install', 'managed-install.json'));
const env = { ...process.env, PATH: `${dirname(pi)}:${process.env.PATH}`,
  PI_CODING_AGENT_DIR: agent, PI_LEGACY_INSTALL: '0', CI: 'true' };
// A parent Pi session can export a managed root unrelated to the target agent.
delete env.PI_MANAGED_INSTALL_ROOT;
const screen = process.stderr;
const animated = screen.isTTY && process.env.TERM !== 'dumb' && screen.columns >= 68 && screen.rows >= 16;
const total = packages.length + 2;
const lines = [];
let child, interrupted, frame = 0, done = 0;

function log(line) {
  line = stripVTControlCharacters(line).replace(/[^ -~]/g, ' ');
  if (!animated) screen.write(`${line}\n`);
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
    if (child?.pid) {
      try { process.kill(-child.pid, signal); }
      catch (error) { if (error.code !== 'ESRCH') log(error.message); }
    }
  });
}

function run(command, args) {
  if (interrupted) throw new Error('Installation interrupted');
  return new Promise((resolve, reject) => {
    // No controlling terminal: the official installer uses /dev/tty for its menus.
    child = spawn(command, args, { env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    for (const input of [child.stdout, child.stderr]) createInterface({ input }).on('line', log);
    child.once('error', reject);
    child.once('close', (code, signal) => {
      child = undefined;
      if (code === 0 && !interrupted) resolve();
      else reject(Object.assign(new Error(`${command} exited with ${signal || code}`), { code }));
    });
  });
}

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

let timer;
try {
  if (animated) {
    screen.write('\x1b[?1049h\x1b[?25l');
    draw();
    timer = setInterval(draw, 100);
  }
  for (const file of ['settings.json', 'open-tui.json']) await settings(join(agent, file));
  await step(managed ? 'Update managed Pi' : 'Install Pi', async () => {
    if (managed) await run(pi, ['update', '--self', '--no-approve']);
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
    await access(pi, constants.X_OK);
    await run(pi, ['--version']);
  });
  for (const source of packages) await step(`Install ${source}`, () => run(pi, ['install', source, '--no-approve']));
  await step('Apply Pi and Open TUI settings', async () => {
    await mkdir(agent, { recursive: true });
    await apply(join(agent, 'settings.json'), await bundled('pi-settings.json'));
    await apply(join(agent, 'open-tui.json'), await bundled('open-tui.json'));
  });
  if (animated) { draw(); await delay(350); }
} catch (error) {
  log(error.message);
  process.exitCode = Number.isInteger(error.code) && error.code > 0 ? error.code : 1;
} finally {
  if (animated) {
    clearInterval(timer);
    screen.write('\x1b[?25h\x1b[?1049l');
    screen.write(`${lines.join('\n')}\n`);
  }
  if (interrupted) process.exitCode = interrupted;
}

if (!process.exitCode) {
  const quote = value => "'" + value.replaceAll("'", "'\"'\"'") + "'";
  console.log(`[100%] Pi and ${packages.length} packages ready.`);
  console.log(`Launch: ${quote(process.argv[2])} exec --using=default ${quote(pi)}`);
}
