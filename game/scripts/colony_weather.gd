extends RefCounted
## Fictional neighborhood temperature, derived from the saved game clock.
## No real-world forecast, location permission, network call or offline advance.

static func at_minute(minute: int) -> Dictionary:
	var day: int = maxi(0, minute) / 1440
	var local: int = posmod(minute, 1440)
	var high: float = 24.0 + posmod(day * 7 + 3, 10)
	var low: float = high - 12.0
	# The warmest point is around 15:00; early morning is cooler.
	var warmth: float = (cos((local - 900.0) * TAU / 1440.0) + 1.0) / 2.0
	var temperature: float = snappedf(lerpf(low, high, warmth), 0.1)
	var daylight: bool = local >= 420 and local < 1140
	var period := "noche"
	if local >= 420 and local < 660: period = "mañana"
	elif local >= 660 and local < 1020: period = "día"
	elif local >= 1020 and local < 1140: period = "tarde"
	return {"source": "colony", "day": day, "minute": local, "temperature_c": temperature,
		"daylight": daylight, "period": period,
		"feeling": "calor" if temperature >= 28.0 else "fresco" if temperature <= 18.0 else "templado"}
