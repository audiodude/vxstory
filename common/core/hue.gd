extends RefCounted
# Slow hue rotation for long-form palette drift. `deg` is absolute degrees;
# saturation, value and alpha are preserved. Grayscale (s == 0) is unaffected.

static func rotated(c: Color, deg: float) -> Color:
	var shift := fposmod(deg, 360.0) / 360.0
	var h := fposmod(c.h + shift, 1.0)
	return Color.from_hsv(h, c.s, c.v, c.a)
