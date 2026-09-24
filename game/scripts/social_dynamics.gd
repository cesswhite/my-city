extends RefCounted
## Event-driven, subjective impressions. Never infers another person's feelings.
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const INCLUSION_ORIGIN := "Impresión personal de inclusión"
const RECEIPT_LIMIT := 256
var _world: WeakRef
var _receipts: Dictionary = {}

func setup(world) -> void:
	_world = weakref(world)
	_receipts.clear()

func _ready_world() -> bool:
	return _world != null and _world.get_ref() != null

func _awake(id: String) -> bool:
	if not _ready_world(): return false
	var world = _world.get_ref()
	return world.is_present(id) and not world.is_sleeping(id)

func _near(a: String, b: String, radius: float = 45.0) -> bool:
	if a == b or not _awake(a) or not _awake(b): return false
	var world = _world.get_ref()
	var first: Dictionary = world.get_resident(a)
	var second: Dictionary = world.get_resident(b)
	return world._distance(first,second) < radius and Navigation._clear_segment(Layout.point(first.pos),Layout.point(second.pos),str(first.room))

func _once(key: String) -> bool:
	if _receipts.has(key): return false
	_receipts[key] = true
	while _receipts.size() > RECEIPT_LIMIT: _receipts.erase(_receipts.keys()[0])
	return true

func note_exchange(a: String, b: String, first: String, second: String, event_id: String) -> void:
	if event_id.is_empty() or first.strip_edges().is_empty() or second.strip_edges().is_empty() or not _near(a,b): return
	if not _once("exchange:"+event_id.left(120)): return
	_impression(a,b)
	_impression(b,a)
	for witness: Dictionary in _world.get_ref().active_residents():
		if witness.id in [a,b] or not _near(str(witness.id),a) or not _near(str(witness.id),b): continue
		_inclusion(str(witness.id),a,b)

func _impression(owner: String, partner: String) -> void:
	# The player chooses their own feelings; this subsystem gives autonomy to NPCs.
	if owner == "player": return
	var world = _world.get_ref()
	var relation: Dictionary = world.relationship_for(owner,partner)
	var name: String = world.get_resident(partner).name
	if relation.frustration >= 55 or relation.tolerance <= 25:
		world.social_knowledge.note_opinion(owner,partner,"En una charla con %s me costó entenderme y sentí ganas de tomar distancia." % name,"personal","rivalry")
	elif relation.trust >= 60 and relation.affection >= 45 and relation.frustration < 25:
		world.social_knowledge.note_opinion(owner,partner,"Me sentí a gusto hablando con %s y tuve ganas de seguir conociéndole." % name,"personal","friendship")
	if owner != "lupita" or partner != "mateo": return
	var authored: Dictionary = world.social_knowledge.knowledge_for(owner,"lupita_mateo_admiration")
	if authored.is_empty() or authored.source_id != owner: return
	if relation.trust >= 75 and relation.affection >= 70 and relation.frustration < 20:
		world.social_knowledge.note_opinion(owner,partner,"Al conversar con Mateo sentí interés e ilusión por conocerlo mejor; no sé si él siente lo mismo.","secret","emerging_interest")

func _inclusion(owner: String, a: String, b: String) -> void:
	if owner == "player": return
	var world = _world.get_ref()
	var person: Dictionary = world.get_resident(owner)
	# A persisted private episode caps this reaction across save/load, per witness/day.
	var day: int = int(world.minute / 1440)
	for index in range(person.memories.size()-1,-1,-1):
		var memory: Dictionary = person.memories[index]
		if int(memory.get("minute",-1)) < day * 1440: break
		if memory.get("kind","") == "sentimiento" and memory.get("origin","") == INCLUSION_ORIGIN and int(memory.get("minute",-1440) / 1440) == day: return
	var candidates: Array[String] = [a,b]
	candidates.sort()
	for friend in candidates:
		var relation: Dictionary = world.relationship_for(owner,friend)
		# Mere friendship or observing a conversation is not enough to imply jealousy.
		if relation.trust < 65 or relation.affection < 60 or relation.tolerance > 50: continue
		var text := "Al ver a %s platicando, me dieron ganas de participar y me sentí un poco fuera; no sé si fue intencional." % str(world.get_resident(friend).name)
		var claim: String = world.social_knowledge.note_opinion(owner,friend,text,"personal","inclusion")
		if claim.is_empty(): return
		var state: Dictionary = person.relationships[friend]
		world._social._recover(state,person,friend)
		state.frustration = minf(100.0,float(state.frustration)+2.0)
		var memory: Dictionary = world._memory("sentimiento",[owner],text,INCLUSION_ORIGIN)
		world._remember(person,memory)
		return

func note_world_memory(owner: String, memory: Dictionary) -> void:
	if owner == "player" or not _awake(owner): return
	var world = _world.get_ref()
	if memory.get("kind","") not in ["ayuda","comunidad"] or memory.get("origin","") != "actividad presencial verificada": return
	if int(memory.get("minute",-1)) != world.minute or memory.get("heard_from",owner) != owner: return
	var participants = memory.get("participants",[])
	if not participants is Array or participants.is_empty() or owner not in participants: return
	var actor: String = str(participants[0])
	if not _near(owner,actor,52.0): return
	var memory_id: String = str(memory.get("id",""))
	if memory_id.is_empty(): return
	var recorded := false
	for own_memory: Dictionary in world.get_resident(owner).memories:
		if own_memory.get("id","") == memory_id and own_memory == memory:
			recorded = true
			break
	if not recorded or not _once("help:"+owner+":"+memory_id): return
	var text := "Después de ver colaborar a %s, me dieron ganas de hacer equipo con esa persona." % str(world.get_resident(actor).name)
	world.social_knowledge.note_opinion(owner,actor,text,"personal","alliance")
