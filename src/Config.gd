extends Node

const MOD_ID := "journal"
const FILE_PATH := "user://MCM/journal"
const _MCM_HELPERS := "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"
const JC := preload("res://src/JournalConsts.gd")

var _mcm


func _ready() -> void:
	await _wait_for_mcm_pack()
	_mcm = load(_MCM_HELPERS) if ResourceLoader.exists(_MCM_HELPERS) else null

	var ini_path := FILE_PATH.path_join("config.ini")
	var cfg := ConfigFile.new()
	_fill_mcm_template(cfg)

	if not FileAccess.file_exists(ini_path):
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(FILE_PATH)
		)
		cfg.save(ini_path)
	else:
		if _mcm:
			_mcm.CheckConfigurationHasUpdated(MOD_ID, cfg, ini_path)
		cfg.load(ini_path)

	_push_runtime_options(cfg)

	if _mcm:
		_mcm.RegisterConfiguration(
			MOD_ID,
			"Journal",
			FILE_PATH,
			"In-game notepad (toggle key, optional pause).",
			{"config.ini": _on_config_saved},
		)
	else:
		push_warning("[Journal] MCM not loaded; keybind won't appear in MCM menu.")
		_register_default_journal_key()


func _wait_for_mcm_pack() -> void:
	const MAX_FRAMES := 600
	var frames := 0
	while not ResourceLoader.exists(_MCM_HELPERS):
		await get_tree().process_frame
		frames += 1
		if frames >= MAX_FRAMES:
			return


func _fill_mcm_template(cfg: ConfigFile) -> void:
	cfg.set_value(
		"Keycode",
		JC.INPUT_ACTION_TOGGLE,
		{
			"name": "Toggle journal",
			"tooltip": "Open or close the journal.",
			"default": KEY_J,
			"default_type": "Key",
			"value": KEY_J,
			"type": "Key",
		},
	)
	cfg.set_value(
		"Bool",
		JC.MCM_BOOL_PAUSE_GAME,
		{
			"name": "Pause entire game",
			"tooltip": "On: full pause (world stops). Off: world runs, but player controls stay locked (WASD only in journal).",
			"default": true,
			"value": true,
		},
	)


func _read_pause_game_from_cfg(cfg: ConfigFile) -> bool:
	if not cfg.has_section_key("Bool", JC.MCM_BOOL_PAUSE_GAME):
		return true
	var raw: Variant = cfg.get_value("Bool", JC.MCM_BOOL_PAUSE_GAME)
	return _coerce_mcm_bool(raw, true)


func _coerce_mcm_bool(raw: Variant, default_if_unknown: bool) -> bool:
	match typeof(raw):
		TYPE_BOOL:
			return raw
		TYPE_INT:
			return raw != 0
		TYPE_FLOAT:
			return raw != 0.0
		TYPE_STRING:
			var s := str(raw).strip_edges().to_lower()
			if s == "":
				return default_if_unknown
			if s in ["0", "false", "no", "off"]:
				return false
			if s in ["1", "true", "yes", "on"]:
				return true
			return default_if_unknown
		TYPE_DICTIONARY:
			return _coerce_mcm_bool(
				(raw as Dictionary).get("value", default_if_unknown),
				default_if_unknown
			)
		_:
			return default_if_unknown


## Call from Main (reads disk so MCM changes apply without relying on Engine meta).
func is_pause_game_while_open() -> bool:
	var ini_path := FILE_PATH.path_join("config.ini")
	if not FileAccess.file_exists(ini_path):
		return true
	var disk := ConfigFile.new()
	if disk.load(ini_path) != OK:
		return true
	return _read_pause_game_from_cfg(disk)


func _push_runtime_options(cfg: ConfigFile) -> void:
	Engine.set_meta(
		JC.RUNTIME_META_PAUSE_GAME,
		_read_pause_game_from_cfg(cfg)
	)


func _on_config_saved(config: ConfigFile) -> void:
	_push_runtime_options(config)


func _register_default_journal_key() -> void:
	var action := JC.INPUT_ACTION_TOGGLE
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	InputMap.action_add_event(action, ev)
