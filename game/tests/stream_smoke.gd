extends SceneTree

const Stream = preload("res://scripts/dialogue_stream.gd")
var checks: int = 0
var failures: int = 0
var fragments: Array[String] = []
var completions: Array[Dictionary] = []
var errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, title: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func _fixture() -> Node:
	fragments.clear()
	completions.clear()
	errors.clear()
	var stream = Stream.new()
	root.add_child(stream)
	stream._reset_state()
	stream.busy = true
	stream.set_process(false)
	stream.delta.connect(func(value: String): fragments.append(value))
	stream.completed.connect(func(value: Dictionary): completions.append(value))
	stream.failed.connect(func(value: String): errors.append(value))
	return stream

func _run() -> void:
	var stream = _fixture()
	var wire := (": heartbeat\r\n\r\nevent: delta\r\ndata: {\"text\":\"¡Hola, César! 🌿\"}\r\n\r\n"
		+ "event: done\ndata: {\"text\":\"¡Hola, César! 🌿\",\ndata: \"source\":\"fixture\",\"model\":\"fixture\",\"ttft_ms\":3,\"total_ms\":8}\n\n").to_utf8_buffer()
	for value in wire:
		stream._accept_bytes(PackedByteArray([value]))
	_check(fragments == ["¡Hola, César! 🌿"], "UTF-8 multibyte split byte by byte survives intact")
	_check(completions.size() == 1 and completions[0].source == "fixture", "CRLF and multiline data complete exactly once")
	_check(errors.is_empty() and not stream.busy, "done closes cleanly")
	_check(stream.metrics.ttft_ms >= 0 and stream.metrics.total_ms >= stream.metrics.ttft_ms, "local timing metrics measured")
	stream._accept_bytes("event: delta\ndata: {\"text\":\"ignored\"}\n\n".to_utf8_buffer())
	_check(fragments.size() == 1, "trailing events after completion ignored")
	stream.free()

	stream = _fixture()
	var suggestion_wire := ("event: delta\ndata: " + JSON.stringify({"text": "Me gusta cuidar el huerto."}) + "\n\n"
		+ "event: done\ndata: " + JSON.stringify({"text": "Me gusta cuidar el huerto.", "source": "openai", "suggestions": ["¿Qué plantas cuidas?", "¿Por qué te gusta el huerto?"]}) + "\n\n").to_utf8_buffer()
	for value in suggestion_wire: stream._accept_bytes(PackedByteArray([value]))
	_check(fragments == ["Me gusta cuidar el huerto."], "suggestion metadata never enters the visible dialogue fragments")
	_check(completions.size() == 1 and completions[0].get("suggestions") == ["¿Qué plantas cuidas?", "¿Por qué te gusta el huerto?"], "done passes exact short suggestions to the controller without another request")
	_check(errors.is_empty() and not stream.busy, "suggested replies preserve the existing exact-text completion contract")
	stream.free()

	stream = _fixture()
	stream._accept_bytes("event: error\ndata: {\"error\":\"Proveedor no disponible\"}\n\n".to_utf8_buffer())
	_check(errors == ["Proveedor no disponible"] and completions.is_empty(), "error event fails without completion")
	stream.free()

	stream = _fixture()
	stream._response_code = 200
	stream._accept_bytes(("event: error\ndata: " + JSON.stringify({"source": "error", "error": {"code": "invalid_upstream_response", "message": "El stream excedió el límite."}, "discard_partial": true}) + "\n\n").to_utf8_buffer())
	_check(errors == ["El stream excedió el límite."] and stream.failure_code == "invalid_upstream_response", "structured SSE failure retains its code and message without rendering a dictionary")
	_check(stream.failure_http_status == 200 and completions.is_empty(), "HTTP 200 does not hide a provider failure inside SSE")
	stream._reset_state()
	_check(stream.failure_code.is_empty() and stream.failure_message.is_empty() and stream.failure_http_status == 0, "a fresh request clears the previous error classification")
	stream.free()

	stream = _fixture()
	stream._response_code = 503
	var http_error := JSON.stringify({"error": {"code": "upstream_busy", "message": "Servicio ocupado, inténtalo después."}}).to_utf8_buffer()
	for value in http_error: stream._accept_http_error_bytes(PackedByteArray([value]))
	_check(stream.busy and errors.is_empty(), "HTTP error bytes are accumulated without failing before the complete UTF-8 body")
	stream._end_of_stream()
	_check(errors == ["Servicio ocupado, inténtalo después."] and stream.failure_code == "upstream_busy" and stream.failure_http_status == 503, "HTTP JSON failure preserves service classification and status")
	stream.free()

	stream = _fixture()
	stream._response_code = 502
	stream._accept_http_error_bytes("<!doctype html> upstream unavailable".to_utf8_buffer())
	stream._end_of_stream()
	_check(errors == ["El servicio de conversación respondió HTTP 502."] and stream.failure_code == "http_502", "unexpected HTTP error pages never become visible service messages")
	stream.free()

	stream = _fixture()
	stream._response_code = 429
	stream._accept_http_error_bytes("x".repeat(8193).to_utf8_buffer())
	_check(not stream.busy and stream.failure_code == "http_429" and stream._error_body.is_empty(), "HTTP error buffering is bounded and releases the transport on overflow")
	stream.free()

	stream = _fixture()
	stream._accept_bytes("event: error\ndata: {\"error\":{\"code\":{\"unexpected\":true},\"message\":[\"unsafe\"]}}\n\n".to_utf8_buffer())
	_check(errors == ["Error del servicio de conversación."] and stream.failure_code == "service_error", "malformed error metadata uses a safe fallback instead of stringifying unexpected values")
	stream.free()

	stream = _fixture()
	stream._accept_bytes("event: delta\ndata: {\"text\":\"Parcial\"}\n\n".to_utf8_buffer())
	stream._end_of_stream()
	_check(fragments == ["Parcial"] and errors.size() == 1 and completions.is_empty(), "EOF before done fails after real partial output")
	stream.free()

	stream = _fixture()
	stream._accept_bytes("event: delta\ndata: not-json\n\n".to_utf8_buffer())
	_check(errors.size() == 1 and fragments.is_empty(), "invalid JSON rejected")
	stream.free()

	stream = _fixture()
	stream._accept_bytes(("event: delta\ndata: " + JSON.stringify({"text": "x".repeat(4001)}) + "\n\n").to_utf8_buffer())
	_check(errors.size() == 1 and fragments.is_empty(), "output limit enforced before emitting")
	stream.free()

	stream = _fixture()
	stream._accept_bytes("x".repeat(65537).to_utf8_buffer())
	_check(errors.size() == 1, "unterminated event buffer is bounded")
	stream.free()

	stream = _fixture()
	stream._accept_bytes("event: done\ndata: {\"text\":\"Unseen text\"}\n\n".to_utf8_buffer())
	_check(errors.size() == 1 and completions.is_empty(), "completion cannot silently replace streamed text")
	stream.free()

	stream = _fixture()
	var first_generation: int = stream._generation
	stream.completed.connect(func(_data: Dictionary):
		stream._reset_state()
		stream.busy = true
		# New bytes must wait for their own invocation, never the old parser stack.
		stream._bytes = "event: delta\ndata: {\"text\":\"Nueva\"}\n\n".to_utf8_buffer(), CONNECT_ONE_SHOT)
	stream._accept_bytes(("event: delta\ndata: {\"text\":\"Primera\"}\n\n"
		+ "event: done\ndata: {\"text\":\"Primera\"}\n\n"
		+ "event: delta\ndata: {\"text\":\"Old trailing data\"}\n\n").to_utf8_buffer())
	_check(stream.busy and stream._generation > first_generation and errors.is_empty(), "completed listener can synchronously rearm a new generation")
	_check(fragments == ["Primera"] and completions.size() == 1, "old parser stops at generation change and discards old trailing data")
	stream._accept_bytes(PackedByteArray())
	stream._accept_bytes("event: done\ndata: {\"text\":\"Nueva\"}\n\n".to_utf8_buffer())
	_check(fragments == ["Primera", "Nueva"] and completions.size() == 2 and errors.is_empty(), "rearmed stream delivers only its own bytes and completion")
	stream.free()

	stream = _fixture()
	var before_cancel: int = stream._generation
	stream.cancel()
	stream._accept_bytes("event: delta\ndata: {\"text\":\"ignored\"}\n\n".to_utf8_buffer())
	_check(not stream.busy and fragments.is_empty() and errors.is_empty(), "cancel discards subsequent bytes without error signal")
	_check(stream._generation > before_cancel, "cancel invalidates active parser and frame generation")
	_check(stream._parse_url("http://localhost:8787/dialogue/stream").port == 8787, "localhost endpoint parsed")
	_check(stream._parse_url("https://my-city.example/dialogue/stream").secure, "HTTPS enables verified TLS")
	_check(stream._parse_url("http://user:secret@localhost/").is_empty(), "userinfo URL rejected")
	_check(stream._parse_url("https://example.com/\r\nInjected: true").is_empty(), "URL header injection rejected")
	_check(stream.start("https://example.com/", PackedStringArray(["X-Test: a\r\nb"]), {}) == ERR_INVALID_PARAMETER, "header injection rejected without network")
	stream.free()
	print("RESULT: %d/%d stream checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
