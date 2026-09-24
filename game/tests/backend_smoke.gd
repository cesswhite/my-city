extends SceneTree
## Run through backend/tests/godot_fixture.ts, which owns the temporary server.

const Stream = preload("res://scripts/dialogue_stream.gd")
const EXPECTED := " ¡Hola, César! ¿Vamos al huerto? 🌿 "
var checks: int = 0
var failures: int = 0
var fragments: Array[String] = []
var completions: Array[Dictionary] = []
var errors: Array[String] = []
var first_delta_at: int = -1
var completed_at: int = -1

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var token := OS.get_environment("MY_CITY_DEV_TOKEN")
	var base_url := OS.get_environment("MY_CITY_API_URL")
	if token.length() < 32 or base_url != "http://127.0.0.1:18787":
		push_error("Run this fixture using bun run test:godot from backend.")
		quit(1)
		return
	var stream = Stream.new()
	root.add_child(stream)
	stream.delta.connect(func(value: String):
		if first_delta_at < 0: first_delta_at = Time.get_ticks_msec()
		fragments.append(value))
	stream.completed.connect(func(value: Dictionary):
		completed_at = Time.get_ticks_msec()
		completions.append(value))
	stream.failed.connect(func(message: String): errors.append(message))
	var result: Error = stream.start(base_url + "/dialogue/stream", PackedStringArray([
		"Authorization: Bearer " + token,
		"Content-Type: application/json",
	]), {
		"resident": {"id": "cesar", "biography": "Creció en el campo."},
		"utterance": "Hola, César.",
		"speaker": {"id": "player", "name": "Alex"},
	})
	_check(result == OK, "inicia transporte HTTP real hacia Worker local")
	var started := Time.get_ticks_msec()
	while stream.busy and Time.get_ticks_msec() - started < 16000:
		await process_frame
	_check(errors.is_empty(), "Worker acepta Authorization y Content-Type del cliente real")
	_check(fragments.size() == 2 and "".join(fragments) == EXPECTED, "fragmentos UTF-8 conservan espacios y emoji")
	_check(completions.size() == 1, "recibe un único done")
	_check(first_delta_at >= 0 and completed_at - first_delta_at >= 150, "muestra primer fragmento antes de terminar la generación")
	if completions.size() == 1:
		var done: Dictionary = completions[0]
		_check(done.get("text") == EXPECTED, "texto final exacto a concatenación")
		_check(done.get("source") == "openai" and done.get("model") == "gpt-6-luna", "contrato OpenAI del proveedor de prueba")
		_check(done.get("ttft_ms", -1) >= 0 and done.get("total_ms", 0) >= done.get("ttft_ms", 0), "métricas reales del transporte de prueba")
	_check(not stream.busy, "termina espera después de done")
	# Reuse the production transport for a real HTTP error response from Worker.
	fragments.clear()
	completions.clear()
	errors.clear()
	var payload := {"resident": {"id": "cesar", "biography": "Creció en el campo."}, "utterance": "Hola de nuevo.", "speaker": {"id": "player", "name": "Alex"}}
	var headers := PackedStringArray(["Authorization: Bearer " + token, "Content-Type: application/json"])
	_check(stream.start(base_url + "/dialogue/stream", headers, payload) == OK, "reutiliza la conexión para una respuesta HTTP de error")
	started = Time.get_ticks_msec()
	while stream.busy and Time.get_ticks_msec() - started < 16000: await process_frame
	_check(stream.failure_code == "upstream_busy" and stream.failure_http_status == 503, "HTTP 503 conserva el código del servicio tras leer el cuerpo JSON")
	_check(errors == ["El proveedor está ocupado; espera antes de reintentar."] and fragments.is_empty() and completions.is_empty(), "error HTTP real llega como mensaje y no como diccionario ni conversación")
	fragments.clear()
	completions.clear()
	errors.clear()
	_check(stream.start(base_url + "/dialogue/stream", headers, payload) == OK and stream.failure_code.is_empty(), "un reintento limpia la clasificación previa antes de recibir nuevos bytes")
	started = Time.get_ticks_msec()
	while stream.busy and Time.get_ticks_msec() - started < 16000: await process_frame
	_check(stream.failure_code == "upstream_incomplete" and stream.failure_http_status == 200, "HTTP 200 con error SSE conserva la causa real de interrupción")
	_check(fragments == ["Respuesta incompleta"] and errors.size() == 1 and completions.is_empty() and not stream.busy, "una interrupción después del primer fragmento nunca confirma un diálogo incompleto")
	stream.free()
	print("RESULT: %d/%d backend loopback checks passed (mocked provider)." % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
