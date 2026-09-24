#!/usr/bin/env python3
"""Deterministic import of the five authorized generated growth assets only.
Run with .venv/bin/python scripts/import-environment-sprites.py.
No generation/network and no writes to previously generated environment sprites.
"""
from pathlib import Path
from io import BytesIO
from PIL import Image
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/imagegen/environment-growth/source.png'
MANIFEST=ROOT/'game/assets/sprites/manifest.json'
ASSETS=[('tree_sapling',(18,26),0),('tree_young',(26,36),1),('apple',(8,9),2),('apple_golden',(8,9),3),('window_closed',(28,29),4)]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write_changed(path,data):
 if not path.exists() or path.read_bytes()!=data:path.write_bytes(data)
manifest=json.loads(MANIFEST.read_text())
colors=set()
for entry in manifest['assets'].values():
 if 'art_direction' not in entry:continue
 image=Image.open(ROOT/'game'/entry['path'].removeprefix('res://')).convert('RGBA')
 colors.update(px[:3] for px in image.get_flattened_data() if px[3]>=128)
assert colors, 'Existing shared environment palette required'
palette=sorted(colors)
greens=[p for p in palette if p[1]>p[0] and p[1]>p[2]]
source=Image.open(SOURCE).convert('RGBA'); assert source.size==(1024,1536)
report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':sha(SOURCE),'model_requested':'gpt-image-2.5-sunburst-2026-09-08','palette_opaque_colors':len(colors),'alpha_threshold':250,'assets':{}}
cache={}
for name,size,index in ASSETS:
 cell=((index%2)*512,(index//2)*512,(index%2+1)*512,(index//2+1)*512)
 tile=source.crop(cell)
 alpha=tile.getchannel('A').point(lambda a:255 if a>=250 else 0)
 bbox=alpha.getbbox(); assert bbox
 tile.putalpha(alpha)
 cropped=tile.crop(bbox)
 # Native canvases are final authored stage sizes. No runtime tree scaling.
 if name.startswith('tree_'):
  ratio=min(size[0]/cropped.width,size[1]/cropped.height)
  native_size=(max(1,round(cropped.width*ratio)),max(1,round(cropped.height*ratio)))
  small=cropped.resize(native_size,Image.Resampling.NEAREST)
  final=Image.new('RGBA',size);final.alpha_composite(small,((size[0]-small.width)//2,size[1]-small.height))
 else:final=cropped.resize(size,Image.Resampling.NEAREST)
 pixels=[]
 for r,g,b,a in final.get_flattened_data():
  if not a:pixels.append((0,0,0,0));continue
  key=(r,g,b)
  if key not in cache:
   candidates=greens if g>r*1.02 and g>b*1.08 and max(r,g,b)-min(r,g,b)>30 else palette
   cache[key]=min(candidates,key=lambda p:2*(r-p[0])**2+4*(g-p[1])**2+3*(b-p[2])**2)
  pixels.append((*cache[key],255))
 final.putdata(pixels)
 path=ROOT/'game/assets/sprites'/f'{name}.png'
 encoded=BytesIO();final.save(encoded,format='PNG');write_changed(path,encoded.getvalue())
 entry={'path':'res://assets/sprites/'+name+'.png','size':list(size),'anchor':[size[0]//2,size[1]],'environment_growth':{'source':str(SOURCE.relative_to(ROOT)),'source_sha256':sha(SOURCE),'source_cell':list(cell),'source_alpha_bounds':list(bbox),'native_size':list(size),'model_requested':report['model_requested'],'model_response':None,'palette':'existing shared environment colors; nearest weighted RGB, green material protected, no dithering'}}
 manifest['assets'][name]=entry
 report['assets'][name]={'size':list(size),'opaque_bounds':list(final.getchannel('A').getbbox()),'sha256':sha(path),'source_cell':list(cell),'source_alpha_bounds':list(bbox)}
write_changed(MANIFEST,(json.dumps(manifest,indent=2)+'\n').encode())
# Full catalog rebuilds retain separately imported generated pieces as explicit
# passthrough assets, the same contract as directional bicycle atlases.
for catalog_name in ['sprite-body-catalog.json','sprite-catalog.json']:
 path=ROOT/'scripts'/catalog_name
 catalog=json.loads(path.read_text())
 entries=catalog.setdefault('manifest',{}).setdefault('assets',{})
 for name,_,_ in ASSETS:entries[name]=manifest['assets'][name]
 write_changed(path,(json.dumps(catalog,indent=2)+'\n').encode())
(ROOT/'output/imagegen/environment-growth/import.json').write_text(json.dumps(report,indent=2)+'\n')
# Integer zoom contact sheet is a QA artifact, never used as production art.
preview=Image.new('RGBA',(720,320),(32,45,39,255))
for i,(name,size,index) in enumerate(ASSETS):
 im=Image.open(ROOT/'game/assets/sprites'/f'{name}.png').convert('RGBA');im=im.resize((size[0]*4,size[1]*4),Image.Resampling.NEAREST);preview.alpha_composite(im,(i*144+16,180-im.height))
preview.save(ROOT/'artifacts/environment-growth/assets-4x.png')
print('Imported five native sprites; shared palette:',len(colors),'colors; old assets untouched')
