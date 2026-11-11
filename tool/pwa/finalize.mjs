import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const build = path.join(root, 'build/web');
async function walk(dir, prefix = '') {
  const result = [];
  for (const entry of await readdir(dir, {withFileTypes: true})) {
    const name = path.posix.join(prefix, entry.name);
    if (entry.isDirectory()) result.push(...await walk(path.join(dir, entry.name), name));
    else result.push(name);
  }
  return result;
}

export async function finalize(directory = build) {
  const files = [];
  for (const name of (await walk(directory)).sort()) {
    if (name === '.last_build_id' || name.endsWith('.map') || name.endsWith('.symbols') || name.startsWith('canvaskit/skwasm')) {
      await rm(path.join(directory, name));
      continue;
    }
    if (name === 'sw.js' || name === 'release.json' || name === '.nojekyll' || name.endsWith('.DS_Store')) continue;
    if (name === 'flutter_service_worker.js') { await rm(path.join(directory, name)); continue; }
    const bytes = await readFile(path.join(directory, name));
    files.push({url: name, sha256: createHash('sha256').update(bytes).digest('hex')});
  }
  for (const required of ['index.html', 'main.dart.js', 'manifest.json', 'assets/web-fonts/NotoSansSC.ttf', 'canvaskit/canvaskit.wasm']) {
    if (!files.some(file => file.url === required)) throw new Error(`Missing offline resource: ${required}`);
  }
  const version = createHash('sha256').update(JSON.stringify(files)).digest('hex').slice(0, 20);
  const release = {version, files};
  const template = await readFile(path.join(root, 'tool/pwa/sw-template.js'), 'utf8');
  await writeFile(path.join(directory, 'sw.js'), template.replace('__MEIKE_RELEASE__', JSON.stringify(release)));
  await writeFile(path.join(directory, 'release.json'), JSON.stringify({version, resources: files.length}));
  return release;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const release = await finalize();
  const output = path.join(root, 'build/pages-repository');
  await rm(output, {recursive: true, force: true});
  await mkdir(path.join(output, '.github/workflows'), {recursive: true});
  await cp(build, output, {recursive: true});
  await cp(path.join(root, 'tool/pwa/pages.yml'), path.join(output, '.github/workflows/pages.yml'));
  console.log(`PWA ${release.version}: ${release.files.length} offline resources. Public deployment files: build/pages-repository`);
}
