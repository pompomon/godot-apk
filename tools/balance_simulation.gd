extends SceneTree
## Offline authoring report. Never initializes a Company or reads/writes player saves.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var trials := 256
	var seed_value := 7001
	var regions := ExpeditionCatalog.regions()
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() != 2:
			_fail("Use --trials=N, --seed=N, or --region=registered_id.")
			return
		match pair[0]:
			"--trials", "--seed":
				if not pair[1].is_valid_int():
					_fail("Expected an integer for %s." % pair[0])
					return
				if pair[0] == "--trials":
					trials = pair[1].to_int()
				else:
					seed_value = pair[1].to_int()
			"--region":
				var region := ExpeditionCatalog.region_by_id(pair[1])
				if region == null:
					_fail("Unknown Region ID.")
					return
				regions = [region]
			_:
				_fail("Unknown option: %s." % pair[0])
				return
	var report := BalanceReport.run(regions, trials, seed_value,
		load("res://data/balancing/default_balancing.tres"))
	if report.has("error"):
		_fail(report.error)
		return
	print(JSON.stringify(report, "\t", true, true))
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
