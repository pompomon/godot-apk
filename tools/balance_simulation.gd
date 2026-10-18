extends SceneTree
## Offline authoring report. Never initializes a Company or reads/writes player saves.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var trials := 256
	var seeds: Array[int] = [7001]
	var seed_options := 0
	var aggregate_seeds := false
	var regions := ExpeditionCatalog.regions()
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() != 2:
			_fail("Use --trials=N, --seed=N or --seeds=N,M, and --region=registered_id.")
			return
		match pair[0]:
			"--trials", "--seed":
				if not pair[1].is_valid_int():
					_fail("Expected an integer for %s." % pair[0])
					return
				if pair[0] == "--trials":
					trials = pair[1].to_int()
				else:
					seed_options += 1
					seeds = [pair[1].to_int()]
			"--seeds":
				seed_options += 1
				aggregate_seeds = true
				seeds = []
				for part in pair[1].split(","):
					if not part.is_valid_int() or seeds.has(part.to_int()):
						_fail("Expected distinct comma-separated integers for --seeds.")
						return
					seeds.append(part.to_int())
			"--region":
				var region := ExpeditionCatalog.region_by_id(pair[1])
				if region == null:
					_fail("Unknown Region ID.")
					return
				regions = [region]
			_:
				_fail("Unknown option: %s." % pair[0])
				return
	if seed_options > 1:
		_fail("Use either --seed or --seeds once.")
		return
	var balancing: BalancingConfig = load("res://data/balancing/default_balancing.tres")
	var reports: Array = []
	for seed_value in seeds:
		var report := BalanceReport.run(regions, trials, seed_value, balancing)
		if report.has("error"):
			_fail(report.error)
			return
		reports.append(report)
	var output: Dictionary = reports[0]
	if aggregate_seeds:
		output = BalanceReport.aggregate(reports)
		if output.has("error"):
			_fail(output.error)
			return
	print(JSON.stringify(output, "\t", true, true))
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
