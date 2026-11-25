import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { chmod, lstat, mkdir, mkdtemp, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export async function setupRtk(bin, termux, run, log) {
  const { platform, arch } = process;
  const cpu = { x64: 'x86_64', arm64: 'aarch64' }[arch];
  const windows = platform === 'win32';
  const suffix = { linux: 'unknown-linux-musl', darwin: 'apple-darwin', win32: 'pc-windows-msvc' }[platform];
  if (termux || !cpu || !suffix || (windows && arch !== 'x64')) {
    log('No supported RTK binary for this platform; the optimizer can run without RTK.');
    return;
  }
  const name = windows ? 'rtk.exe' : 'rtk';
  const path = join(bin, name);
  const releases = 'https://github.com/rtk-ai/rtk/releases';
  const latest = await get(`${releases}/latest`, { redirect: 'manual' }, 302);
  const tag = latest.headers.get('location')?.split('/').at(-1);
  if (!/^v\d+\.\d+\.\d+$/.test(tag ?? '')) throw new Error('Could not resolve the stable RTK release');
  if (existsSync(path)) {
    const version = (await run(path, ['--version'], true)).trim().split(/\s+/)[1];
    if (`v${version}` === tag) return;
  }
  const url = `${releases}/download/${tag}`;
  const asset = `rtk-oss-${cpu}-${suffix}.${windows ? 'zip' : 'tar.gz'}`;
  const checksums = await (await get(`${url}/checksums.txt`)).text();
  const checksum = checksums.split(/\r?\n/).map(line => line.trim().split(/\s+/))
    .find(([, file]) => file === asset)?.[0];
  if (!/^[0-9a-f]{64}$/i.test(checksum ?? '')) throw new Error(`No valid RTK checksum for ${asset}`);
  const bytes = Buffer.from(await (await get(`${url}/${asset}`)).arrayBuffer());
  if (createHash('sha256').update(bytes).digest('hex') !== checksum.toLowerCase()) throw new Error('RTK checksum mismatch');
  await mkdir(bin, { recursive: true });
  const temp = await mkdtemp(join(bin, '.rtk-'));
  try {
    const archive = join(temp, asset);
    const candidate = join(temp, name);
    await writeFile(archive, bytes);
    await run(windows ? 'tar.exe' : 'tar', ['-xf', archive, '-C', temp, name]);
    if (!(await lstat(candidate)).isFile()) throw new Error('RTK archive did not contain a regular executable');
    await chmod(candidate, 0o755);
    await run(candidate, ['--version']);
    await rename(candidate, path);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}

async function get(url, options, status = 200) {
  const response = await fetch(url, { signal: AbortSignal.timeout(60_000), ...options });
  if (response.status !== status) throw new Error(`RTK download: HTTP ${response.status} (${url})`);
  return response;
}
