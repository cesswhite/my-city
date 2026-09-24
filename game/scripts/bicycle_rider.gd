extends RefCounted
## A seated rider assembled exclusively from native, tinted character atlas regions.
## The caller supplies idle character_layers; this helper never loads SpriteArt.
const FRAME := Vector2(24,32)
const PEDALS := [Vector2(3,0),Vector2(0,2),Vector2(-3,0),Vector2(0,-2)]
static var _poses: Dictionary = {}

static func facing(direction: Vector2) -> Vector2:
	if not direction.is_finite() or direction.is_zero_approx(): return Vector2.DOWN
	if absf(direction.x) > absf(direction.y): return Vector2.LEFT if direction.x < 0 else Vector2.RIGHT
	return Vector2.UP if direction.y < 0 else Vector2.DOWN

static func hip_offset(direction: Vector2, pose: Dictionary = {}) -> Vector2:
	var side: Vector2 = facing(direction)
	var fallback := Vector2(-6,-16) if side == Vector2.RIGHT else Vector2(6,-16) if side == Vector2.LEFT else Vector2(-1,-18) if side == Vector2.UP else Vector2(-1,-23)
	return _point(pose.get("hip_offset"),fallback)

static func _crank(direction: Vector2, pose: Dictionary) -> Vector2:
	var fallback := Vector2(5,10) if direction == Vector2.RIGHT else Vector2(-6,10) if direction == Vector2.LEFT else Vector2(1,11) if direction == Vector2.UP else Vector2(1,15)
	return _point(pose.get("crank_from_hip"),fallback)

static func _hand(direction: Vector2, pose: Dictionary) -> Vector2:
	var fallback := Vector2(12,-3) if direction == Vector2.RIGHT else Vector2(-12,-3) if direction == Vector2.LEFT else Vector2(0,-7) if direction == Vector2.UP else Vector2(0,3)
	return _point(pose.get("hand_from_hip"),fallback)

static func _hand_span(pose: Dictionary) -> int:
	var value = pose.get("hand_span",7)
	if (value is float or value is int) and is_finite(float(value)): return clampi(roundi(float(value)),1,12)
	return 7

static func actor_rect(at: Vector2, direction: Vector2 = Vector2.DOWN, pose: Dictionary = {}) -> Rect2:
	if not at.is_finite(): return Rect2()
	var side: Vector2 = facing(direction)
	var hip: Vector2 = at.round() + hip_offset(side,pose)
	# Include all four pedal phases and handlebar reach, even with supplied poses.
	var crank: Vector2 = _crank(side,pose)
	var hand: Vector2 = _hand(side,pose)
	var span: float = 2.0 if side in [Vector2.LEFT,Vector2.RIGHT] else float(_hand_span(pose)+1)
	var lean: float = side.x*3.0
	var first := Vector2(minf(-12+lean,minf(crank.x-4,hand.x-span)),minf(-23,hand.y-2))
	var last := Vector2(maxf(12+lean,maxf(crank.x+5,hand.x+span+2)),maxf(15,maxf(crank.y+5,hand.y+3)))
	return Rect2(hip+first,last-first)

static func _point(value, fallback: Vector2) -> Vector2:
	if value is Vector2 and value.is_finite(): return value.round()
	if value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
		var point := Vector2(float(value[0]),float(value[1]))
		if point.is_finite(): return point.round()
	return fallback

static func _piece(result: Array[Dictionary], layer: Dictionary, source: Rect2, position: Vector2, transpose: bool = false) -> void:
	if not layer.get("texture") is Texture2D or not layer.get("source") is Rect2: return
	var frame: Rect2 = layer.source
	if frame.size != FRAME or not Rect2(Vector2.ZERO,FRAME).encloses(source): return
	var offset: Vector2 = _point(layer.get("offset"),Vector2.ZERO)
	var size := Vector2(source.size.y,source.size.x) if transpose else source.size
	result.append({"texture":layer.texture,"source":Rect2(frame.position+source.position,source.size),
		"rect":Rect2((position+offset).round(),size),"tint":layer.get("tint",Color.WHITE),"transpose":transpose,
		"id":str(layer.get("id",""))})

static func _limb(result: Array[Dictionary], layer: Dictionary, start: Vector2, finish: Vector2, source: Rect2) -> void:
	# Short, integer staircase of original two-pixel atlas strips. No new pixels,
	# image allocation, scaling, rotations or deformation of the head/accessories.
	var distance: int = maxi(abs(roundi(finish.x-start.x)),abs(roundi(finish.y-start.y)))
	var count: int = maxi(1,ceili(float(distance)/2.0))
	for index in count+1:
		_piece(result,layer,source,start.lerp(finish,float(index)/count).round())

static func _legs(result: Array[Dictionary], layers: Array[Dictionary], hip: Vector2, direction: Vector2, moving: bool, phase: int, pose: Dictionary, far: bool) -> void:
	var side: bool = direction in [Vector2.LEFT,Vector2.RIGHT]
	var sign_x: int = -1 if direction == Vector2.LEFT else 1
	var cycle: int = posmod(phase,4) if moving else 0
	var pedal: Vector2 = PEDALS[posmod(cycle+(2 if far else 0),4)]
	var crank: Vector2 = _crank(direction,pose)
	var leg_side: int = -1 if far else 1
	var root: Vector2 = hip + Vector2(-1 if far else 1,0)
	# Head-on views retain a one-pixel depth cue at the middle of the pedal turn.
	var front_height: float = pedal.y+signf(pedal.x)
	var foot: Vector2 = hip + crank + (Vector2(pedal.x*sign_x,pedal.y) if side else Vector2(leg_side*3,front_height))
	var knee: Vector2 = hip + Vector2(sign_x*(5+(1 if cycle in [1,2] else 0)),3+(1 if far else 0)) if side else hip + Vector2(leg_side*4,3+(1 if front_height > 0 else 0))
	for original: Dictionary in layers:
		var layer: Dictionary = original
		if far:
			layer = original.duplicate()
			layer.tint = layer.get("tint",Color.WHITE)*Color(0.8,0.8,0.8,1.0)
		if layer.get("id","") == "char_pants":
			var sample_x: int = 10 if far else 12
			_limb(result,layer,root,knee,Rect2(sample_x,25,2,2))
			_limb(result,layer,knee,foot-Vector2(0,1),Rect2(sample_x,25,2,2))
		elif layer.get("id","") == "char_details":
			_piece(result,layer,Rect2(9 if far else 12,28,3,2),foot-Vector2(1,0))

static func _arm(result: Array[Dictionary], layers: Array[Dictionary], hip: Vector2, direction: Vector2, pose: Dictionary, far: bool) -> void:
	var side: bool = direction in [Vector2.LEFT,Vector2.RIGHT]
	var sign_x: int = -1 if direction == Vector2.LEFT else 1
	var leg_side: int = -1 if far else 1
	var shoulder: Vector2 = hip+Vector2(sign_x*3 if side else leg_side*4,-5 if side else -4)
	var hand: Vector2 = hip+_hand(direction,pose)
	if side:
		if far: shoulder += Vector2(-sign_x,-1); hand += Vector2(0,-1)
	else: hand += Vector2(leg_side*_hand_span(pose),0)
	var elbow: Vector2 = shoulder.lerp(hand,0.5).round()+Vector2(0,1)
	for layer: Dictionary in layers:
		match str(layer.get("id","")):
			"char_shirt": _limb(result,layer,shoulder,elbow,Rect2(11,19,2,2))
			"char_body":
				var source := Rect2(13,20,2,2) if direction == Vector2.LEFT else Rect2(9,20,2,2) if direction == Vector2.RIGHT else Rect2(8,21,1,2)
				_limb(result,layer,elbow,hand,source)

static func _assemble(layers: Array[Dictionary], moving: bool, phase: int, direction: Vector2, pose: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var side: Vector2 = facing(direction)
	var hip: Vector2 = hip_offset(side,pose)
	var origin := hip-Vector2(12,23)
	var lean := Vector2(side.x*3,0)
	_legs(result,layers,hip,side,moving,phase,pose,true)
	_arm(result,layers,hip,side,pose,true)
	for layer: Dictionary in layers:
		# The upper body leans as one rigid piece: the face and accessories are
		# translated, never stretched or rotated. Three native waist rows join it.
		_piece(result,layer,Rect2(0,0,24,20),origin+lean)
		var id: String = str(layer.get("id",""))
		if id in ["char_body","char_shirt","char_pants","char_details"]:
			var torso_x: int = 9 if side == Vector2.LEFT else 11 if side == Vector2.RIGHT else 9
			var torso_width: int = 4 if side in [Vector2.LEFT,Vector2.RIGHT] else 6
			for row in 3:
				_piece(result,layer,Rect2(torso_x,20+row,torso_width,1),origin+Vector2(torso_x+side.x*(2-row),20+row))
		else:
			_piece(result,layer,Rect2(0,20,24,3),origin+Vector2(0,20)+lean)
	_legs(result,layers,hip,side,moving,phase,pose,false)
	_arm(result,layers,hip,side,pose,false)
	return result

static func _relative_parts(layers: Array[Dictionary], moving: bool, phase: int, direction: Vector2, pose: Dictionary) -> Array[Dictionary]:
	var signature: Array = [facing(direction),posmod(phase,4) if moving else 0,pose]
	for layer: Dictionary in layers:
		if not layer.get("texture") is Texture2D: continue
		signature.append([layer.texture.get_rid(),layer.get("id"),layer.get("source"),layer.get("tint"),layer.get("offset")])
	var key: int = hash(signature)
	if not _poses.has(key):
		# Bounded appearance/pose cache: no texture readbacks or limb allocations
		# during repeated frames; changed clothes or direction get their own pose.
		if _poses.size() >= 64: _poses.erase(_poses.keys().front())
		_poses[key] = _assemble(layers,moving,phase,direction,pose)
	return _poses[key]

static func parts(at: Vector2, layers: Array[Dictionary], moving: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN, pose: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not at.is_finite(): return result
	for original: Dictionary in _relative_parts(layers,moving,phase,direction,pose):
		var part: Dictionary = original.duplicate()
		part.rect.position += at.round()
		result.append(part)
	return result

static func draw(canvas: CanvasItem, at: Vector2, layers: Array[Dictionary], moving: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN, pose: Dictionary = {}) -> void:
	if not at.is_finite(): return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for part: Dictionary in _relative_parts(layers,moving,phase,direction,pose):
		canvas.draw_texture_rect_region(part.texture,Rect2(at.round()+part.rect.position,part.rect.size),part.source,part.tint,part.transpose)
