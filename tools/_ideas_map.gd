extends SceneTree
func _initialize() -> void:
	for s in [1, 7]:
		var w := World.new(s)
		var ch := "~-.,:#d^MGL"
		var counts := {}
		for z in range(0, w.height, 2):
			var line := ""
			for x in range(0, w.width, 1):
				var t: Dictionary = w.get_tile(x, z)
				var c := ch[int(t["type"])]
				if t["river"]: c = "r"
				line += c
			print(line)
		for row in w.tiles:
			for t in row:
				counts[int(t["type"])] = int(counts.get(int(t["type"]), 0)) + 1
		print(s, " ", counts)
	quit()
