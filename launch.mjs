#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
if (args.length) {
  if (args.length === 1 && args[0] === '--help') process.stdout.write('Usage: pi-arro000-flavour-install\n');
  else { process.stderr.write('Unexpected arguments. Use --help for usage.\n'); process.exitCode = 2; }
} else {
  const windows = process.platform === 'win32';
  const script = fileURLToPath(new URL(windows ? 'install.ps1' : 'install.sh', import.meta.url));
  const command = windows ? 'powershell.exe' : 'bash';
  const flags = windows ? ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File'] : [];
  const child = spawn(command, [...flags, script], { stdio: 'inherit' });
  child.once('error', error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
  child.once('exit', (code, signal) => { process.exitCode = code ?? (signal === 'SIGINT' ? 130 : 143); });
}
