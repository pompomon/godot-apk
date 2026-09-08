extends RefCounted
## Integer CPU raster primitives. No interpolation, antialiasing or global RNG.

const PALETTE := preload("res://tools/art/art_palette.gd")
var image: Image


func _init(width: int, height: int, background: String = "") -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0) if background.is_empty() else PALETTE.color(background))


func rect(x: int, y: int, width: int, height: int, shade: String) -> void:
	var area := Rect2i(x, y, width, height).intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if area.has_area():
		image.fill_rect(area, PALETTE.color(shade))


func dot(x: int, y: int, shade: String, size: int = 1) -> void:
	rect(x, y, size, size, shade)


func line(x0: int, y0: int, x1: int, y1: int, shade: String, width: int = 1) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy
	while true:
		rect(x0, y0, width, width, shade)
		if x0 == x1 and y0 == y1:
			break
		var twice := error * 2
		if twice >= dy:
			error += dy
			x0 += sx
		if twice <= dx:
			error += dx
			y0 += sy


func poly(points: Array, shade: String) -> void:
	var low := image.get_height()
	var high := 0
	for point: Array in points:
		low = mini(low, point[1])
		high = maxi(high, point[1])
	for y in range(maxi(0, low), mini(image.get_height(), high + 1)):
		var intersections: Array[float] = []
		for index in range(points.size()):
			var a: Array = points[index]
			var b: Array = points[(index + 1) % points.size()]
			if (a[1] <= y and b[1] > y) or (b[1] <= y and a[1] > y):
				intersections.append(a[0] + float(y - a[1]) * float(b[0] - a[0]) / float(b[1] - a[1]))
		intersections.sort()
		for index in range(0, intersections.size() - 1, 2):
			var left := ceili(intersections[index])
			var right := floori(intersections[index + 1])
			rect(left, y, right - left + 1, 1, shade)


func disc(cx: int, cy: int, radius: int, shade: String) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				dot(cx + x, cy + y, shade)


func diamond(x: int, y: int, radius: int, shade: String) -> void:
	poly([[x, y - radius], [x + radius, y], [x, y + radius + 1], [x - radius, y]], shade)


func doubled() -> Image:
	var result := image.duplicate() as Image
	result.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
	return result
