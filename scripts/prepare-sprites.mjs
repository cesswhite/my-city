/**
 * Deterministic local PNG import. No generation, network, credential access or package install.
 * node scripts/prepare-sprites.mjs --catalog <json> [--root <project>] [--out game/assets/generated] [--manifest <json>]
 * node scripts/prepare-sprites.mjs --self-test
 *
 * Catalog:
 * {version:1, sheets:{body:{path:'output/imagegen/body.png',grid:[4,4],background:'auto'}},
 *  assets:[{id:'char_body',sheet:'body',columns:[0,1,2,3],rows:[0,1,2,3],
 *   crop:[32,0,192,256],size:[24,32],fit:'fill',trim:false,frames:4,
 *   directions:['down','left','right','up'],anchor:[12,30],
 *   mask:{any:[{hue:[0,45],saturation:[0.1,1],value:[0,1]}],gray:'max',gain:1}}],
 *  manifest:{characters:{size:[24,32],anchor:[12,30],layers:[{asset:'char_body',tint:'skin'}]}}}
 * Mask numbers are illustrative only. Calibrate against the inspected source before importing.
 * size is per-cell output size; manifest size is full PNG size, frame_size is logical cell size.
 * crop_space:'sheet' makes crop absolute (one output cell only). Optional alpha_threshold:128
 * creates binary alpha; omitted preserves it. source_offsets:[[x,y],...] applies one translation
 * per original source row, before resizing, shared across all its animation frames.
 * source_scale optionally resizes an overlay around the top-center of its untrimmed canvas.
 */
import { readFile, writeFile, rename, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve, relative, extname, isAbsolute, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir, homedir } from 'node:os';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const DIRECTIONS = ['down', 'left', 'right', 'up'];
const MAX_PIXELS = 32_000_000;
let sharpModule;

export function loadSharp() {
  if (sharpModule) return sharpModule;
  for (const location of ['sharp', '../backend/node_modules/sharp', join(homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp')]) {
    try { sharpModule = require(location); return sharpModule; } catch {}
  }
  throw new Error('Sharp no está disponible. Usa el runtime local con Sharp; este script no instala dependencias.');
}

function integer(value, name, min = 0, max = 8192) {
  if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error(`${name}: entero fuera de rango.`);
  return value;
}
function pair(value, name, min = 1) {
  if (!Array.isArray(value) || value.length !== 2) throw new Error(`${name}: se esperan dos enteros.`);
  return value.map((number) => integer(number, name, min));
}
function indices(value, count, name) {
  if (!Array.isArray(value) || !value.length || new Set(value).size !== value.length) throw new Error(`${name}: lista vacía o duplicada.`);
  return value.map((number) => integer(number, name, 0, count - 1));
}
function range(value, name, max) {
  if (!Array.isArray(value) || value.length !== 2 || value.some((number) => !Number.isFinite(number) || number < 0 || number > max)) throw new Error(`${name}: rango inválido.`);
  if (name !== 'hue' && value[0] > value[1]) throw new Error(`${name}: rango invertido.`);
  return value;
}
export function rgbToHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
  let hue = delta === 0 ? 0 : max === r ? 60 * (((g - b) / delta) % 6) : max === g ? 60 * ((b - r) / delta + 2) : 60 * ((r - g) / delta + 4);
  if (hue < 0) hue += 360;
  return [hue, max === 0 ? 0 : delta / max, max];
}
function inRange(number, limits, wrap = false) {
  return wrap && limits[0] > limits[1] ? number >= limits[0] || number <= limits[1] : number >= limits[0] && number <= limits[1];
}
function keyFamily(r, g, b) {
  const [h, s, v] = rgbToHsv(r, g, b);
  if (s < 0.65 || v < 0.70) return '';
  return h >= 95 && h <= 145 ? 'green' : h >= 280 && h <= 330 ? 'magenta' : '';
}

/** Preserve existing alpha. Opaque images may key only matching pixels connected to an edge. */
export function removeEdgeChroma(input, width, height, mode = 'auto') {
  if (!['auto', 'alpha', 'edge-chroma', 'none'].includes(mode)) throw new Error('background: modo desconocido.');
  const data = Buffer.from(input);
  for (let i = 3; i < data.length; i += 4) {
    if (data[i] !== 255) return { data, removed: 0, treatment: 'preserved-alpha' };
  }
  if (mode === 'alpha' || mode === 'none') return { data, removed: 0, treatment: 'opaque-kept' };
  const border = [];
  for (let x = 0; x < width; x++) { border.push(x); if (height > 1) border.push((height - 1) * width + x); }
  for (let y = 1; y < height - 1; y++) { border.push(y * width); if (width > 1) border.push(y * width + width - 1); }
  const counts = { green: 0, magenta: 0 };
  for (const pixel of border) { const offset = pixel * 4; const family = keyFamily(...data.subarray(offset, offset + 3)); if (family) counts[family]++; }
  const family = counts.green > counts.magenta ? 'green' : 'magenta';
  if (counts[family] / border.length < 0.80) {
    if (mode === 'edge-chroma') throw new Error('Chroma ambiguo: al menos el 80% del borde debe compartir verde o magenta fluorescente.');
    return { data, removed: 0, treatment: 'opaque-kept' };
  }
  const visited = new Uint8Array(width * height), queue = new Int32Array(width * height);
  let head = 0, tail = 0, removed = 0;
  function visit(pixel) {
    if (visited[pixel]) return;
    visited[pixel] = 1;
    const offset = pixel * 4;
    if (keyFamily(data[offset], data[offset + 1], data[offset + 2]) !== family) return;
    queue[tail++] = pixel;
  }
  for (const pixel of border) visit(pixel);
  while (head < tail) {
    const pixel = queue[head++], x = pixel % width, y = Math.floor(pixel / width);
    data[pixel * 4 + 3] = 0;
    removed++;
    if (x > 0) visit(pixel - 1);
    if (x + 1 < width) visit(pixel + 1);
    if (y > 0) visit(pixel - width);
    if (y + 1 < height) visit(pixel + width);
  }
  return { data, removed, treatment: `edge-${family}` };
}

/** Explicit calibrated windows only; no implicit assumption about the generated body palette. */
export function applyColorMask(input, mask, width) {
  if (!mask) return Buffer.from(input);
  if (!Array.isArray(mask.any) || !mask.any.length) throw new Error('mask.any requiere al menos una selección HSV calibrada.');
  const windows = mask.any.map((window) => ({
    hue: range(window.hue ?? [0, 360], 'hue', 360),
    saturation: range(window.saturation ?? [0, 1], 'saturation', 1),
    value: range(window.value ?? [0, 1], 'value', 1),
    region: window.region,
  }));
  for (const window of windows) if (window.region !== undefined) {
    if (!Number.isInteger(width) || width < 1 || !Array.isArray(window.region) || window.region.length !== 4) throw new Error('mask.region requiere [x,y,w,h] y ancho de imagen.');
    window.region.forEach((number, index) => integer(number, 'mask.region', index < 2 ? 0 : 1));
  }
  const gray = mask.gray ?? 'none', gain = mask.gain ?? 1;
  if (!['none', 'max', 'luma'].includes(gray) || !Number.isFinite(gain) || gain <= 0 || gain > 4) throw new Error('mask: conversión gris o ganancia inválida.');
  const data = Buffer.from(input);
  for (let i = 0; i < data.length; i += 4) {
    if (!data[i + 3]) continue;
    const [h, s, v] = rgbToHsv(data[i], data[i + 1], data[i + 2]);
    const x = (i / 4) % width, y = Math.floor(i / 4 / width);
    const selected = windows.some((window) => (!window.region || (x >= window.region[0] && y >= window.region[1] && x < window.region[0] + window.region[2] && y < window.region[1] + window.region[3])) && inRange(h, window.hue, true) && inRange(s, window.saturation) && inRange(v, window.value));
    if (selected === Boolean(mask.invert)) { data[i + 3] = 0; continue; }
    if (gray !== 'none') {
      const shade = gray === 'max' ? Math.max(data[i], data[i + 1], data[i + 2]) : 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      const adjusted = Math.max(0, Math.min(255, Math.round(shade * gain)));
      data[i] = data[i + 1] = data[i + 2] = adjusted;
    }
  }
  return data;
}

export function offsetPixels(input, width, height, offset = [0, 0]) {
  if (!Array.isArray(offset) || offset.length !== 2) throw new Error('source_offset requiere [x,y].');
  offset.forEach((value) => integer(value, 'source_offset', -8192, 8192));
  const output = Buffer.alloc(input.length);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const targetX = x + offset[0], targetY = y + offset[1];
    if (targetX < 0 || targetY < 0 || targetX >= width || targetY >= height) continue;
    input.copy(output, (targetY * width + targetX) * 4, (y * width + x) * 4, (y * width + x + 1) * 4);
  }
  return output;
}

export function thresholdAlpha(input, threshold) {
  const output = Buffer.from(input);
  if (threshold === undefined) return output;
  integer(threshold, 'alpha_threshold', 1, 255);
  for (let i = 3; i < output.length; i += 4) output[i] = output[i] >= threshold ? 255 : 0;
  return output;
}

async function scaleOnCanvas(sharp, input, width, height, scale = 1) {
  if (!Number.isFinite(scale) || scale <= 0 || scale > 1) throw new Error('source_scale debe estar entre 0 (excluido) y 1.');
  if (scale === 1) return input;
  const scaledWidth = Math.max(1, Math.round(width * scale)), scaledHeight = Math.max(1, Math.round(height * scale));
  const resized = await sharp(input, { raw: { width, height, channels: 4 } }).resize(scaledWidth, scaledHeight, { fit: 'fill', kernel: 'nearest' }).raw().toBuffer();
  const output = Buffer.alloc(input.length);
  blit(output, width, resized, scaledWidth, scaledHeight, Math.floor((width - scaledWidth) / 2), 0);
  return output;
}

function alphaBounds(data, width, height) {
  let left = width, top = height, right = -1, bottom = -1;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (!data[(y * width + x) * 4 + 3]) continue;
    left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y);
  }
  return right < 0 ? null : { left, top, width: right - left + 1, height: bottom - top + 1 };
}
function blit(target, targetWidth, source, width, height, atX, atY) {
  for (let row = 0; row < height; row++) source.copy(target, ((atY + row) * targetWidth + atX) * 4, row * width * 4, (row + 1) * width * 4);
}
async function atomicWrite(path, contents) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}`;
  try { await writeFile(temporary, contents, { flag: 'wx' }); await rename(temporary, path); }
  finally { await rm(temporary, { force: true }); }
}

export async function prepareSprites(catalog, options = {}) {
  const sharp = options.sharp ?? loadSharp();
  const projectRoot = resolve(options.projectRoot ?? process.cwd());
  const outputDir = resolve(projectRoot, options.outputDir ?? 'game/assets/generated');
  const manifestPath = resolve(projectRoot, options.manifestPath ?? join(outputDir, 'manifest.json'));
  const resourcePath = relative(join(projectRoot, 'game'), outputDir);
  if (resourcePath.startsWith('..') || isAbsolute(resourcePath)) throw new Error('La salida debe estar dentro de game/ para producir rutas res:// válidas.');
  if (catalog?.version !== 1 || !catalog.sheets || !Array.isArray(catalog.assets) || !catalog.assets.length) throw new Error('Catálogo inválido: se requieren version:1, sheets y assets.');
  // Keep explicit passthrough entries/metadata (for example separately imported riding
  // atlases). A normal catalog rebuild must not remove assets it does not generate.
  const ids = new Set(), sheets = new Map(), manifest = { ...(catalog.manifest ?? {}), version: 1, assets: structuredClone(catalog.manifest?.assets ?? {}) }, reports = [];
  for (const asset of catalog.assets) {
    if (typeof asset.id !== 'string' || !/^[a-z][a-z0-9_]*$/.test(asset.id) || ids.has(asset.id)) throw new Error('Identificador de asset inválido o duplicado.');
    ids.add(asset.id);
    const source = catalog.sheets[asset.sheet];
    if (!source || typeof source.path !== 'string' || extname(source.path).toLowerCase() !== '.png') throw new Error(`${asset.id}: falta una fuente PNG.`);
    let sheet = sheets.get(asset.sheet);
    if (!sheet) {
      const [columns, rows] = pair(source.grid, 'grid');
      const path = resolve(projectRoot, source.path);
      const buffer = await readFile(path);
      const metadata = await sharp(buffer, { limitInputPixels: MAX_PIXELS }).metadata();
      if (metadata.format !== 'png' || !metadata.width || !metadata.height || metadata.width % columns || metadata.height % rows) throw new Error(`${asset.sheet}: PNG o cuadrícula incompatible.`);
      const raw = await sharp(buffer, { limitInputPixels: MAX_PIXELS }).ensureAlpha().toColourspace('srgb').raw().toBuffer();
      const keyed = removeEdgeChroma(raw, metadata.width, metadata.height, source.background ?? 'auto');
      sheet = { ...keyed, width: metadata.width, height: metadata.height, columns, rows, cellWidth: metadata.width / columns, cellHeight: metadata.height / rows };
      sheets.set(asset.sheet, sheet);
      reports.push({ sheet: asset.sheet, treatment: keyed.treatment, removed_pixels: keyed.removed });
    }
    const columns = indices(asset.columns ?? [0], sheet.columns, 'columns'), rows = indices(asset.rows ?? [0], sheet.rows, 'rows');
    const [width, height] = pair(asset.size, 'size');
    const absoluteCrop = asset.crop_space === 'sheet';
    if (asset.crop_space !== undefined && !['sheet', 'cell'].includes(asset.crop_space)) throw new Error(`${asset.id}: crop_space inválido.`);
    if (absoluteCrop && (columns.length !== 1 || rows.length !== 1)) throw new Error(`${asset.id}: crop absoluto requiere un único asset, no una selección de atlas.`);
    const crop = asset.crop ?? [0, 0, absoluteCrop ? sheet.width : sheet.cellWidth, absoluteCrop ? sheet.height : sheet.cellHeight];
    if (!Array.isArray(crop) || crop.length !== 4) throw new Error(`${asset.id}: crop inválido.`);
    crop.forEach((number, index) => integer(number, 'crop', index < 2 ? 0 : 1));
    if (crop[0] + crop[2] > (absoluteCrop ? sheet.width : sheet.cellWidth) || crop[1] + crop[3] > (absoluteCrop ? sheet.height : sheet.cellHeight)) throw new Error(`${asset.id}: crop sale de la celda o imagen.`);
    const fit = asset.fit ?? 'fill';
    if (!['fill', 'contain'].includes(fit)) throw new Error(`${asset.id}: fit inválido.`);
    const outputWidth = width * columns.length, outputHeight = height * rows.length;
    if (outputWidth * outputHeight > MAX_PIXELS) throw new Error(`${asset.id}: atlas excesivo.`);
    if (asset.frames !== undefined && integer(asset.frames, 'frames', 1) !== columns.length) throw new Error(`${asset.id}: frames no coincide con columns.`);
    if (asset.directions !== undefined && (!Array.isArray(asset.directions) || asset.directions.length !== rows.length || new Set(asset.directions).size !== rows.length || asset.directions.some((direction) => !DIRECTIONS.includes(direction)))) throw new Error(`${asset.id}: directions no coincide con rows.`);
    const output = Buffer.alloc(outputWidth * outputHeight * 4);
    for (let row = 0; row < rows.length; row++) for (let col = 0; col < columns.length; col++) {
      const region = { left: (absoluteCrop ? 0 : columns[col] * sheet.cellWidth) + crop[0], top: (absoluteCrop ? 0 : rows[row] * sheet.cellHeight) + crop[1], width: crop[2], height: crop[3] };
      let data = await sharp(sheet.data, { raw: { width: sheet.width, height: sheet.height, channels: 4 } }).extract(region).raw().toBuffer();
      let frameWidth = region.width, frameHeight = region.height;
      const offsets = asset.source_offsets ?? source.source_offsets;
      if (offsets !== undefined && (!Array.isArray(offsets) || offsets.length !== sheet.rows)) throw new Error(`${asset.id}: source_offsets requiere una entrada por fila de la fuente.`);
      data = thresholdAlpha(data, asset.alpha_threshold ?? source.alpha_threshold);
      data = await scaleOnCanvas(sharp, data, frameWidth, frameHeight, asset.source_scale ?? source.source_scale ?? 1);
      data = offsetPixels(data, frameWidth, frameHeight, offsets?.[rows[row]] ?? asset.source_offset ?? source.source_offset ?? [0, 0]);
      data = applyColorMask(data, asset.mask, frameWidth);
      if (asset.trim) {
        const bounds = alphaBounds(data, frameWidth, frameHeight);
        if (!bounds) continue;
        data = await sharp(data, { raw: { width: frameWidth, height: frameHeight, channels: 4 } }).extract(bounds).raw().toBuffer();
        frameWidth = bounds.width; frameHeight = bounds.height;
      }
      const scale = Math.min(width / frameWidth, height / frameHeight);
      const resizedWidth = fit === 'fill' ? width : Math.min(width, Math.max(1, Math.round(frameWidth * scale)));
      const resizedHeight = fit === 'fill' ? height : Math.min(height, Math.max(1, Math.round(frameHeight * scale)));
      const resized = await sharp(data, { raw: { width: frameWidth, height: frameHeight, channels: 4 } }).resize(resizedWidth, resizedHeight, { fit: 'fill', kernel: 'nearest' }).raw().toBuffer();
      const x = Math.floor((width - resizedWidth) / 2), y = asset.align === 'center' ? Math.floor((height - resizedHeight) / 2) : height - resizedHeight;
      blit(output, outputWidth, resized, resizedWidth, resizedHeight, col * width + x, row * height + y);
    }
    const bytes = await sharp(output, { raw: { width: outputWidth, height: outputHeight, channels: 4 } }).png({ compressionLevel: 9, adaptiveFiltering: false }).toBuffer();
    await atomicWrite(join(outputDir, `${asset.id}.png`), bytes);
    const entry = { ...(manifest.assets[asset.id] ?? {}), path: `res://${resourcePath.split('\\').join('/')}/${asset.id}.png`, size: [outputWidth, outputHeight] };
    if (asset.anchor !== undefined) { const anchor = pair(asset.anchor, 'anchor', 0); if (anchor[0] > width || anchor[1] > height) throw new Error(`${asset.id}: ancla fuera de la celda.`); entry.anchor = anchor; }
    if (asset.frames !== undefined || asset.directions !== undefined) {
      entry.frame_size = [width, height]; entry.frames = asset.frames ?? columns.length;
      if (asset.directions !== undefined) entry.directions = asset.directions;
    }
    manifest.assets[asset.id] = entry;
  }
  await atomicWrite(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  return { manifest, reports, outputDir, manifestPath };
}

export async function selfTest() {
  const sharp = loadSharp();
  const temporary = await mkdtemp(join(tmpdir(), 'my-city-sprites-test-'));
  let checks = 0;
  try {
    const opaque = Buffer.alloc(7 * 7 * 4);
    for (let pixel = 0; pixel < 49; pixel++) opaque.set([0, 255, 0, 255], pixel * 4);
    for (let y = 2; y <= 4; y++) for (let x = 2; x <= 4; x++) opaque.set([240, 0, 0, 255], (y * 7 + x) * 4);
    opaque.set([0, 255, 0, 255], (3 * 7 + 3) * 4);
    const keyed = removeEdgeChroma(opaque, 7, 7, 'edge-chroma');
    assert.equal(keyed.removed, 40); assert.equal(keyed.data[(3 * 7 + 3) * 4 + 3], 255); checks += 2;
    const transparent = Buffer.from(opaque); transparent[3] = 128;
    assert.deepEqual(removeEdgeChroma(transparent, 7, 7).data, transparent); checks++;
    assert.throws(() => removeEdgeChroma(Buffer.alloc(16, 255), 2, 2, 'edge-chroma'), /ambiguo/); checks++;
    const mask = applyColorMask(Buffer.from([0, 0, 255, 128, 255, 0, 0, 255]), { any: [{ hue: [200, 260] }], gray: 'max' });
    assert.deepEqual([...mask], [255, 255, 255, 128, 255, 0, 0, 0]); checks++;
    const alpha = thresholdAlpha(Buffer.from([1, 2, 3, 127, 4, 5, 6, 128]), 128);
    assert.deepEqual([...alpha], [1, 2, 3, 0, 4, 5, 6, 255]); checks++;
    const shifted = offsetPixels(Buffer.from([1, 2, 3, 255, 4, 5, 6, 255]), 1, 2, [0, 1]);
    assert.deepEqual([...shifted], [0, 0, 0, 0, 1, 2, 3, 255]); checks++;
    const scaled = await scaleOnCanvas(sharp, Buffer.alloc(4 * 4 * 4, 255), 4, 4, 0.5);
    assert.equal([...scaled].filter((value, index) => index % 4 === 3 && value === 255).length, 4); checks++;
    assert.deepEqual([...scaled.subarray(4, 8)], [255, 255, 255, 255]); checks++;
    assert.equal(scaled[(2 * 4 + 1) * 4 + 3], 0); checks++;
    await assert.rejects(() => scaleOnCanvas(sharp, scaled, 4, 4, 1.1), /source_scale/); checks++;
    const regional = applyColorMask(Buffer.from([0, 0, 255, 255, 0, 0, 255, 255]), { any: [{ hue: [200, 260], region: [1, 0, 1, 1] }] }, 2);
    assert.equal(regional[3], 0); assert.equal(regional[7], 255); checks += 2;
    const image = Buffer.from([255, 0, 0, 255, 0, 0, 255, 255, 0, 255, 0, 0, 255, 255, 0, 128]);
    await sharp(image, { raw: { width: 2, height: 2, channels: 4 } }).png().toFile(join(temporary, 'fixture.png'));
    const catalog = { version: 1, sheets: { sample: { path: 'fixture.png', grid: [2, 2], background: 'alpha' } }, assets: [{ id: 'fixture', sheet: 'sample', columns: [1, 0], rows: [0, 1], size: [2, 3], trim: false, frames: 2, directions: ['down', 'up'], anchor: [1, 3] }] };
    const result = await prepareSprites(catalog, { projectRoot: temporary, sharp });
    const png = await sharp(join(result.outputDir, 'fixture.png')).raw().toBuffer({ resolveWithObject: true });
    assert.equal(png.info.width, 4); assert.equal(png.info.height, 6); checks += 2;
    assert.deepEqual([...png.data.subarray(0, 4)], [0, 0, 255, 255]); checks++;
    assert.equal(png.data[(3 * 4 + 0) * 4 + 3], 128); assert.equal(png.data[(3 * 4 + 2) * 4 + 3], 0); checks += 2;
    assert.deepEqual(result.manifest.assets.fixture.frame_size, [2, 3]); checks++;
    assert.equal(result.manifest.assets.fixture.path, 'res://assets/generated/fixture.png'); checks++;
    const before = await readFile(join(result.outputDir, 'fixture.png'));
    await prepareSprites(catalog, { projectRoot: temporary, sharp });
    assert.deepEqual(await readFile(join(result.outputDir, 'fixture.png')), before); checks++;
    const rowOffsets = await prepareSprites({ ...catalog, sheets: { sample: { ...catalog.sheets.sample, source_offsets: [[0, 0], [0, -1]] } } }, { projectRoot: temporary, sharp });
    const offsetAtlas = await sharp(join(rowOffsets.outputDir, 'fixture.png')).raw().toBuffer();
    assert.equal(offsetAtlas[3], 255); assert.equal(offsetAtlas[(3 * 4) * 4 + 3], 0); checks += 2;
    const absolute = await prepareSprites({ ...catalog, assets: [{ id: 'absolute', sheet: 'sample', crop_space: 'sheet', crop: [0, 0, 2, 2], size: [2, 2], alpha_threshold: 128 }] }, { projectRoot: temporary, sharp });
    const absolutePixels = await sharp(join(absolute.outputDir, 'absolute.png')).raw().toBuffer();
    assert.equal(absolutePixels[15], 255); assert.equal(absolutePixels[11], 0); checks += 2;
    await assert.rejects(() => prepareSprites({ ...catalog, assets: [{ ...catalog.assets[0], id: '../invalid' }] }, { projectRoot: temporary, sharp }), /Identificador/); checks++;
    await assert.rejects(() => prepareSprites({ ...catalog, assets: [{ ...catalog.assets[0], crop: [1, 0, 1, 1] }] }, { projectRoot: temporary, sharp }), /crop sale/); checks++;
    return checks;
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--self-test') { console.log(`SPRITE IMPORT: ${await selfTest()} checks passed; temporary synthetic PNGs only.`); return; }
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--catalog', '--root', '--out', '--manifest'].includes(args[i]) || !args[i + 1]) throw new Error('Uso: node scripts/prepare-sprites.mjs --catalog <json> [--root <proyecto>] [--out <directorio>] [--manifest <json>]');
    options[args[i].slice(2)] = args[i + 1];
  }
  if (!options.catalog) throw new Error('Falta --catalog. No se importa ningún asset sin catálogo explícito.');
  const projectRoot = resolve(options.root ?? process.cwd());
  const catalog = JSON.parse(await readFile(resolve(projectRoot, options.catalog), 'utf8'));
  const result = await prepareSprites(catalog, { projectRoot, outputDir: options.out, manifestPath: options.manifest });
  console.log(JSON.stringify({ assets: Object.keys(result.manifest.assets), sources: result.reports, manifest: result.manifestPath }, null, 2));
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error instanceof Error ? error.message : 'No se pudo importar el catálogo.'); process.exitCode = 1; });
}
