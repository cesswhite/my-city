extends RefCounted
## Pure native-pixel projection of the persisted environmental snapshot.
## Texture lookup is supplied by SpriteArt, avoiding a preload cycle.
const Crops = preload("res://scripts/crop_sprites.gd")
const Layout = preload("res://scripts/world_layout.gd")
const WORLD := Rect2(12,48,468,244)
const TREE_ASSETS := ["tile_soil","garden_left","tree_sapling","tree_young","tree_small","tree"]
const TREE_SIZES := [Vector2(8,4),Vector2(7,9),Vector2(18,26),Vector2(26,36),Vector2(33,47),Vector2(42,56)]

static func data(state: Dictionary) -> Dictionary:
	var value = state.get("environment",{})
	return value if value is Dictionary else {}

static func curtains_closed(room: String, state: Dictionary, prop_key: String="window") -> bool:
	var household = data(state).get("households",{}).get(room,{})
	return household is Dictionary and bool(household.get("curtains",{}).get(prop_key,false))

static func objects(room: String, base: Array[Dictionary], state: Dictionary) -> Array[Dictionary]:
	var snapshot: Dictionary = data(state)
	var result: Array[Dictionary] = []
	for original: Dictionary in base:
		var object: Dictionary = original.duplicate(true)
		if object.get("id","")=="window" and curtains_closed(room,state,str(object.get("key","window"))):
			object.id="window_closed"
			object.curtains_closed=true
		var watered: Dictionary=snapshot.get("households",{}).get(room,{}).get("watered",{})
		var prop_key: String=str(object.get("key",""))
		var water_age: float=float(snapshot.get("minute",0))-float(watered.get(prop_key,-1000))
		if not Layout.is_outdoor(room) and object.id in ["plant","flowerpot","planter","planter_seeded"] and watered.has(prop_key) and water_age>=0.0 and water_age<10.0:
			object.environment_object=true
			object.environment_kind="watered"
			object.water_freshness=1.0-water_age/10.0
		if object.has("settlement_plot") and not snapshot.is_empty():
			object.environment_object=true
			object.environment_kind="plot"
		result.append(object)
	for cell: Dictionary in snapshot.get("cropcells",[]):
		if str(cell.get("room",""))!=room:continue
		var spec: Dictionary=crop_spec(cell,true)
		if spec.is_empty():continue
		var at: Vector2=_point(cell.get("at",spec.rect.end))
		result.append({"key":"environment_crop_"+str(cell.id),"id":spec.asset,"rect":spec.rect,"y":at.y,"fixed_size":true,"environment_object":true,"environment_kind":"crop","environment_cell":cell.duplicate(true)})
	for tree: Dictionary in snapshot.get("treeplants",[]):
		if str(tree.get("room",""))!=room:continue
		var stage: int=clampi(int(tree.get("stage",0)),0,5)
		var at: Vector2=_point(tree.get("at",Vector2.ZERO))
		var size: Vector2=TREE_SIZES[stage]
		result.append({"key":"environment_tree_"+str(tree.id),"id":TREE_ASSETS[stage],"rect":Rect2((at-Vector2(floor(size.x/2.0),size.y)).round(),size),"support_point":at,"y":at.y,"fixed_size":true,"environment_object":true,"environment_kind":"tree","environment_tree":tree.duplicate(true)})
	for fruit: Dictionary in snapshot.get("fruit",[]):
		if str(fruit.get("room",""))!=room:continue
		var at: Vector2=_point(fruit.get("at",Vector2.ZERO))
		result.append({"key":"environment_fruit_"+str(fruit.id),"id":"apple_golden" if str(fruit.get("kind","apple"))=="golden" else "apple","rect":Rect2((at-Vector2(4,9)).round(),Vector2(8,9)),"y":at.y,"fixed_size":true,"environment_object":true,"environment_kind":"fruit","environment_fruit":str(fruit.get("tree_id","")),"fruit_id":str(fruit.id),"fruit_kind":str(fruit.get("kind","apple")),"tree_id":str(fruit.get("tree_id",""))})
	return result

static func _point(value) -> Vector2:
	if value is Vector2:return value
	if value is Array and value.size()==2:return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO

static func _rect(value) -> Rect2:
	if value is Rect2:return value
	return Layout.rect(value) if value is Array else Rect2()

static func crop_spec(cell: Dictionary, revised: bool=false) -> Dictionary:
	var stage: int=clampi(int(cell.get("stage",0)),0,3)
	if stage==0 or (bool(cell.get("destroyed",false)) and str(cell.get("condition",""))!="regrowing"):return {}
	var variants: Array=Crops.variants(revised)
	var variant: Dictionary=variants[posmod(int(cell.get("index",0)),variants.size())]
	var source: Rect2=variant.source
	var box: Rect2=_rect(cell.get("rect",Rect2()))
	var at: Vector2=_point(cell.get("at",box.position+Vector2(source.size.x/2.0,source.size.y)))
	var origin: Vector2=(box.position+Vector2(4,4)).round() if box.has_area() else (at-Vector2(floor(source.size.x/2.0),source.size.y)).round()
	var rows: int=4 if stage==1 else 7 if stage==2 else int(source.size.y)
	var damaged: bool=str(cell.get("condition","healthy"))=="bent" or bool(cell.get("bent",false))
	var condition: float=0.55 if damaged else 1.0
	var tint: Color=Color("b69364").lerp(Color.WHITE,condition)
	return {"asset":variant.asset,"source":source,"rect":Rect2(origin,source.size),"rows":rows,"tint":tint,"bent":bool(cell.get("bent",false)),"condition":condition}

static func crop_runs(cell: Dictionary, frames: Callable, revised: bool=false) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var spec: Dictionary=crop_spec(cell,revised)
	if spec.is_empty():return result
	var frame: Dictionary=frames.call(spec.asset)
	if frame.is_empty():return result
	var source: Rect2=Rect2(frame.source.position+spec.source.position,spec.source.size)
	for run: Rect2 in Crops._foliage_runs(frame.texture,source):
		if run.position.y<source.end.y-int(spec.rows):continue
		var offset := Vector2.ZERO
		# A trampled stem stays rooted; the upper native rows lean by one/two pixels.
		if bool(spec.bent):
			var distance: int=int(source.end.y-run.position.y)
			offset=Vector2(2 if distance>5 else 1 if distance>2 else 0,1 if distance>3 else 0)
		result.append({"texture":frame.texture,"source":run,"rect":Rect2(spec.rect.position+run.position-source.position+offset,run.size),"tint":spec.tint})
	return result

static func _paint(canvas: CanvasItem, texture: Texture2D, source: Rect2, destination: Rect2, tint: Color=Color.WHITE) -> void:
	var visible: Rect2=destination.intersection(WORLD)
	if not visible.has_area():return
	canvas.draw_texture_rect_region(texture,visible,Rect2(source.position+visible.position-destination.position,visible.size),tint)

static func _soil(canvas: CanvasItem, box: Rect2, frames: Callable) -> void:
	var frame: Dictionary=frames.call("tile_soil")
	if frame.is_empty():return
	var size: Vector2=frame.source.size
	var start: Vector2=WORLD.position+((box.position-WORLD.position)/size).floor()*size
	for y in range(int(start.y),int(ceil(box.end.y)),int(size.y)):
		for x in range(int(start.x),int(ceil(box.end.x)),int(size.x)):
			var destination := Rect2(Vector2(x,y),size)
			var clipped: Rect2=destination.intersection(box)
			_paint(canvas,frame.texture,Rect2(frame.source.position+clipped.position-destination.position,clipped.size),clipped)

static func draw_object(canvas: CanvasItem, object: Dictionary, frames: Callable, revised: bool=false) -> bool:
	if not object.get("environment_object",false):return false
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	match str(object.get("environment_kind","")):
		"plot":
			pass # Target metadata only. Soil belongs below every actor and plant.
		"crop":
			for run: Dictionary in crop_runs(object.environment_cell,frames,revised):_paint(canvas,run.texture,run.source,run.rect,run.tint)
		"tree":
			var tree: Dictionary=object.environment_tree
			if int(tree.stage)==0:_soil(canvas,object.rect,frames)
			elif int(tree.stage)==1:
				var cell: Dictionary={"stage":1,"at":tree.at,"index":0,"condition":100}
				for run: Dictionary in crop_runs(cell,frames,revised):_paint(canvas,run.texture,run.source,run.rect,run.tint)
			else:
				var frame: Dictionary=frames.call(object.id)
				if not frame.is_empty():_paint(canvas,frame.texture,frame.source,object.rect)
		"fruit":
			var frame: Dictionary=frames.call(object.id)
			if not frame.is_empty():_paint(canvas,frame.texture,frame.source,object.rect)
		"watered":
			var frame: Dictionary=frames.call(object.id)
			var freshness: float=float(object.water_freshness)
			if not frame.is_empty():_paint(canvas,frame.texture,frame.source,object.rect,Color.WHITE.lerp(Color("c7dfd6"),freshness*0.35))
			# Tiny transient water feedback is a runtime effect, never a new asset.
			var at: Vector2=(object.rect.position+Vector2(object.rect.size.x-3,5)).round()
			for point: Vector2 in [at,at+Vector2(2,4),at+Vector2(-1,7)]:
				var drop:=Rect2(point,Vector2(1,2))
				if WORLD.encloses(drop):canvas.draw_rect(drop,Color(0.68,0.89,0.89,0.75*freshness))
		_:return false
	return true

static func draw_ground(canvas: CanvasItem, room: String, state: Dictionary, frames: Callable) -> void:
	if data(state).is_empty():return
	for object: Dictionary in Layout.props(room):
		if object.has("settlement_plot"):_soil(canvas,object.rect,frames)
