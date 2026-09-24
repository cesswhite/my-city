/** Import the verified GPT Images 2.5 sheet without synthesizing new artwork. */
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {loadSharp} from './prepare-sprites.mjs';

const sharp = loadSharp();
const source = 'output/imagegen/bicycle-directions-source.png';
const output = 'game/assets/sprites/bicycle_riding.png';
const metadata = 'output/imagegen/bicycle-directions-provenance.json';
const bounds = [[75,54,106,167],[20,58,216,133],[20,58,216,133],[75,31,106,168]];
const sizes = [[17,27],[34,21],[34,21],[17,27]];
const directions = ['down','left','right','up'];
const opaqueBounds = {};
const content = await readFile(source);
const original = await sharp(content).metadata();
if (original.width !== 1024 || original.height !== 1024 || !original.hasAlpha) throw new Error('Expected inspected 1024×1024 RGBA sheet');
const composites = [];
for (let row=0; row<4; row++) {
  let left=40, top=32, right=0, bottom=0;
  for (let col=0; col<4; col++) {
    const [x,y,width,height] = bounds[row], [w,h] = sizes[row];
    const {data,info} = await sharp(content).extract({left:col*256+x,top:row*256+y,width,height})
      .resize(w,h,{kernel:'nearest',fit:'fill'}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    for (let i=0;i<data.length;i+=4) {
      data[i+3] = data[i+3]>=180 ? 255 : 0;
      if (!data[i+3]) data.fill(0,i,i+3);
    }
    const input = await sharp(data,{raw:info}).png().toBuffer();
    const offsetX=Math.floor((40-w)/2), offsetY=31-h;
    for (let py=0;py<h;py++) for (let px=0;px<w;px++) {
      if (!data[(py*w+px)*4+3]) continue;
      left=Math.min(left,offsetX+px); top=Math.min(top,offsetY+py);
      right=Math.max(right,offsetX+px+1); bottom=Math.max(bottom,offsetY+py+1);
    }
    composites.push({input,left:col*40+offsetX,top:row*32+offsetY});
  }
  if (right<=left || bottom<=top) throw new Error('Empty direction: '+directions[row]);
  opaqueBounds[directions[row]]=[left,top,right-left,bottom-top];
}
await mkdir('game/assets/sprites',{recursive:true});
await sharp({create:{width:160,height:128,channels:4,background:{r:0,g:0,b:0,alpha:0}}})
  .composite(composites).png().toFile(output);
const manifestPath = 'game/assets/sprites/manifest.json';
const manifest = JSON.parse(await readFile(manifestPath,'utf8'));
manifest.assets.bicycle_riding = {path:'res://assets/sprites/bicycle_riding.png',size:[160,128],frame_size:[40,32],frames:4,directions,anchor:[20,30],opaque_bounds:opaqueBounds};
await writeFile(manifestPath,JSON.stringify(manifest,null,2)+'\n');
const provenance=JSON.parse(await readFile(metadata,'utf8'));
provenance.source_sha256=createHash('sha256').update(content).digest('hex');
provenance.atlas_sha256=createHash('sha256').update(await readFile(output)).digest('hex');
provenance.prompt_sha256=createHash('sha256').update(await readFile('output/imagegen/bicycle-directions-prompt.txt')).digest('hex');
provenance.import={script:'scripts/import-bicycle-sprites.mjs',output,cell:[40,32],directions:manifest.assets.bicycle_riding.directions,frames:4,row_crops:bounds,row_native_sizes:sizes,alpha_threshold:180,processing:'Fixed per-row measured alpha crops, nearest-neighbor native sizing, binary alpha and shared ground anchor; all visible pixels originate in the generated sheet.'};
await writeFile(metadata,JSON.stringify(provenance,null,2)+'\n');
console.log('Imported 16 bicycle sprites: '+output);
