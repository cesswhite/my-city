extends SceneTree
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	var start := Vector2(280, 180)
	var cardinal: Vector2 = Navigation.move_direction(start, Vector2.RIGHT, 12)
	var diagonal: Vector2 = Navigation.move_direction(start, Vector2.ONE, 12)
	expect(cardinal.is_equal_approx(Vector2(292, 180)), "cardinal input moves the requested distance on free ground")
	expect(absf(start.distance_to(diagonal) - 12.0) < 0.001, "diagonal input has the same speed as cardinal input")
	expect(absf(diagonal.x - start.x - (diagonal.y - start.y)) < 0.001, "diagonal movement distributes the normalized direction equally")
	expect(Navigation.move_direction(start, Vector2(5, 5), 12).is_equal_approx(diagonal), "input magnitude cannot increase movement speed")
	expect(Navigation.move_direction(start, Vector2(1.0e30, 1.0e30), 12).is_equal_approx(diagonal), "large finite headings normalize without overflow")
	expect(Navigation.move_direction(start, Vector2.LEFT, 0.25).is_equal_approx(Vector2(279.75, 180)), "fractional final substep preserves short-frame distance")

	var fountain: Vector2 = Navigation.move_direction(Vector2(192, 232), Vector2.RIGHT, 10000)
	expect(Navigation.is_walkable(fountain) and fountain.x < 204 and fountain.y == 232, "large frame spike stops at the near edge of the fountain without tunneling")
	var reverse_fountain: Vector2 = Navigation.move_direction(Vector2(284, 232), Vector2.LEFT, 10000)
	expect(Navigation.is_walkable(reverse_fountain) and reverse_fountain.x >= 265, "fountain collision works from the opposite side")
	var table: Vector2 = Navigation.move_direction(Vector2(196, 182), Vector2.RIGHT, 100, "player")
	expect(Navigation.is_walkable(table, "player") and table.x < 207, "manual movement cannot cross the interior table")
	var bed: Vector2 = Navigation.move_direction(Layout.stand_at("bed"), Vector2.LEFT, 100, "cesar")
	expect(Navigation.is_walkable(bed, "cesar") and bed.x >= 161, "manual movement cannot cross a bed")
	var slide: Vector2 = Navigation.move_direction(Vector2(200, 178), Vector2.ONE, 20, "player")
	expect(Navigation.is_walkable(slide, "player") and slide.x < 207 and absf(slide.y - 178 - 20 / sqrt(2.0)) < 0.001, "blocked diagonal slides along the table wall")
	var corner := Vector2(203.75, 220.25)
	var corner_result: Vector2 = Navigation.move_direction(corner, Vector2(1, -1), 1)
	expect(corner_result.x == corner.x and corner_result.y < 220, "diagonal cannot clip across a fountain corner between pixel samples")

	var doorstep: Vector2 = Navigation.move_direction(Navigation.door_positions().player, Vector2.UP, 100)
	expect(Navigation.is_walkable(doorstep) and doorstep.y >= Navigation.STREET_BOUNDS.position.y, "front door movement stops at the building instead of entering automatically")
	var indoor_exit: Vector2 = Navigation.move_direction(Vector2(236, 264), Vector2.DOWN, 100, "player")
	expect(Navigation.is_walkable(indoor_exit, "player") and indoor_exit.x == 236 and indoor_exit.y < Navigation.INTERIOR_BOUNDS.end.y, "indoor exit remains a room boundary without an automatic portal")
	var immense: Vector2 = Navigation.move_direction(start, Vector2.RIGHT, 1.0e24)
	expect(Navigation.is_walkable(immense) and immense.x < Navigation.STREET_BOUNDS.end.x, "enormous finite distance terminates at a wall without crossing it")
	var grazing: Vector2 = Navigation.move_direction(Vector2(200, 178), Vector2(0.00002, 1), 1.0e24, "player")
	expect(Navigation.is_walkable(grazing, "player") and grazing.x < 204, "near-parallel sliding limits frame work instead of creeping indefinitely along a wall")

	expect(Navigation.move_direction(start, Vector2.ZERO, 10) == start, "zero input does not move")
	expect(Navigation.move_direction(start, Vector2.RIGHT, 0) == start, "zero distance does not move")
	expect(Navigation.move_direction(start, Vector2.RIGHT, -1) == start, "negative distance is rejected")
	expect(Navigation.move_direction(start, Vector2(INF, 1), 10) == start, "infinite direction is rejected")
	expect(Navigation.move_direction(start, Vector2(NAN, 1), 10) == start, "NaN direction is rejected")
	expect(Navigation.move_direction(start, Vector2.RIGHT, INF) == start, "infinite distance is rejected")
	expect(Navigation.move_direction(start, Vector2.RIGHT, NAN) == start, "NaN distance is rejected")
	var invalid_origin := Vector2(INF, 10)
	expect(Navigation.move_direction(invalid_origin, Vector2.LEFT, 10) == invalid_origin, "invalid origin is returned unchanged rather than recovered")
	var in_fountain := Vector2(236, 236)
	expect(Navigation.move_direction(in_fountain, Vector2.RIGHT, 10) == in_fountain, "solid origin does not teleport to free ground")
	expect(Navigation.move_direction(start, Vector2.RIGHT, 10, "unknown") == start, "unknown room does not permit movement")
	print("KEYBOARD NAVIGATION: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
