extends SceneTree
## Scheduler contract only: real geometry, authored catalog, local host spies.
## Knowledge persistence and its trust rules have separate core tests.
const Encounters = preload("res://scripts/social_encounters.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []
class Planner extends RefCounted:
	var queries := 0
	var reverse_only := false
	var result: Dictionary = {"first":"Lupita me confió que le da miedo organizar la comida.","reply":"Prefiero que ella decida cuándo contarlo.","kind":"gossip","topic_id":"lupita_meal_worry"}
	func encounter_pair(a: String,_b: String) -> Dictionary:
		queries+=1
		if reverse_only and a != "ines": return {}
		return result.duplicate(true)
class Jobs extends RefCounted:
	var workers: Array[String] = []
	func busy(id: String) -> bool: return id in workers
class World extends RefCounted:
	const MAX_DISTANCE := 45.0
	var player_autonomy := false
	var conversation_holds: Array[String] = []
	var _routine_keys := {"mateo":"day:morning","ines":"day:morning"}
	var settlement_jobs := Jobs.new()
	var social_dialogue := Planner.new()
	var people: Array[Dictionary] = [
		{"id":"mateo","name":"Mateo","room":"street","pos":[200.0,180.0],"target":[200.0,180.0],"travel_intent":"","activity":"Descansando","present":true,"sleeping":false,"available":true},
		{"id":"ines","name":"Inés","room":"street","pos":[224.0,180.0],"target":[224.0,180.0],"travel_intent":"","activity":"Descansando","present":true,"sleeping":false,"available":true}]
	var records: Array[Dictionary] = []
	var greeting_queries := 0
	func active_residents() -> Array[Dictionary]:
		return people.filter(func(p):return p.present)
	func get_resident(id: String) -> Dictionary:
		for person in people:
			if person.id==id: return person
		return {}
	func is_present(id: String) -> bool: return bool(get_resident(id).get("present",false))
	func is_sleeping(id: String) -> bool: return bool(get_resident(id).get("sleeping",false))
	func daily_state(id: String) -> Dictionary: return {"kind":"sleeping" if is_sleeping(id) else "leisure"}
	func social_available(id: String) -> bool:
		var person := get_resident(id)
		return person.available and person.pos==person.target and not person.has("travel_route")
	func greeting_pair(_a: String,_b: String) -> Dictionary:
		greeting_queries+=1
		return {"first":"Buenas tardes.","reply":"Buenas tardes, Mateo."}
	func record_dialogue(a: String,b: String,first: String,reply: String,source: String) -> bool:
		records.append({"a":a,"b":b,"first":first,"reply":reply,"source":source})
		return true
class Host extends Control:
	var colony := World.new()
	var dialogue_job: Dictionary = {}
	var decision_pending := false
	var deciding_id := ""
	var paths: Dictionary = {}
	var facing: Dictionary = {}
	var ambient_thoughts = null
	func position_of(person: Dictionary) -> Vector2: return Vector2(person.pos[0],person.pos[1])
func _initialize(): call_deferred("run")
func expect(value: bool,text: String):
	checks+=1
	if not value: failures.append(text);push_error(text)
func begin(host: Host) -> RefCounted:
	var encounters := Encounters.new(host)
	encounters.advance(2.2)
	return encounters
func run():
	if "--ui-test" not in OS.get_cmdline_user_args(): quit(1);return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/social_content.json"))
	var ids: Array[String] = []
	expect(catalog.version==1 and catalog.topics.size()>=5 and catalog.topics.size()<=8,"small versioned authored catalog")
	var residents := ["cesar","lupita","mateo","ines","alma","player"]
	for topic: Dictionary in catalog.topics:
		expect(topic.id not in ids,"unique topic "+str(topic.id));ids.append(topic.id)
		expect(topic.owner_id in residents and topic.owner_id in topic.seed_holders,"owner knows own topic "+str(topic.id))
		expect(not topic.text.is_empty() and topic.text.length()<=240 and topic.aliases.size()<=4,"bounded authored text "+str(topic.id))
		expect(topic.kind in ["fact","opinion","rumor","secret"] and topic.privacy in ["public","personal","secret"],"explicit epistemic kind and privacy "+str(topic.id))
		expect("player" not in topic.seed_holders,"no player omniscience "+str(topic.id))
		expect(topic.subjects.all(func(id):return id in residents) and topic.seed_holders.all(func(id):return id in residents),"known fictional people "+str(topic.id))
		if topic.id=="lupita_meal_worry":
			expect(topic.seed_holders==["lupita","mateo"] and topic.origin_label.contains("confió") and topic.leakable,"historical confidence limited to Lupita and Mateo")
		else: expect(topic.seed_holders==[topic.owner_id],"no unrelated starting confidants "+str(topic.id))
		if topic.privacy=="secret": expect(topic.require_trust>=70,"secrets require close trust "+str(topic.id))
	var host := Host.new()
	var schedule := begin(host)
	expect(host.colony.social_dialogue.queries==1 and host.colony.greeting_queries==0,"substantive plan checked before greeting")
	expect(schedule._active.kind=="gossip" and schedule._active.plan.topic_id=="lupita_meal_worry","authored metadata preserved without mutation")
	expect(host.colony.records.is_empty(),"selecting topic does not transmit it")
	expect(host.colony.conversation_holds.size()==2,"gossip reserves only the actual pair")
	expect(not schedule.visible_for("mateo").is_empty() and schedule.visible_for("ines").is_empty(),"first speaker only")
	var turn: float = schedule._active.turn_seconds
	expect(turn>=3.5 and turn<=7.5,"reading time bounded")
	schedule.advance(turn+0.01)
	expect(schedule.visible_for("mateo").is_empty() and not schedule.visible_for("ines").is_empty(),"listener replies without simultaneous bubbles")
	expect(host.colony.records.is_empty(),"partial exchange not committed")
	schedule.advance(turn+0.01)
	expect(host.colony.records.size()==1 and host.colony.records[0].source=="Conversación local · gossip","completed authored exchange uses standard commit")
	expect(host.colony.conversation_holds.is_empty() and schedule._active.is_empty(),"finished exchange releases holds")
	for i in range(120): schedule.advance(0.2)
	expect(host.colony.records.size()==1 and host.colony.social_dialogue.queries==1,"standing together cannot farm a rumor")
	host.free()
	for reason in ["manual_cancel","sleep","absent","area","blocked","job","provider"]:
		host=Host.new();schedule=begin(host)
		match reason:
			"manual_cancel": schedule.cancel_for("mateo")
			"sleep": host.colony.people[1].sleeping=true
			"absent": host.colony.people[1].present=false
			"area": host.colony.people[1].room="homes"
			"blocked":
				host.colony.people[0].pos=[190.0,196.0]
				host.colony.people[1].pos=[190.0,218.0]
			"job": host.colony.settlement_jobs.workers.append("ines")
			"provider": host.dialogue_job={"a":"ines","b":"player"}
		schedule.advance(20)
		expect(schedule._active.is_empty() and host.colony.conversation_holds.is_empty(),"cancel releases "+reason)
		expect(host.colony.records.is_empty(),"no knowledge after interrupted "+reason)
		host.free()
	for reason in ["wall","different_room","sleep","absent","job","decision","provider"]:
		host=Host.new()
		match reason:
			"wall":
				host.colony.people[0].pos=[190.0,196.0];host.colony.people[0].target=[190.0,196.0]
				host.colony.people[1].pos=[190.0,218.0];host.colony.people[1].target=[190.0,218.0]
			"different_room":host.colony.people[1].room="homes"
			"sleep":host.colony.people[1].sleeping=true
			"absent":host.colony.people[1].present=false
			"job":host.colony.settlement_jobs.workers.append("ines")
			"decision":host.decision_pending=true;host.deciding_id="ines"
			"provider":host.dialogue_job={"a":"ines","b":"player"}
		schedule=begin(host)
		expect(schedule._active.is_empty() and host.colony.social_dialogue.queries==0,"eligibility excludes "+reason)
		host.free()
	# Passing greetings preserve a multi-block route and never invent a long talk.
	host=Host.new()
	host.colony.people[0].target=[280.0,180.0]
	host.colony.people[0].travel_intent="cafe"
	host.colony.people[0].travel_route={"destination":"homes","legs":["street","homes"]}
	var prior: Dictionary=host.colony.people[0].duplicate(true)
	schedule=begin(host)
	expect(schedule._active.kind=="greeting" and host.colony.social_dialogue.queries==0,"walking preserves short greeting")
	schedule.advance(5)
	expect(host.colony.people[0].target==prior.target and host.colony.people[0].travel_intent==prior.travel_intent and host.colony.people[0].travel_route==prior.travel_route,"greeting preserves route and target")
	host.free()
	host=Host.new();host.colony.social_dialogue.result={}
	schedule=begin(host)
	expect(schedule._active.kind=="greeting" and host.colony.greeting_queries==1,"empty planner falls back to ordinary greeting")
	schedule.cancel();host.free()
	host=Host.new();host.colony.social_dialogue.result={"first":"","reply":"incomplete","kind":"confrontation"}
	schedule=begin(host)
	expect(schedule._active.kind=="greeting","malformed plan cannot reserve a blank confrontation")
	schedule.cancel();host.free()
	host=Host.new();host.colony.social_dialogue.reverse_only=true
	schedule=begin(host)
	expect(schedule._active.a=="ines" and schedule._active.b=="mateo" and not schedule.visible_for("ines").is_empty(),"reverse plan keeps its real first speaker")
	schedule.advance(20)
	expect(host.colony.records.size()==1 and host.colony.records[0].a=="ines","reverse completion preserves knowledge direction")
	host.free()
	host=Host.new();host.colony.social_dialogue.result.kind="confrontation"
	schedule=begin(host)
	expect(schedule._active.kind=="confrontation","same physical encounter accepts priority confrontation plan")
	var origin: Array=host.colony.people[0].pos.duplicate()
	host.colony._routine_keys.mateo="day:next"
	host.colony.people[0].target=[300.0,180.0]
	schedule.cancel()
	expect(host.colony.people[0].target==[300.0,180.0] and host.colony.people[0].pos==origin,"cancel preserves newer schedule and never teleports")
	host.free()
	print("Social encounters gossip %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
