extends Node
## Nonblocking SSE transport. Only complete UTF-8 lines are decoded.

signal delta(text: String)
signal completed(data: Dictionary)
signal failed(message: String)

const TIMEOUT_MS := 15000
const MAX_BUFFER_BYTES := 65536
const MAX_OUTPUT_CHARS := 4000
const MAX_ERROR_BYTES := 8192

var busy: bool = false
var metrics: Dictionary = {"ttft_ms": -1, "total_ms": 0}
var failure_code: String = ""
var failure_message: String = ""
var failure_http_status: int = 0
var _client := HTTPClient.new()
var _started_at: int = 0
var _request_sent: bool = false
var _response_checked: bool = false
var _path: String = ""
var _headers := PackedStringArray()
var _body: String = ""
var _bytes := PackedByteArray()
var _event_name: String = ""
var _data_lines := PackedStringArray()
var _event_bytes: int = 0
var _output: String = ""
var _first_line: bool = true
var _generation: int = 0
var _response_code: int = 0
var _error_body := PackedByteArray()

func _ready() -> void:
	set_process(busy)

func start(url: String, headers: PackedStringArray, payload: Dictionary) -> Error:
	if busy:
		return ERR_BUSY
	var endpoint: Dictionary = _parse_url(url)
	if endpoint.is_empty():
		return ERR_INVALID_PARAMETER
	for header in headers:
		if header.contains("\r") or header.contains("\n"):
			return ERR_INVALID_PARAMETER
	_reset_state()
	_path = endpoint.path
	_headers = headers.duplicate()
	_headers.append("Accept: text/event-stream")
	if not Array(headers).any(func(header): return str(header).to_lower().begins_with("content-type:")):
		_headers.append("Content-Type: application/json")
	_headers.append("Accept-Encoding: identity")
	_body = JSON.stringify(payload)
	_client.blocking_mode_enabled = false
	_client.read_chunk_size = 4096
	var tls: TLSOptions = TLSOptions.client() if endpoint.secure else null
	var result: Error = _client.connect_to_host(endpoint.host, endpoint.port, tls)
	if result != OK:
		failure_code = "connection_failed"
		failure_message = "No se pudo iniciar la conexión de conversación."
		_clear_transport()
		return result
	busy = true
	set_process(true)
	return OK

func cancel() -> void:
	_generation += 1
	if busy:
		metrics.total_ms = Time.get_ticks_msec() - _started_at
	busy = false
	_clear_transport()
	_bytes.clear()
	_data_lines.clear()
	_event_bytes = 0
	_error_body.clear()
	set_process(false)

func _exit_tree() -> void:
	cancel()

func _parse_url(url: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^(https?)://(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?(/[^\\r\\n #]*)?$")
	var matched: RegExMatch = pattern.search(url)
	if matched == null:
		return {}
	var secure: bool = matched.get_string(1) == "https"
	var port: int = 443 if secure else 80
	if not matched.get_string(3).is_empty():
		port = int(matched.get_string(3))
	if port < 1 or port > 65535:
		return {}
	var host: String = matched.get_string(2)
	if host.begins_with("["):
		host = host.substr(1, host.length() - 2)
	var path: String = matched.get_string(4)
	return {"secure": secure, "host": host, "port": port, "path": "/" if path.is_empty() else path}

func _reset_state() -> void:
	# Every start invalidates any frame/parser stack still delivering a signal.
	_generation += 1
	_client.close()
	_started_at = Time.get_ticks_msec()
	metrics = {"ttft_ms": -1, "total_ms": 0}
	failure_code = ""
	failure_message = ""
	failure_http_status = 0
	_response_code = 0
	_error_body.clear()
	_request_sent = false
	_response_checked = false
	_bytes.clear()
	_event_name = ""
	_data_lines.clear()
	_event_bytes = 0
	_output = ""
	_first_line = true

func _process(_elapsed: float) -> void:
	if not busy:
		return
	var generation: int = _generation
	if Time.get_ticks_msec() - _started_at >= TIMEOUT_MS:
		_fail("La conversación superó el tiempo de espera.", "request_timeout")
		return
	var polling: Error = _client.poll()
	if polling != OK:
		_fail("No se pudo mantener la conexión de conversación.", "connection_failed")
		return
	match _client.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_CONNECTED:
			if not _request_sent:
				var result: Error = _client.request(HTTPClient.METHOD_POST, _path, _headers, _body)
				_headers.clear()
				_body = ""
				if result != OK:
					_fail("No se pudo iniciar la conversación.", "connection_failed")
					return
				_request_sent = true
			else:
				if _check_response():
					_end_of_stream()
		HTTPClient.STATUS_BODY:
			if not _check_response():
				return
			# Bound work per frame, including when the server sends a large burst.
			for _chunk_index in range(4):
				if _client.get_status() != HTTPClient.STATUS_BODY:
					break
				var chunk: PackedByteArray = _client.read_response_body_chunk()
				if chunk.is_empty():
					break
				if _response_code == 200:
					_accept_bytes(chunk)
				else:
					_accept_http_error_bytes(chunk)
				if not busy or _generation != generation:
					return
			if _generation == generation and _client.get_status() != HTTPClient.STATUS_BODY:
				_end_of_stream()
		HTTPClient.STATUS_DISCONNECTED:
			_end_of_stream()
		_:
			_fail("Falló la conexión con el servicio de conversación.", "connection_failed")

func _check_response() -> bool:
	if _response_checked:
		return true
	if not _client.has_response():
		_fail("El servicio no devolvió una respuesta HTTP válida.")
		return false
	_response_code = _client.get_response_code()
	if _response_code != 200:
		# Worker errors use JSON before streaming begins. Read their bounded body
		# asynchronously so HTTP failures retain the same code/message as SSE errors.
		_response_checked = true
		return true
	var content_type: String = ""
	for header in _client.get_response_headers():
		if header.to_lower().begins_with("content-type:"):
			content_type = header.substr(header.find(":") + 1).strip_edges().to_lower()
	if not content_type.begins_with("text/event-stream"):
		_fail("El servicio no devolvió una conversación en streaming.")
		return false
	_response_checked = true
	return true

func _accept_bytes(chunk: PackedByteArray) -> void:
	if not busy:
		return
	var generation: int = _generation
	if _bytes.size() + _event_bytes + chunk.size() > MAX_BUFFER_BYTES:
		_fail("La respuesta de conversación excedió el tamaño permitido.")
		return
	_bytes.append_array(chunk)
	while busy and _generation == generation:
		var newline: int = _bytes.find(10)
		if newline < 0:
			break
		var line_bytes: PackedByteArray = _bytes.slice(0, newline)
		_bytes = _bytes.slice(newline + 1)
		if not line_bytes.is_empty() and line_bytes[-1] == 13:
			line_bytes.resize(line_bytes.size() - 1)
		# Newline is ASCII, so no multibyte character is split at this boundary.
		var line: String = line_bytes.get_string_from_utf8()
		if _first_line:
			_first_line = false
			line = line.trim_prefix("\ufeff")
		_parse_line(line, line_bytes.size())

func _parse_line(line: String, byte_count: int) -> void:
	if line.is_empty():
		_dispatch_event()
		return
	_event_bytes += byte_count + 1
	if _event_bytes + _bytes.size() > MAX_BUFFER_BYTES:
		_fail("La respuesta de conversación excedió el tamaño permitido.")
		return
	if line.begins_with(":"):
		return
	var separator: int = line.find(":")
	var field: String = line if separator < 0 else line.substr(0, separator)
	var value: String = "" if separator < 0 else line.substr(separator + 1).trim_prefix(" ")
	match field:
		"event": _event_name = value
		"data": _data_lines.append(value)

func _dispatch_event() -> void:
	var event: String = _event_name
	var raw: String = "\n".join(_data_lines)
	_event_name = ""
	_data_lines.clear()
	_event_bytes = 0
	if raw.is_empty():
		return
	if event not in ["delta", "done", "error"]:
		return
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary:
		_fail("El servicio devolvió un evento de conversación inválido.")
		return
	var data: Dictionary = parser.data
	match event:
		"delta":
			if not data.get("text") is String:
				_fail("El fragmento de conversación no contiene texto válido.")
				return
			var fragment: String = data.text
			if _output.length() + fragment.length() > MAX_OUTPUT_CHARS:
				_fail("La conversación excedió el límite de texto.")
				return
			if fragment.is_empty():
				return
			if int(metrics.ttft_ms) < 0:
				metrics.ttft_ms = Time.get_ticks_msec() - _started_at
			_output += fragment
			delta.emit(fragment)
		"done":
			if not data.get("text") is String or data.text.length() > MAX_OUTPUT_CHARS:
				_fail("La conversación terminó con texto inválido.")
				return
			if data.text != _output:
				_fail("El cierre de la conversación no coincide con sus fragmentos.")
				return
			metrics.total_ms = Time.get_ticks_msec() - _started_at
			busy = false
			_clear_transport()
			set_process(false)
			completed.emit(data)
		"error":
			_service_error(data, "service_error", "Error del servicio de conversación.")

func _accept_http_error_bytes(chunk: PackedByteArray) -> void:
	if _error_body.size() + chunk.size() > MAX_ERROR_BYTES:
		_fail_http_response()
		return
	_error_body.append_array(chunk)

func _service_error(data: Dictionary, fallback_code: String, fallback_message: String) -> void:
	var code: String = fallback_code
	var message: String = fallback_message
	var detail = data.get("error")
	if detail is Dictionary:
		var received_code = detail.get("code")
		if received_code is String and received_code.length() <= 64 and received_code.is_valid_identifier():
			code = received_code
		if detail.get("message") is String and not detail.message.strip_edges().is_empty():
			message = detail.message.left(500)
	elif detail is String and not detail.strip_edges().is_empty():
		# Preserve compatibility with older local services and existing fixtures.
		message = detail.left(500)
	_fail(message, code)

func _fail_http_response() -> void:
	var code: String = "http_%d" % _response_code
	var message: String = "El servicio de conversación respondió HTTP %d." % _response_code
	var parser := JSON.new()
	if parser.parse(_error_body.get_string_from_utf8()) == OK and parser.data is Dictionary:
		_service_error(parser.data, code, message)
	else:
		_fail(message, code)

func _end_of_stream() -> void:
	if busy:
		if _response_code != 0 and _response_code != 200:
			_fail_http_response()
		else:
			_fail("La conexión terminó antes de completar la conversación.", "stream_interrupted")

func _clear_transport() -> void:
	_client.close()
	_headers.clear()
	_body = ""
	_path = ""

func _fail(message: String, code: String = "invalid_stream") -> void:
	if not busy:
		return
	metrics.total_ms = Time.get_ticks_msec() - _started_at
	failure_code = code
	failure_message = message
	failure_http_status = _response_code
	busy = false
	_clear_transport()
	_bytes.clear()
	_data_lines.clear()
	_error_body.clear()
	set_process(false)
	failed.emit(message)
