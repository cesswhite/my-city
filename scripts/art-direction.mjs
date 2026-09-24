/** Local reference/staging workflow; no generation, credentials or network.
 * node scripts/art-direction.mjs prepare
 * node scripts/art-direction.mjs import [--palette off|common96|shared256]
 * node scripts/art-direction.mjs activate [--palette off|common96|shared256] # explicit publication
 * node scripts/art-direction.mjs self-test
 * Optional --config scripts/art-direction.json and --root <project>.
 * Source corrections: source_offset:[dx,dy] per group; asset_corrections[id]
 * may supply offset:[dx,dy] or absolute rect:[x,y,w,h]. No auto trim/recenter.
 * Import never activates its staging manifest or overwrites production files.
 */
import {readFile, writeFile, mkdir, mkdtemp, rm, rename} from 'node:fs/promises';
import {resolve, relative, dirname, join, basename} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {loadSharp, prepareSprites} from './prepare-sprites.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const jsonBytes = value => Buffer.from(JSON.stringify(value,null,2)+'\n');
const REQUIRED = 54;
const PALETTE_RULE = 'Chromatic green (g>r*1.02, g>b*1.08, HSV saturation>0.18) selects only colors with g>r and g>b; other pixels use global weighted RGB distance. No dithering.';
const SHARED_RULE = 'One shared image-derived palette: all 54 native PNG canvases at 1x in fixed 128x128 cells, quantized together once with Sharp palette PNG, colours=256, dither=0, effort=10; then cropped back without resizing.';
const PALETTE_MODES = ['off','common96','shared256'];
function paletteDirectory(staging,palette) {
  if(!PALETTE_MODES.includes(palette))throw new Error('Palette must be off, common96 or shared256.');
  return palette==='off'?staging:join(staging,palette==='common96'?'palette96':'palette256');
}

function local(root,path) {
  if (typeof path !== 'string' || !path || path.startsWith('res://')) throw new Error('Expected project-relative file path.');
  const output = resolve(root,path), rel = relative(root,output);
  if (rel.startsWith('..') || rel === '' || rel.startsWith('/')) throw new Error('Path must stay inside project.');
  return output;
}
function imagePath(root,path) {
  if (!path?.startsWith('res://')) throw new Error('Asset path must use res://.');
  return local(root,'game/'+path.slice(6));
}
function ints(value,count,label,minimum=0) {
  if (!Array.isArray(value)||value.length!==count||value.some(n=>!Number.isSafeInteger(n)||n<minimum||n>8192)) throw new Error('Invalid '+label);
  return value;
}
function offset(value,label) {
  if (!Array.isArray(value)||value.length!==2||value.some(n=>!Number.isSafeInteger(n)||Math.abs(n)>512)) throw new Error('Invalid '+label);
  return value;
}
function validate(config,manifest) {
  if (config.version!==1 || !config.groups || config.alpha_threshold!==128) throw new Error('Unsupported art-direction configuration.');
  const ids=[];
  for (const [name,group] of Object.entries(config.groups)) {
    ints(group.grid,2,'grid',1);
    ints([group.cell,group.max_scale,group.max_content],3,'cell limits',1);
    if (group.grid[0]*group.grid[1]!==group.assets.length || group.max_content>group.cell || group.max_scale>8) throw new Error('Group layout mismatch: '+name);
    offset(group.source_offset??[0,0],'source offset');
    for (const id of group.assets) {
      if (!/^[a-z][a-z0-9_]*$/.test(id)||!manifest.assets[id]) throw new Error('Missing/invalid asset: '+id);
      if (/^(char_|hair_|hat_|beard_|ui_|bicycle)/.test(id)) throw new Error('Protected asset: '+id);
      ints(manifest.assets[id].size,2,'native size',1);
      if (group.opaque && manifest.assets[id].size.some(n=>n!==32)) throw new Error('Terrain must be 32x32.');
      ids.push(id);
    }
    for (const [id,correction] of Object.entries(group.asset_corrections??{})) {
      if (!group.assets.includes(id)||!correction||Object.keys(correction).some(k=>!['offset','rect'].includes(k))) throw new Error('Invalid source correction: '+id);
      if (correction.offset) offset(correction.offset,'asset offset');
      if (correction.rect) { ints(correction.rect,4,'asset rect'); if (!correction.rect[2]||!correction.rect[3]) throw new Error('Empty correction rect.'); }
    }
  }
  if (ids.length!==REQUIRED||new Set(ids).size!==REQUIRED) throw new Error('Exactly 54 distinct environment assets are required.');
  const colors=Object.values(config.material_ramps??{}).flat();
  if(colors.length!==96||new Set(colors).size!==96||colors.some(c=>!/^#[0-9a-fA-F]{6}$/.test(c))) throw new Error('Palette must declare exactly 96 unique RGB colors.');
  return ids;
}
function binary(data,threshold) {
  const output=Buffer.from(data);
  for(let i=0;i<output.length;i+=4) {
    output[i+3]=output[i+3]>=threshold?255:0;
    if(!output[i+3]) output[i]=output[i+1]=output[i+2]=0;
  }
  return output;
}
function alphaBounds(data,width,height) {
  let x0=width,y0=height,x1=-1,y1=-1;
  for(let y=0;y<height;y++) for(let x=0;x<width;x++) if(data[(y*width+x)*4+3]) {
    x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);
  }
  return x1<0?null:[x0,y0,x1-x0+1,y1-y0+1];
}
async function immutable(path,bytes) {
  await mkdir(dirname(path),{recursive:true});
  try { await writeFile(path,bytes,{flag:'wx'}); }
  catch(error) {
    if(error.code!=='EEXIST') throw error;
    if(!bytes.equals(await readFile(path))) throw new Error('Immutable backup differs; refusing overwrite: '+path);
  }
}
async function atomic(path,bytes) {
  await mkdir(dirname(path),{recursive:true});
  const temp=path+'.tmp-'+process.pid;
  try { await writeFile(temp,bytes);await rename(temp,path); }
  finally { await rm(temp,{force:true}); }
}
async function maybeRead(path) {
  try { return await readFile(path); }
  catch(error) { if(error.code==='ENOENT')return null;throw error; }
}
async function inputs(root,config) {
  const currentBytes=await readFile(local(root,config.manifest));
  const backupBytes=await maybeRead(join(local(root,config.work_dir),'before/manifest.json'));
  const bytes=backupBytes??currentBytes;
  const manifest=JSON.parse(bytes);
  const ids=validate(config,manifest);
  return {bytes,manifest,ids,currentBytes,current:JSON.parse(currentBytes),hasBackup:backupBytes!==null};
}

export async function prepareReferences(config,{root=process.cwd()}={}) {
  root=resolve(root);
  const sharp=loadSharp(), {bytes,manifest,ids}=await inputs(root,config);
  const work=local(root,config.work_dir), backup=join(work,'before');
  // All backups are immutable, including the exact manifest bytes.
  await immutable(join(backup,'manifest.json'),bytes);
  const original=new Map();
  for(const id of ids) {
    const png=await maybeRead(join(backup,id+'.png'))??await readFile(imagePath(root,manifest.assets[id].path));
    await immutable(join(backup,id+'.png'),png);
    original.set(id,png);
  }
  const layout={version:1,base_manifest_sha256:digest(bytes),alpha_threshold:config.alpha_threshold,groups:{}};
  for(const [name,group]of Object.entries(config.groups)) {
    const width=group.grid[0]*group.cell,height=group.grid[1]*group.cell;
    const layers=[], entries=[];
    for(const [index,id]of group.assets.entries()) {
      const asset=manifest.assets[id], [w,h]=asset.size;
      const raw=await sharp(original.get(id)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
      if(raw.info.width!==w||raw.info.height!==h) throw new Error('PNG/manifest size mismatch: '+id);
      const pixels=binary(raw.data,config.alpha_threshold);
      if(group.opaque && pixels.some((v,i)=>i%4===3&&v!==255)) throw new Error('Opaque terrain contains transparency: '+id);
      const scale=Math.min(group.max_scale,Math.floor(group.max_content/Math.max(w,h)));
      if(scale<1) throw new Error('Canvas cannot fit reference cell: '+id);
      const col=index%group.grid[0], row=Math.floor(index/group.grid[0]);
      const x=col*group.cell+Math.floor((group.cell-w*scale)/2),y=row*group.cell+Math.floor((group.cell-h*scale)/2);
      const input=await sharp(pixels,{raw:{width:w,height:h,channels:4}}).resize(w*scale,h*scale,{kernel:'nearest'}).png().toBuffer();
      layers.push({input,left:x,top:y,blend:'over'});
      entries.push({id,index,cell:[col*group.cell,row*group.cell,group.cell,group.cell],rect:[x,y,w*scale,h*scale],size:[w,h],scale,alpha_bounds:alphaBounds(pixels,w,h),original_path:asset.path,original_sha256:digest(original.get(id))});
    }
    const reference=await sharp({create:{width,height,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite(layers).png().toBuffer();
    const referencePath=join(work,'references',name+'.png');
    await atomic(referencePath,reference);
    layout.groups[name]={size:[width,height],grid:group.grid,cell:group.cell,opaque:group.opaque,reference:relative(root,referencePath),reference_sha256:digest(reference),assets:entries};
  }
  await atomic(join(work,'references','layout.json'),jsonBytes(layout));
  return layout;
}

function quantize(data,colors) {
  const output=Buffer.from(data),cache=new Map();
  const greens=colors.filter(([r,g,b])=>g>r&&g>b);
  if(!greens.length)throw new Error('Palette needs green material colors.');
  for(let i=0;i<output.length;i+=4) {
    if(!output[i+3]) continue;
    const key=(output[i]<<16)|(output[i+1]<<8)|output[i+2];
    let chosen=cache.get(key);
    if(!chosen) {
      let best=Infinity;
      const r=output[i],g=output[i+1],b=output[i+2],max=Math.max(r,g,b),min=Math.min(r,g,b);
      // Preserve recognizable living foliage. Without this material gate olive
      // midtones can be closer to gold/wood and make plants appear dead.
      const chromaticGreen=g>r*1.02&&g>b*1.08&&max>0&&(max-min)/max>0.18;
      for(const color of chromaticGreen?greens:colors) {
        // Shared material colors, weighted RGB distance; no per-image palettes/dither.
        const d=2*(output[i]-color[0])**2+4*(output[i+1]-color[1])**2+3*(output[i+2]-color[2])**2;
        if(d<best){best=d;chosen=color;}
      }
      cache.set(key,chosen);
    }
    output[i]=chosen[0];output[i+1]=chosen[1];output[i+2]=chosen[2];
  }
  return output;
}

async function sourceLineage(root,config,name,group,sourceHash) {
  const work=local(root,config.work_dir), lineage={};
  let rawSource=group.source;
  const alignmentPath=join(work,'aligned/provenance.json');
  const alignmentBytes=await maybeRead(alignmentPath);
  if(group.source.startsWith(config.work_dir+'/aligned/')) {
    if(!alignmentBytes)throw new Error('Aligned source requires provenance: '+name);
    const alignment=JSON.parse(alignmentBytes).groups?.[name];
    if(!alignment||alignment.aligned_sha256!==sourceHash||digest(await readFile(local(root,alignment.raw_source)))!==alignment.raw_sha256)throw new Error('Raw/aligned provenance hash mismatch: '+name);
    if(!Array.isArray(alignment.assets)||alignment.assets.length!==group.assets.length||alignment.assets.some((entry,index)=>entry.id!==group.assets[index]))throw new Error('Alignment measurements do not match group: '+name);
    rawSource=alignment.raw_source;
    lineage.alignment={path:relative(root,alignmentPath),sha256:digest(alignmentBytes),group:name,raw_source:rawSource,raw_sha256:alignment.raw_sha256,aligned_sha256:alignment.aligned_sha256,measurements:alignment.assets};
  }
  const verificationPath=join(work,'model-verification.json'),verificationBytes=await maybeRead(verificationPath);
  if(verificationBytes) {
    const verification=JSON.parse(verificationBytes);
    if(verification.catalog_http!==200||verification.catalog_model_id!==config.model_requested||verification.model_requested!==config.model_requested)throw new Error('Model catalog verification does not match configured model.');
    lineage.model_verification={path:relative(root,verificationPath),sha256:digest(verificationBytes),model_requested:verification.model_requested,catalog_model_id:verification.catalog_model_id,catalog_http:verification.catalog_http,checked_on:verification.checked_on};
  }
  const generationPath=join(work,basename(rawSource,'.png')+'-generation.json'),generationBytes=await maybeRead(generationPath);
  if(generationBytes) {
    const generation=JSON.parse(generationBytes),args=generation.command_arguments;
    const arg=key=>Array.isArray(args)&&args.includes(key)?args[args.indexOf(key)+1]:null;
    if(generation.model_requested!==config.model_requested||generation.catalog_verified!==true||generation.cli_exit_status!==0||arg('--model')!==config.model_requested||arg('--out')!==rawSource||arg('--prompt-file')!==group.prompt)throw new Error('Generation record does not match source/model/prompt: '+name);
    lineage.generation={path:relative(root,generationPath),sha256:digest(generationBytes),model_requested:generation.model_requested,model_response:generation.model_response??null,cli_exit_status:0,raw_source:rawSource,raw_sha256:digest(await readFile(local(root,rawSource)))};
  }
  return lineage;
}

async function quantizeShared(pending,ids,report,sharp) {
  assert.equal(pending.length,REQUIRED);
  const cell=128,columns=9,rows=6,width=cell*columns,height=cell*rows;
  const layers=[],original=[];
  for(let index=0;index<ids.length;index++) {
    const raw=await sharp(pending[index][1]).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    if(raw.info.width>cell||raw.info.height>cell)throw new Error('Native asset cannot fit shared-palette cell: '+ids[index]);
    original.push(raw);
    layers.push({input:pending[index][1],left:(index%columns)*cell,top:Math.floor(index/columns)*cell,blend:'over'});
  }
  // There is exactly one palette optimization, never one palette per asset.
  const combined=await sharp({create:{width,height,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite(layers).png({palette:true,colours:256,dither:0,effort:10}).toBuffer();
  const decoded=await sharp(combined).ensureAlpha().raw().toBuffer();
  const actualColors=new Set();
  for(let index=0;index<ids.length;index++) {
    const id=ids[index],{info,data:before}=original[index];
    const left=(index%columns)*cell,top=Math.floor(index/columns)*cell;
    const crop=await sharp(decoded,{raw:{width,height,channels:4}}).extract({left,top,width:info.width,height:info.height}).raw().toBuffer();
    const pixels=binary(crop,128);
    for(let offset=0;offset<pixels.length;offset+=4) {
      if(pixels[offset+3]!==before[offset+3])throw new Error('Shared quantization changed alpha silhouette: '+id);
      if(pixels[offset+3])actualColors.add('#'+pixels.subarray(offset,offset+3).toString('hex'));
    }
    const png=await sharp(pixels,{raw:{width:info.width,height:info.height,channels:4}}).png({compressionLevel:9,adaptiveFiltering:false}).toBuffer();
    pending[index][1]=png;
    report.assets[id].sha256=digest(png);
    report.assets[id].shared_palette={combined_sha256:digest(combined),cell:[left,top,cell,cell],native_rect:[left,top,info.width,info.height]};
  }
  if(actualColors.size>256)throw new Error('Shared palette exceeds 256 opaque colors.');
  report.shared_palette={method:SHARED_RULE,grid:[columns,rows],cell:[cell,cell],assets:REQUIRED,colours_requested:256,dither:0,effort:10,opaque_colors_actual:actualColors.size,colors:[...actualColors].sort(),combined_sha256:digest(combined),alpha:'Binary threshold 128; exact original silhouette verified.'};
}

export async function importStaging(config,{root=process.cwd(),palette=config.palette_default??'off'}={}) {
  if(!PALETTE_MODES.includes(palette)) throw new Error('Palette must be off, common96 or shared256.');
  root=resolve(root);
  const sharp=loadSharp(), {bytes,manifest,ids}=await inputs(root,config);
  const work=local(root,config.work_dir), staging=local(root,config.staging_dir);
  const stagingRelative=relative(resolve(root,'game/assets/sprites/art-v2'),staging);
  if(stagingRelative.startsWith('..')||stagingRelative.startsWith('/')) throw new Error('Staging output must remain inside game/assets/sprites/art-v2.');
  const layout=JSON.parse(await readFile(join(work,'references','layout.json'),'utf8'));
  if(layout.base_manifest_sha256!==digest(bytes)) throw new Error('Production manifest changed after prepare; review the immutable backup first.');
  if(!bytes.equals(await readFile(join(work,'before','manifest.json')))) throw new Error('Backup manifest mismatch.');
  const output=paletteDirectory(staging,palette);
  const colors=Object.values(config.material_ramps).flat().map(hex=>[1,3,5].map(at=>parseInt(hex.slice(at,at+2),16)));
  const current=JSON.parse(await readFile(local(root,config.manifest),'utf8'));
  const result=structuredClone(current), report={version:1,palette,palette_rule:palette==='common96'?PALETTE_RULE:palette==='shared256'?SHARED_RULE:'No color quantization.',model_requested:config.model_requested,model_note:'Recorded requested ID; importer does not infer effective model from pixels. Linked catalog verification is not a response model attestation.',base_manifest_sha256:digest(bytes),sources:{},assets:{}};
  const pending=[];
  for(const [name,group]of Object.entries(config.groups)) {
    const reference=layout.groups[name];
    if(!reference||JSON.stringify(reference.assets.map(x=>x.id))!==JSON.stringify(group.assets)) throw new Error('Reference group mismatch: '+name);
    if(digest(await readFile(local(root,reference.reference)))!==reference.reference_sha256) throw new Error('Reference sheet changed after prepare: '+name);
    const source=await readFile(local(root,group.source)),prompt=await readFile(local(root,group.prompt));
    const metadata=await sharp(source).metadata();
    if(metadata.format!=='png'||metadata.width!==reference.size[0]||metadata.height!==reference.size[1]) throw new Error('Source must be PNG at exact reference dimensions: '+name);
    if(!group.opaque&&!metadata.hasAlpha) throw new Error('Cutout source requires real alpha; no automatic background replacement: '+name);
    const promptHash=digest(prompt),sourceHash=digest(source);
    const lineage=await sourceLineage(root,config,name,group,sourceHash);
    report.sources[name]={path:group.source,sha256:sourceHash,prompt:group.prompt,prompt_sha256:promptHash,reference:reference.reference,reference_sha256:reference.reference_sha256,source_offset:group.source_offset??[0,0],asset_corrections:group.asset_corrections??{},lineage};
    for(const entry of reference.assets) {
      const id=entry.id,correction=group.asset_corrections?.[id]??{};
      if(digest(await readFile(join(work,'before',id+'.png')))!==entry.original_sha256) throw new Error('Backup asset changed after prepare: '+id);
      const rect=[...(correction.rect??entry.rect)], delta=correction.offset??[0,0],batch=group.source_offset??[0,0];
      rect[0]+=delta[0]+batch[0];rect[1]+=delta[1]+batch[1];
      const [x,y,w,h]=rect,[nw,nh]=entry.size;
      if(x<0||y<0||w<1||h<1||x+w>metadata.width||y+h>metadata.height||w*nh!==h*nw) throw new Error('Correction is out of bounds or changes aspect: '+id);
      const raw=await sharp(source).extract({left:x,top:y,width:w,height:h}).resize(nw,nh,{kernel:'nearest'}).ensureAlpha().raw().toBuffer();
      let pixels=binary(raw,config.alpha_threshold);
      if(group.opaque&&pixels.some((v,i)=>i%4===3&&v!==255)) throw new Error('Terrain must remain opaque: '+id);
      if(palette==='common96') pixels=quantize(pixels,colors);
      if(!alphaBounds(pixels,nw,nh)) throw new Error('Imported asset is empty: '+id);
      const png=await sharp(pixels,{raw:{width:nw,height:nh,channels:4}}).png({compressionLevel:9,adaptiveFiltering:false}).toBuffer();
      const file=join(output,id+'.png');
      const assetLineage=structuredClone(lineage);
      if(assetLineage.alignment) {
        assetLineage.alignment.measurement=assetLineage.alignment.measurements.find(item=>item.id===id);
        delete assetLineage.alignment.measurements;
      }
      const provenance={source:group.source,source_sha256:sourceHash,prompt:group.prompt,prompt_sha256:promptHash,reference_sha256:reference.reference_sha256,source_rect:rect,native_size:entry.size,alpha_threshold:config.alpha_threshold,palette,model_requested:config.model_requested,original_sha256:entry.original_sha256,sha256:digest(png),lineage:assetLineage};
      result.assets[id]={...result.assets[id],path:'res://'+relative(resolve(root,'game'),file).split('\\').join('/'),art_direction:provenance};
      report.assets[id]=provenance;
      pending.push([file,png]);
    }
  }
  assert.equal(pending.length,REQUIRED);
  if(palette==='shared256')await quantizeShared(pending,ids,report,sharp);
  for(const [id,asset]of Object.entries(current.assets)) if(!ids.includes(id)) assert.deepEqual(result.assets[id],asset);
  // Validate the full batch before publishing any staging files. Production untouched.
  for(const [file,png]of pending) await atomic(file,png);
  result.art_direction={status:'staging_not_activated',report:'res://'+relative(resolve(root,'game'),join(output,'provenance.json')).split('\\').join('/'),palette,replacements:ids};
  await atomic(join(output,'provenance.json'),jsonBytes(report));
  await atomic(join(output,'manifest.json'),jsonBytes(result));
  return {manifest:join(output,'manifest.json'),assets:pending.length,palette};
}

/** The only operation that publishes sprites. Calling prepare/import never reaches it. */
export async function activateStaging(config,{root=process.cwd(),palette=config.palette_default??'off'}={}) {
  if(!PALETTE_MODES.includes(palette))throw new Error('Palette must be off, common96 or shared256.');
  root=resolve(root);
  const sharp=loadSharp(), {bytes,manifest,ids,current}=await inputs(root,config);
  const work=local(root,config.work_dir),staging=local(root,config.staging_dir);
  const selected=paletteDirectory(staging,palette);
  const staged=JSON.parse(await readFile(join(selected,'manifest.json'),'utf8'));
  const reportBytes=await readFile(join(selected,'provenance.json')), report=JSON.parse(reportBytes);
  if(staged.art_direction?.status!=='staging_not_activated'||report.base_manifest_sha256!==digest(bytes)||report.palette!==palette||report.model_requested!==config.model_requested) throw new Error('Staging provenance does not match the selected pack.');
  if(JSON.stringify(staged.art_direction.replacements)!==JSON.stringify(ids)||Object.keys(report.assets).length!==REQUIRED)throw new Error('Staging replacement set mismatch.');
  const packed=[],packedColors=new Set();
  for(const id of ids) {
    const entry=staged.assets[id],provenance=report.assets[id];
    assert.deepEqual(entry.size,manifest.assets[id].size,'Staging changed native size: '+id);
    assert.deepEqual(current.assets[id].size,manifest.assets[id].size,'Production geometry changed: '+id);
    assert.deepEqual(entry.art_direction,provenance,'Staging provenance mismatch: '+id);
    const file=imagePath(root,entry.path);
    if(file!==join(selected,id+'.png'))throw new Error('Staged PNG is outside selected pack: '+id);
    const png=await readFile(file),raw=await sharp(png).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    if(digest(png)!==provenance.sha256||raw.info.width!==entry.size[0]||raw.info.height!==entry.size[1]||raw.data.some((n,i)=>i%4===3&&n!==0&&n!==255))throw new Error('Staged PNG hash/geometry/alpha invalid: '+id);
    if(palette==='shared256')for(let offset=0;offset<raw.data.length;offset+=4)if(raw.data[offset+3])packedColors.add('#'+raw.data.subarray(offset,offset+3).toString('hex'));
    packed.push({id,png,entry,provenance});
  }
  if(palette==='shared256') {
    if(packedColors.size>256||report.shared_palette?.assets!==REQUIRED||report.shared_palette?.opaque_colors_actual!==packedColors.size)throw new Error('Shared palette count/provenance mismatch.');
    assert.deepEqual(report.shared_palette.colors,[...packedColors].sort(),'Shared palette colors must describe actual PNGs.');
  }
  const packHash=digest(jsonBytes({palette,assets:packed.map(item=>[item.id,item.provenance.sha256]),report_sha256:digest(reportBytes)}));
  const acceptedDir=join(work,'accepted',packHash.slice(0,16));
  const accepted={version:1,pack_sha256:packHash,palette,base_manifest_sha256:digest(bytes),model_requested:config.model_requested,report_sha256:digest(reportBytes),assets:{}};
  const active=structuredClone(current);
  for(const {id,png,entry,provenance}of packed) {
    const source=join(acceptedDir,id+'.png');
    await immutable(source,png);
    accepted.assets[id]={path:relative(root,source),sha256:digest(png),size:entry.size,provenance};
    active.assets[id]={...active.assets[id],art_direction:{...provenance,accepted_source:relative(root,source),accepted_sha256:digest(png)}};
  }
  await immutable(join(acceptedDir,'provenance.json'),reportBytes);
  await immutable(join(acceptedDir,'accepted.json'),jsonBytes(accepted));
  // Model/provenance metadata is deliberately mixed: only the listed environment
  // assets change; character/UI/vehicle batches retain their existing provenance.
  active.generation={...active.generation,environment_overrides:{version:2,pack_sha256:packHash,accepted:relative(root,join(work,'accepted.json')),palette,replacements:ids,model_requested:config.model_requested}};
  active.art_direction={status:'active',pack_sha256:packHash,palette,replacements:ids,accepted:relative(root,join(work,'accepted.json'))};
  for(const {id,png}of packed)await atomic(imagePath(root,active.assets[id].path),png);
  await atomic(join(work,'accepted.json'),jsonBytes(accepted));
  await atomic(local(root,config.manifest),jsonBytes(active));
  return {assets:packed.length,palette,accepted:join(work,'accepted.json'),manifest:local(root,config.manifest),pack_sha256:packHash};
}

/** Called by the ordinary catalog builder; no image generation or activation. */
export async function applyAcceptedCatalog(catalog,{root=process.cwd()}={}) {
  root=resolve(root);
  const currentBytes=await maybeRead(resolve(root,'game/assets/sprites/manifest.json'));
  const current=currentBytes?JSON.parse(currentBytes):{};
  const acceptedBytes=await maybeRead(resolve(root,'output/imagegen/art-v2/accepted.json'));
  catalog.manifest={...current,...catalog.manifest,assets:structuredClone(current.assets??{})};
  if(!acceptedBytes)return catalog;
  const accepted=JSON.parse(acceptedBytes), ids=Object.keys(accepted.assets??{});
  const config=JSON.parse(await readFile(resolve(root,'scripts/art-direction.json'),'utf8'));
  const {manifest,ids:expected}=await inputs(root,config);
  if(accepted.version!==1||ids.length!==REQUIRED||ids.some(id=>!expected.includes(id)))throw new Error('Accepted pack has an invalid replacement set.');
  const sharp=loadSharp();
  for(const id of ids) {
    const item=accepted.assets[id];
    const source=local(root,item.path);
    if(!relative(resolve(root,'output/imagegen/art-v2/accepted'),source)||relative(resolve(root,'output/imagegen/art-v2/accepted'),source).startsWith('..'))throw new Error('Accepted source must be in accepted pack.');
    const bytes=await readFile(source),meta=await sharp(bytes).metadata();
    assert.deepEqual(item.size,manifest.assets[id].size,'Accepted pack changed native size: '+id);
    if(digest(bytes)!==item.sha256||meta.format!=='png'||meta.width!==item.size[0]||meta.height!==item.size[1])throw new Error('Accepted pack damaged or changed: '+id);
    const index=catalog.assets.findIndex(asset=>asset.id===id);
    if(index<0)throw new Error('Accepted asset missing in normal catalog: '+id);
    const sheet='accepted_v2_'+id;
    catalog.sheets[sheet]={path:item.path,grid:[1,1],background:'alpha',alpha_threshold:128};
    catalog.assets[index]={id,sheet,columns:[0],rows:[0],size:item.size,trim:false,fit:'fill'};
    catalog.manifest.assets[id]={...catalog.manifest.assets[id],art_direction:{...item.provenance,accepted_source:item.path,accepted_sha256:item.sha256}};
  }
  catalog.manifest.generation={...catalog.manifest.generation,environment_overrides:{version:2,pack_sha256:accepted.pack_sha256,accepted:'output/imagegen/art-v2/accepted.json',palette:accepted.palette,replacements:ids,model_requested:accepted.model_requested}};
  catalog.manifest.art_direction={status:'active',pack_sha256:accepted.pack_sha256,palette:accepted.palette,replacements:ids,accepted:'output/imagegen/art-v2/accepted.json'};
  return catalog;
}

async function selfTest(config,root) {
  const sharp=loadSharp(), {bytes,manifest,ids,currentBytes}=await inputs(root,config);
  const temporary=await mkdtemp(join(tmpdir(),'my-city-art-direction-'));
  let checks=0;
  try {
    const colors=Object.values(config.material_ramps).flat().map(hex=>[1,3,5].map(at=>parseInt(hex.slice(at,at+2),16)));
    for(const sample of [[98,120,60],[129,134,54],[54,72,34],[152,163,81]]) {
      const mapped=quantize(Buffer.from([...sample,255]),colors);
      assert(mapped[1]>mapped[0]&&mapped[1]>mapped[2],'olive/leaf midtones must remain visibly green');checks++;
    }
    for(const sample of [[137,93,61],[32,45,52]]) {
      assert.deepEqual(quantize(Buffer.from([...sample,255]),colors),Buffer.from([...sample,255]),'warm wood and dark metal keep their exact palette identity');checks++;
    }
    await mkdir(dirname(local(temporary,config.manifest)),{recursive:true});
    await writeFile(local(temporary,config.manifest),bytes);
    await mkdir(join(temporary,'scripts'),{recursive:true});
    await writeFile(join(temporary,'scripts/art-direction.json'),jsonBytes(config));
    const originals=new Map();
    for(const id of Object.keys(manifest.assets)) {
      const destination=imagePath(temporary,manifest.assets[id].path);
      const png=await readFile(imagePath(root,manifest.assets[id].path));
      await mkdir(dirname(destination),{recursive:true});
      await writeFile(destination,png);
      originals.set(id,png);
    }
    const layout=await prepareReferences(config,{root:temporary});
    await prepareReferences(config,{root:temporary});checks++;
    const fixture=structuredClone(config);
    for(const [name,group]of Object.entries(fixture.groups)) {
      group.source=layout.groups[name].reference;
      group.prompt=fixture.work_dir+'/prompts/'+name+'.txt';
      await mkdir(dirname(local(temporary,group.prompt)),{recursive:true});
      await writeFile(local(temporary,group.prompt),'Local reference round-trip, no generated image.');
    }
    // Check raw→aligned lineage using copied reference bytes, not generated art.
    const linked=structuredClone(fixture),linkedGroup=linked.groups.buildings;
    const rawSource=linkedGroup.source,rawBytes=await readFile(local(temporary,rawSource));
    linkedGroup.source=config.work_dir+'/aligned/buildings.png';
    await mkdir(dirname(local(temporary,linkedGroup.source)),{recursive:true});
    await writeFile(local(temporary,linkedGroup.source),rawBytes);
    const alignmentPath=local(temporary,config.work_dir+'/aligned/provenance.json');
    const alignment={version:1,groups:{buildings:{raw_source:rawSource,raw_sha256:digest(rawBytes),aligned_sha256:digest(rawBytes),assets:layout.groups.buildings.assets.map(item=>({id:item.id,source_rect:item.rect,native_canvas:item.size,native_placement:[0,0,...item.size],reference_scale:item.scale}))}}};
    const alignmentBytes=jsonBytes(alignment);
    await writeFile(alignmentPath,alignmentBytes);
    await writeFile(local(temporary,config.work_dir+'/model-verification.json'),jsonBytes({model_requested:config.model_requested,catalog_model_id:config.model_requested,catalog_http:200,checked_on:'synthetic fixture, no HTTP call'}));
    await writeFile(local(temporary,config.work_dir+'/buildings-generation.json'),jsonBytes({model_requested:config.model_requested,catalog_verified:true,model_response:null,cli_exit_status:0,command_arguments:['--model',config.model_requested,'--out',rawSource,'--prompt-file',linkedGroup.prompt]}));
    const evidence=await sourceLineage(temporary,linked,'buildings',linkedGroup,digest(rawBytes));
    assert.equal(evidence.alignment.sha256,digest(alignmentBytes));checks++;
    assert.equal(evidence.alignment.raw_sha256,digest(rawBytes));checks++;
    assert.equal(evidence.generation.model_response,null,'catalog evidence must not invent a response-model attestation');checks++;
    assert.equal(evidence.model_verification.catalog_model_id,config.model_requested);checks++;
    await assert.rejects(()=>sourceLineage(temporary,linked,'buildings',linkedGroup,'0'.repeat(64)),/provenance hash mismatch/);checks++;
    const linkedImport=await importStaging(linked,{root:temporary});
    const linkedManifest=JSON.parse(await readFile(linkedImport.manifest,'utf8'));
    assert.deepEqual(linkedManifest.assets.cafe.art_direction.lineage.alignment.measurement,alignment.groups.buildings.assets[0]);checks++;
    assert(!('measurements' in linkedManifest.assets.cafe.art_direction.lineage.alignment),'individual assets link only their own alignment measurement');checks++;
    const imported=await importStaging(fixture,{root:temporary});
    const staged=JSON.parse(await readFile(imported.manifest,'utf8'));
    for(const id of ids) {
      const original=await sharp(imagePath(temporary,manifest.assets[id].path)).ensureAlpha().raw().toBuffer();
      const final=await sharp(imagePath(temporary,staged.assets[id].path)).ensureAlpha().raw().toBuffer();
      assert.deepEqual(final,binary(original,config.alpha_threshold),id+' round-trip exact pixels');checks++;
      assert.deepEqual(staged.assets[id].size,manifest.assets[id].size);checks++;
    }
    for(const [id,asset]of Object.entries(manifest.assets)) if(!ids.includes(id)){assert.deepEqual(staged.assets[id],asset);checks++;}
    const capped=await importStaging(fixture,{root:temporary,palette:'common96'}), paletteManifest=JSON.parse(await readFile(capped.manifest,'utf8'));
    const allowed=new Set(Object.values(config.material_ramps).flat().map(c=>c.slice(1).toLowerCase()));
    for(const id of ids) {
      const data=await sharp(imagePath(temporary,paletteManifest.assets[id].path)).ensureAlpha().raw().toBuffer();
      for(let i=0;i<data.length;i+=4)if(data[i+3])assert(allowed.has(data.subarray(i,i+3).toString('hex')));
      checks++;
    }
    const shared=await importStaging(fixture,{root:temporary,palette:'shared256'});
    const sharedManifest=JSON.parse(await readFile(shared.manifest,'utf8'));
    const sharedReport=JSON.parse(await readFile(join(dirname(shared.manifest),'provenance.json'),'utf8'));
    const sharedColors=new Set(),paletteHashes=new Set();
    for(const id of ids) {
      const image=await sharp(imagePath(temporary,sharedManifest.assets[id].path)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
      const original=binary(await sharp(imagePath(temporary,manifest.assets[id].path)).ensureAlpha().raw().toBuffer(),128);
      assert.deepEqual([image.info.width,image.info.height],manifest.assets[id].size);checks++;
      for(let index=0;index<image.data.length;index+=4) {
        assert.equal(image.data[index+3],original[index+3],id+' binary silhouette remains exact');
        if(image.data[index+3])sharedColors.add('#'+image.data.subarray(index,index+3).toString('hex'));
      }
      checks++;
      assert.equal(digest(await readFile(imagePath(temporary,sharedManifest.assets[id].path))),sharedManifest.assets[id].art_direction.sha256);checks++;
      paletteHashes.add(sharedManifest.assets[id].art_direction.shared_palette.combined_sha256);
    }
    assert(sharedColors.size<=256&&sharedColors.size>1);checks++;
    assert.equal(paletteHashes.size,1,'all environment pieces use the same optimization');checks++;
    assert.deepEqual(sharedReport.shared_palette.colors,[...sharedColors].sort());checks++;
    for(const [id,asset]of Object.entries(manifest.assets))if(!ids.includes(id)){assert.deepEqual(sharedManifest.assets[id],asset);checks++;}
    const changed=Buffer.from(bytes);changed[0]=0;
    await assert.rejects(()=>immutable(join(local(temporary,config.work_dir),'before/manifest.json'),changed),/Immutable backup differs/);checks++;
    fixture.groups.buildings.source_offset=[500,0];
    await assert.rejects(()=>importStaging(fixture,{root:temporary}),/out of bounds/);checks++;
    fixture.groups.buildings.source_offset=[0,0];
    // Explicit activation is exercised only in this isolated temporary project.
    const activated=await activateStaging(fixture,{root:temporary,palette:'shared256'});
    const accepted=JSON.parse(await readFile(activated.accepted,'utf8'));
    const active=JSON.parse(await readFile(activated.manifest,'utf8'));
    for(const id of ids) {
      assert.equal(digest(await readFile(imagePath(temporary,active.assets[id].path))),accepted.assets[id].sha256);checks++;
      assert.equal(active.assets[id].path,manifest.assets[id].path);checks++;
    }
    for(const [id,asset]of Object.entries(manifest.assets))if(!ids.includes(id)) {
      assert.deepEqual(active.assets[id],asset);checks++;
      assert.deepEqual(await readFile(imagePath(temporary,asset.path)),originals.get(id));checks++;
    }
    const repeated=await prepareReferences(config,{root:temporary});
    assert.deepEqual(repeated,layout,'prepare after activation still uses immutable original canvases');checks++;
    await importStaging(fixture,{root:temporary});checks++;
    assert.deepEqual(await readFile(join(local(temporary,config.work_dir),'before/manifest.json')),bytes);checks++;

    // Reproduce ordinary catalog overlays and the normal importer. All source
    // files and destinations are temporary; no production manifest is rebuilt.
    const normalCatalog=JSON.parse(await readFile(resolve(root,'scripts/sprite-catalog.json'),'utf8'));
    for(const sheet of Object.values(normalCatalog.sheets)) {
      const destination=local(temporary,sheet.path);
      await mkdir(dirname(destination),{recursive:true});
      await writeFile(destination,await readFile(local(root,sheet.path)));
    }
    await applyAcceptedCatalog(normalCatalog,{root:temporary});
    const rebuilt=await prepareSprites(normalCatalog,{projectRoot:temporary,outputDir:'game/assets/sprites'});
    for(const id of ids) {
      assert.equal(digest(await readFile(imagePath(temporary,rebuilt.manifest.assets[id].path))),accepted.assets[id].sha256,'normal reimport preserves accepted bytes: '+id);checks++;
      assert.equal(rebuilt.manifest.assets[id].art_direction.accepted_sha256,accepted.assets[id].sha256);checks++;
    }
    for(const [id,asset]of Object.entries(manifest.assets))if(!ids.includes(id)) {
      assert.deepEqual(rebuilt.manifest.assets[id],asset,'normal reimport preserves metadata: '+id);checks++;
      assert.deepEqual(await readFile(imagePath(temporary,asset.path)),originals.get(id),'normal reimport preserves protected PNG: '+id);checks++;
    }
    const tampered=local(temporary,accepted.assets[ids[0]].path);
    await writeFile(tampered,Buffer.from('not accepted PNG'));
    await assert.rejects(()=>applyAcceptedCatalog(normalCatalog,{root:temporary}));checks++;
    assert.deepEqual(await readFile(local(root,config.manifest)),currentBytes);checks++;
    return checks;
  } finally { await rm(temporary,{recursive:true,force:true}); }
}

async function main() {
  const [command,...args]=process.argv.slice(2), options={};
  for(let i=0;i<args.length;i+=2) {
    if(!['--root','--config','--palette'].includes(args[i])||!args[i+1])throw new Error('Unknown or missing argument.');
    options[args[i].slice(2)]=args[i+1];
  }
  const root=resolve(options.root??process.cwd());
  const config=JSON.parse(await readFile(local(root,options.config??'scripts/art-direction.json'),'utf8'));
  if(command==='prepare') {
    const layout=await prepareReferences(config,{root});
    console.log(JSON.stringify({assets:REQUIRED,references:Object.fromEntries(Object.entries(layout.groups).map(([name,g])=>[name,{path:g.reference,size:g.size}])),layout:config.work_dir+'/references/layout.json'},null,2));
  } else if(command==='import') console.log(JSON.stringify(await importStaging(config,{root,palette:options.palette??config.palette_default}),null,2));
  else if(command==='activate') console.log(JSON.stringify(await activateStaging(config,{root,palette:options.palette??config.palette_default}),null,2));
  else if(command==='self-test') console.log('ART DIRECTION: '+await selfTest(config,root)+' checks passed; local reference round-trip only.');
  else throw new Error('Usage: node scripts/art-direction.mjs prepare|import|activate|self-test [--palette off|common96|shared256]');
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
