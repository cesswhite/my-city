/** Merge the calibrated modular character catalog with measured scenery crops. No AI calls. */
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {applyAcceptedCatalog} from './art-direction.mjs';
const body=JSON.parse(await readFile(new URL('./sprite-body-catalog.json',import.meta.url),'utf8'));
const layout=JSON.parse(await readFile(new URL('../game/data/world_layout.json',import.meta.url),'utf8'));
const catalog={...body,sheets:{...body.sheets},assets:[...body.assets],manifest:{...body.manifest,generation:{model:'gpt-image-2.5-sunburst-2026-09-08',date:'2026-09-23',format:'png',sources:'output/imagegen',prompts:'output/imagegen/prompts',mode:'official imagegen CLI generate-batch + edit + generate',processing:'Measured alpha crops, nearest-neighbor native size, binary alpha, calibrated material masks; no procedural art fallback.'}}};
for(const id of ['buildings','terrain','outdoors','interiors','ui'])catalog.sheets[id]={path:`output/imagegen/${id}.png`,grid:id==='buildings'?[3,2]:[4,4],background:id==='terrain'?'none':'alpha',alpha_threshold:128};
function item(id,sheet,crop,size,fit='contain'){catalog.assets.push({id,sheet,crop_space:'sheet',crop,size,fit,trim:true});}
// Measured opaque regions. AI sheets are not assumed to obey their requested cell borders.
item('cafe','buildings',[45,45,449,403],[113,110]);
item('homes','buildings',[548,98,442,352],[88,82]);
item('alma_home','buildings',[1110,94,338,366],[49,73]);
item('workshop','buildings',[23,561,589,385],[128,106]);
item('player_home','buildings',[651,564,384,380],[40,54]);
item('shop','buildings',[1083,590,430,366],[54,30]);
const terrain=['tile_grass','tile_sand','tile_plaza','tile_wood','tile_wall','tile_wall_sage','tile_wall_peach','tile_wall_lavender','tile_soil','tile_water','tile_rug_red','tile_rug_teal','tile_stone','tile_roof','tile_brick','tile_timber'];
terrain.forEach((id,i)=>catalog.assets.push({id,sheet:'terrain',columns:[i%4],rows:[Math.floor(i/4)],size:[32,32],trim:false,fit:'fill'}));
item('rug','terrain',[512,512,256,256],[126,86],'fill');
item('exit_mat','terrain',[768,512,256,256],[40,21],'fill');
const outdoors=[
 ['tree',[15,15,282,304],[42,56]],['tree_small',[308,81,185,233],[33,47]],
 ['fountain',[532,126,229,182],[61,46]],['bench',[787,156,223,145],[36,18]],
 ['cafe_table',[28,373,218,166],[38,23]],['planter',[280,391,219,136],[76,43]],
 ['garden',[529,406,234,120],[107,72]],['flowerpot',[819,338,159,206],[16,22]],
 ['fence',[28,603,219,130],[32,17]],['bunting',[248,594,279,113],[96,23]],
 ['bicycle_fixed',[520,568,247,165],[44,34]],['bicycle_broken',[772,556,235,189],[44,34]],
 ['item_oil',[91,823,107,164],[18,24]],['item_seeds',[315,836,163,151],[22,24]],
 ['item_tea',[573,827,140,162],[22,24]],['lamp',[857,742,73,261],[10,39]]
];outdoors.forEach(([id,crop,size])=>item(id,'outdoors',crop,size));
item('garden_left','outdoors',[540,417,105,97],[24,22]);
item('garden_right','outdoors',[646,417,105,97],[24,22]);
const interiors=[
 ['bed',[48,25,157,232],[70,84]],['table',[265,72,239,161],[88,52]],
 ['cabinet',[529,75,223,161],[84,49]],['bookshelf',[790,50,212,193],[80,36]],
 ['window',[20,277,217,223],[75,34]],['chair',[314,277,141,216],[24,20]],
 ['tea_set',[541,289,202,205],[66,28]],['project_tools',[790,291,214,200],[44,47]],
 ['notebooks',[29,532,204,216],[32,28]],['photo',[277,548,216,171],[42,27]],
 ['plant',[539,509,208,239],[24,39]],['project_painting',[803,506,184,248],[44,47]],
 ['project_basket',[22,782,217,204],[44,47]],['project_seeds',[269,783,236,203],[44,47]],
 ['tea_ready',[551,771,182,210],[66,28]],['planter_seeded',[775,792,239,182],[76,43]]
];interiors.forEach(([id,crop,size])=>item(id,'interiors',crop,size));
const ui=['button_normal','button_hover','button_primary','button_pressed','panel','message_panel','input','input_focus','button_disabled','tooltip','tab_selected','focus_outline','scroll_track','scroll_thumb','scroll_active','button_secondary'];
const xs=[57,295,533,770],ys=[57,287,520,750],hs=[190,192,189,194];
ui.forEach((id,i)=>item(`ui_${id}`,'ui',[xs[i%4],ys[Math.floor(i/4)],198,hs[Math.floor(i/4)]],[24,24],'fill'));
// Reimport the measured sources at one shared logical scale; never enlarge tiny PNGs.
for (const asset of catalog.assets) {
  if (layout.sprite_sizes[asset.id]) asset.size=[...layout.sprite_sizes[asset.id]];
  if (asset.id==='planter') {
    // Preserve top padding from the source so both planter states occupy 38px in
    // their shared 42px canvas. Their proportions and bottom anchor stay intact.
    asset.crop=[280,370,218,145];
    asset.trim=false;
  }
}
await applyAcceptedCatalog(catalog,{root:fileURLToPath(new URL('..',import.meta.url))});
await writeFile(new URL('./sprite-catalog.json',import.meta.url),JSON.stringify(catalog,null,2)+'\n');
console.log(`Sprite catalog: ${catalog.assets.length} measured assets.`);
