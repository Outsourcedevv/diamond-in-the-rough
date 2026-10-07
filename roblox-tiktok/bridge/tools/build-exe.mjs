// Builds DiamondRushBridge.exe: the bridge, its packages, the control page and
// Node.js itself in one Windows program, so streamers need nothing installed.
// Uses Node's single executable applications (SEA). Run from bridge/:
//   node tools/build-exe.mjs [path to node-vXX-win-x64/node.exe] [output]
// The node.exe must be the same version as the Node running this script.
// The .exe has no Roblox key. The game's owner puts roblox-cloud.txt next to
// it and opens it once: it then writes a "For streamers" copy with the key
// hidden inside (see sealBinary in cloud.mjs).
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const bridge = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = path.join(bridge, 'build');
const target = path.resolve(process.argv[2] ?? process.execPath);
const output = path.resolve(process.argv[3] ?? path.join(work, process.platform === 'win32' || target.endsWith('.exe') ? 'DiamondRushBridge.exe' : 'diamond-rush-bridge'));
fs.mkdirSync(work, { recursive: true });

const run = (command, args) => execFileSync(command, args, { cwd: bridge, stdio: 'inherit', shell: process.platform === 'win32' });

// 1. One CommonJS file with every package inside.
run('npx', ['--yes', 'esbuild@0.24.0', 'bridge.mjs', '--bundle', '--platform=node', '--format=cjs', '--target=node22', '--log-level=warning',
  `--outfile=${path.join(work, 'bridge.cjs')}`,
  "--banner:js=globalThis.__DIAMOND_RUSH_SEA__ = { asset: (name) => Buffer.from(require('node:sea').getAsset(name)) };"]);

// 2. The SEA blob, with the control page and three.js as assets.
const config = {
  main: path.join(work, 'bridge.cjs'),
  output: path.join(work, 'bridge.blob'),
  disableExperimentalSEAWarning: true,
  assets: { 'control.html': path.join(bridge, 'control.html'), 'vendor/three.module.min.js': path.join(bridge, 'vendor', 'three.module.min.js') },
};
fs.writeFileSync(path.join(work, 'sea-config.json'), JSON.stringify(config, null, 2));
run(process.execPath, ['--experimental-sea-config', path.join(work, 'sea-config.json')]);

// 3. A copy of node with the blob injected.
fs.copyFileSync(target, output);
const machO = output.endsWith('.exe') ? [] : process.platform === 'darwin' ? ['--macho-segment-name', 'NODE_SEA'] : [];
run('npx', ['--yes', 'postject@1.0.0-alpha.6', output, 'NODE_SEA_BLOB', path.join(work, 'bridge.blob'), '--sentinel-fuse', 'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2', ...machO]);
console.log(`Built ${output} (${(fs.statSync(output).size / 1048576).toFixed(1)} MB)`);
