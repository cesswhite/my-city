/** Calibrate inspected generated cutouts to the existing native pixel envelopes.
 * Only crops/composes/resamples generated pixels; no new artwork or API calls.
 * Keep raw sources untouched and record every measured rectangle and transform.
 */
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {loadSharp} from './prepare-sprites.mjs';
const sharp=loadSharp(), root='output/imagegen/art-v2';
const layout=JSON.parse(await readFile(`${root}/references/layout.json`));
const measurements=JSON.parse(await readFile('scripts/art-source-alignment.json'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const report={version:1,method:'Inspected source rectangles, uniform nearest scaling, original native alpha envelope, bottom-center anchoring, binary alpha. No synthesized pixels.',groups:{}};
await mkdir(`${root}/aligned`,{recursive:true});
for(const group of ['buildings','outdoors','interiors']) {
  const source=await readFile(`${root}/sources/${group}.png`), spec=layout.groups[group];
  if(hash(source)!==measurements.source_sha256?.[group]) throw new Error('Source changed; measure and review crops again: '+group);
  const composite=[], entries=[];
  for(const entry of spec.assets) {
    const crop=measurements[group][entry.id];
    if(!crop)throw new Error('Missing measured crop: '+entry.id);
    const [x,y,w,h]=crop, [ax,ay,aw,ah]=entry.alpha_bounds;
    const factor=Math.min(aw/w,ah/h);
    const width=Math.max(1,Math.round(w*factor)),height=Math.max(1,Math.round(h*factor));
    const left=ax+Math.floor((aw-width)/2),top=ay+ah-height;
    const raw=await sharp(source).extract({left:x,top:y,width:w,height:h}).resize(width,height,{kernel:'nearest'}).ensureAlpha().raw().toBuffer();
    for(let i=3;i<raw.length;i+=4){raw[i]=raw[i]>=128?255:0;if(!raw[i])raw.fill(0,i-3,i);}
    const png=await sharp(raw,{raw:{width,height,channels:4}}).resize(width*entry.scale,height*entry.scale,{kernel:'nearest'}).png().toBuffer();
    composite.push({input:png,left:entry.rect[0]+left*entry.scale,top:entry.rect[1]+top*entry.scale});
    entries.push({id:entry.id,source_rect:crop,native_canvas:entry.size,native_placement:[left,top,width,height],reference_scale:entry.scale});
  }
  const output=await sharp({create:{width:spec.size[0],height:spec.size[1],channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite(composite).png().toBuffer();
  await writeFile(`${root}/aligned/${group}.png`,output);
  report.groups[group]={raw_source:`${root}/sources/${group}.png`,raw_sha256:hash(source),aligned_sha256:hash(output),assets:entries};
}
await writeFile(`${root}/aligned/provenance.json`,JSON.stringify(report,null,2)+'\n');
console.log('Aligned 38 inspected generated cutouts; original files and game geometry unchanged.');
