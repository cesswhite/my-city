extends SceneTree
## Export only synthetic, engine-filtered contexts for mocked backend integration.
const Colony = preload("res://scripts/colony.gd")
var rows: Array = []

func _init() -> void:
	var world = Colony.new()
	world.save_path = "user://never-written-social-context-fixture.json"
	world.setup(false, true)
	world.settlement_jobs.autonomous_enabled = false
	var ledger = world.social_knowledge
	add_row(world, "public own opinion", "alma", "player", "rincones", "alma_preserve_corners")
	var secret: String = ledger.claim("lupita_meal_worry").text
	var withheld := world.context_for("lupita", "player", "comida")
	rows.append({"name":"withheld private detail", "context":withheld, "excluded_text":secret})
	var relation: Dictionary = world.get_resident("mateo").relationships.player
	relation.trust = 80.0
	relation.affection = 60.0
	relation.frustration = 0.0
	relation.cooldown_until = 0
	var share_day := -1
	for day in 30:
		world.minute = day * 1440 + 720
		if ledger.can_share("mateo", "player", "lupita_meal_worry"):
			share_day = day
			break
	if share_day < 0:
		push_error("No deterministic share day found in fixture")
		quit(1)
		return
	place(world, "mateo", [240,210])
	place(world, "player", [260,210])
	if not ledger.transfer("mateo", "player", "lupita_meal_worry", "", "fixture-disclosure"):
		push_error("Core refused synthetic physical disclosure")
		quit(1)
		return
	add_row(world, "authorized third-party disclosure", "mateo", "player", "comida", "lupita_meal_worry")
	place(world, "lupita", [240,210])
	ledger.note_exchange("player", "lupita", secret, "¿Cómo lo supiste?", "fixture-recognition")
	var incident: Dictionary = world.context_for("lupita", "player", "¿Cómo lo supiste?")
	rows.append({"name":"subject own suspicion", "context":incident, "expected_case":true, "excluded_text":secret})
	var output := ProjectSettings.globalize_path("res://../artifacts/social-knowledge/core-contexts.json")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("Exported %d isolated social contexts." % rows.size())
	quit(0)

func add_row(world, title: String, owner: String, partner: String, query: String, claim: String) -> void:
	rows.append({"name":title,"context":world.context_for(owner,partner,query),"expected_claim":claim})

func place(world, id: String, point: Array) -> void:
	var person: Dictionary = world.get_resident(id)
	person.room = "street"
	person.pos = point.duplicate()
	person.target = point.duplicate()
	person.travel_intent = ""
	person.erase("travel_route")
