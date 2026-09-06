extends GutHookScript
## Fail empty discovery and GUT warnings/errors, including skipped parse failures.


func run() -> void:
	if gut.get_test_count() == 0:
		push_error("No foundation tests were executed; check test discovery.")
		set_exit_code(1)
	elif not gut.logger.get_errors().is_empty() or not gut.logger.get_warnings().is_empty():
		push_error("GUT reported errors or warnings; check test discovery and output.")
		set_exit_code(1)
