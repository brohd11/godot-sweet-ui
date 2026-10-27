@tool
class_name _SweetUIGenerator
extends EditorScript

const Parser = preload("res://addons/_lib/gdscript_parser/src/gdscript_parser.gd")
const Lexer = preload("res://addons/_lib/gdscript_parser/src/utils/lambda_scanner.gd")
const TagScanner = preload("res://addons/_lib/editor_parser/src/tag/scanner.gd")

const TARGETS_SETTING = "sweet_ui/generation/targets"
const LEGACY_DIRECTORY_SETTING = "sweet_ui/generation/directory"
const DEFAULT_DIRECTORY = "res://scripts/sweet_ui"
## Templates use this placeholder; each target renames it to its own class name.
const DEFAULT_NAME = "SweetUI"
const DEFAULT_TARGETS = {DEFAULT_DIRECTORY: DEFAULT_NAME}
const UNNAMED_ALIAS = "_SweetUI"
const SOURCE = DEFAULT_DIRECTORY + "/sweet_ui_source.gd"
const TARGET = DEFAULT_DIRECTORY + "/generated/sweet_ui.gd"
const CLASSES_TARGET = DEFAULT_DIRECTORY + "/generated/sweets_generated.gd"
const SWEETS_TARGET = DEFAULT_DIRECTORY + "/generated/sweets.gd"


func _run() -> void:
	generate()


static func register_setting() -> void:
	if not ProjectSettings.has_setting(TARGETS_SETTING):
		var legacy = ProjectSettings.get_setting(LEGACY_DIRECTORY_SETTING, DEFAULT_DIRECTORY)
		ProjectSettings.set_setting(TARGETS_SETTING, {str(legacy): DEFAULT_NAME})
	if ProjectSettings.has_setting(LEGACY_DIRECTORY_SETTING):
		ProjectSettings.set_setting(LEGACY_DIRECTORY_SETTING, null)
	ProjectSettings.set_initial_value(TARGETS_SETTING, DEFAULT_TARGETS)
	ProjectSettings.add_property_info({"name": TARGETS_SETTING, "type": TYPE_DICTIONARY,
		"hint": PROPERTY_HINT_DICTIONARY_TYPE, "hint_string": "String;String"})


static func _template_path(name: String) -> String:
	var script: Script = _SweetUIGenerator
	return script.resource_path.get_base_dir().path_join("templates/" + name + ".gd.txt")


static func read_template() -> String:
	return FileAccess.get_file_as_string(_template_path("sweet_ui"))


## Regenerates every configured target, or only the directory given.
static func generate(only: String = "") -> Error:
	return _report(setup(true, only))


static func _report(result: Dictionary) -> Error:
	if result.error != OK:
		push_error(result.message)
	else:
		print("Sweet UI generated." if result.changed else "Sweet UI already up to date.")
		if result.changed and Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
			_scan_editor.call_deferred()
	return result.error


## Plugin enable can run inside the initial scan; rescanning there re-enters plugin setup.
static func _scan_editor() -> void:
	var filesystem = Engine.get_singleton(&"EditorInterface").get_resource_filesystem()
	while filesystem.is_scanning():
		await Engine.get_main_loop().process_frame
	filesystem.scan()


## Enable repairs missing outputs; explicit generation also incorporates source changes.
static func setup(force: bool = false, only: String = "") -> Dictionary:
	register_setting()
	var read = _read_targets()
	if read.error != OK:
		return read
	var targets: Dictionary = read.targets
	only = only.simplify_path().trim_suffix("/")
	if not only.is_empty() and not targets.has(only):
		return _failure("No Sweet UI target configured for %s in %s." % [only, TARGETS_SETTING])
	var changed = false
	for directory: String in targets:
		if only.is_empty() or directory == only:
			var result = _setup_directory(directory, force, targets[directory])
			if result.error != OK:
				return result
			changed = changed or result.changed
	return {"error": OK, "changed": changed}


## Validates every target before any of them writes.
static func _read_targets() -> Dictionary:
	var configured = ProjectSettings.get_setting(TARGETS_SETTING, DEFAULT_TARGETS)
	if configured is not Dictionary:
		return _failure("%s must map project directories to class names." % TARGETS_SETTING)
	var script: Script = _SweetUIGenerator
	var addon_dir = script.resource_path.get_base_dir().get_base_dir().get_base_dir()
	var targets: Dictionary = {}
	for key in configured:
		var directory = str(key).simplify_path().trim_suffix("/")
		var name = configured[key]
		if not directory.begins_with("res://") or directory == "res:" or directory == addon_dir or directory.begins_with(addon_dir + "/"):
			return _failure("Sweet UI needs a project directory outside its addon: " + directory)
		if name is not String or not (name.is_empty() or name.is_valid_ascii_identifier()) or ClassDB.class_exists(name):
			return _failure("Invalid Sweet UI class name for %s: %s" % [directory, name])
		for other: String in targets:
			if directory == other or directory.begins_with(other + "/") or other.begins_with(directory + "/"):
				return _failure("Sweet UI targets cannot overlap: %s, %s" % [other, directory])
			if not name.is_empty() and targets[other] == name:
				return _failure("Sweet UI class name used by two targets: " + name)
		var target = directory.path_join("generated/sweet_ui.gd")
		for entry in ProjectSettings.get_global_class_list():
			if not name.is_empty() and entry.class == name and entry.path != target and FileAccess.file_exists(entry.path):
				return _failure("%s already exists at %s. Move its directory through Godot before changing %s." % [name, entry.path, TARGETS_SETTING])
		targets[directory] = name
	return {"error": OK, "targets": targets}


static func _setup_directory(directory: String, force: bool = false, class_name_: String = DEFAULT_NAME) -> Dictionary:
	var source = directory.path_join("sweet_ui_source.gd")
	var target = directory.path_join("generated/sweet_ui.gd")
	var classes = directory.path_join("generated/sweets_generated.gd")
	var sweets = directory.path_join("generated/sweets.gd")
	var seeded = false
	if not FileAccess.file_exists(source):
		var seed = FileAccess.get_file_as_string(_template_path("sweet_ui_source"))
		if seed.is_empty():
			return _failure("Cannot read Sweet UI source template.", ERR_FILE_NOT_FOUND)
		var written = _write_outputs({source: seed})
		if written.error != OK:
			return written
		seeded = true
	if not force and not seeded and _has_name(target, class_name_) and FileAccess.file_exists(classes) and FileAccess.file_exists(sweets):
		return {"error": OK, "changed": false}
	return _generate_file(target, source, classes, sweets, "", class_name_)


## A renamed target counts as stale output, like a missing file.
static func _has_name(target: String, class_name_: String) -> bool:
	if not FileAccess.file_exists(target):
		return false
	var declaration = FileAccess.get_file_as_string(target).get_slice("\n", 0)
	return declaration == "class_name " + class_name_ if not class_name_.is_empty() else not declaration.begins_with("class_name ")


static func _generate_file(target_path: String, source_path: String = SOURCE, classes_path: String = CLASSES_TARGET, sweets_path: String = SWEETS_TARGET, template_source: String = "", class_name_: String = DEFAULT_NAME) -> Dictionary:
	var result = build_candidate(source_path, target_path, classes_path, sweets_path, template_source, class_name_)
	if result.error != OK:
		return result
	_clear_validation(result.validation)
	return _write_outputs({classes_path: result.classes_source, sweets_path: result.sweets_source, target_path: result.source})


static func _write_outputs(outputs: Dictionary) -> Dictionary:
	var pending: Array[String] = []
	for path: String in outputs:
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == outputs[path]:
			continue
		var directory_error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if directory_error != OK:
			_clear_staging(pending)
			return _failure("Cannot create generated Sweets directory: " + path.get_base_dir(), directory_error)
		pending.append(path)
		var file = FileAccess.open(path + ".sweets.tmp", FileAccess.WRITE)
		if file == null:
			_clear_staging(pending)
			return _failure("Cannot stage generated Sweets: " + path, FileAccess.get_open_error())
		file.store_string(outputs[path])
		var error = file.get_error()
		file.close()
		if error != OK:
			_clear_staging(pending)
			return _failure("Cannot stage generated Sweets: " + path, error)
	var replaced: Array[String] = []
	var backups: Array[String] = []
	for path in pending:
		var error = OK
		if FileAccess.file_exists(path):
			error = DirAccess.rename_absolute(path, path + ".sweets.bak")
			if error == OK:
				backups.append(path)
		if error == OK:
			error = DirAccess.rename_absolute(path + ".sweets.tmp", path)
			if error == OK:
				replaced.append(path)
		if error != OK:
			for replaced_path in replaced:
				DirAccess.remove_absolute(replaced_path)
			for backup in backups:
				DirAccess.rename_absolute(backup + ".sweets.bak", backup)
			_clear_staging(pending)
			return _failure("Cannot replace generated Sweets: " + path, error)
	for backup in backups:
		DirAccess.remove_absolute(backup + ".sweets.bak")
	return {"error": OK, "changed": not pending.is_empty()}


static func _clear_staging(paths: Array[String]) -> void:
	for path in paths:
		if FileAccess.file_exists(path + ".sweets.tmp"):
			DirAccess.remove_absolute(path + ".sweets.tmp")


## Clear the returned temporary validation types after their instances are gone.
static func build_candidate(source_path: String = SOURCE, target_path: String = TARGET, classes_path: String = CLASSES_TARGET, sweets_path: String = SWEETS_TARGET, template_source: String = "", class_name_: String = DEFAULT_NAME) -> Dictionary:
	var prefix = read_template() if template_source.is_empty() else template_source
	if prefix.is_empty():
		return _failure("Cannot read Sweet UI runtime template.", ERR_FILE_NOT_FOUND)
	prefix = prefix.replace("\r\n", "\n").strip_edges(false, true) + "\n\n"
	var generated = _build_region(source_path)
	if generated.error != OK:
		return generated
	var preload_line = "const _Generated = preload(%s)\n" % var_to_str(_relative_path(target_path, classes_path))
	var sweets_preload = "const Sweets = preload(%s)\n" % var_to_str(_relative_path(target_path, sweets_path))
	var candidate: String = prefix + preload_line + sweets_preload + generated.source
	var sweets_source: String = "extends RefCounted\n\nconst _Generated = preload(%s)\n" % var_to_str(_relative_path(sweets_path, classes_path)) + generated.static_source

	# A local owner type keeps self typed without touching the editor's cached scripts.
	var validation_path = _validation_path(target_path)
	var validation_name = "SweetsValidation" + validation_path.get_file().get_basename().trim_prefix("__sweets_validate_")
	var wrapper_source: String = generated.classes_source.trim_prefix("extends RefCounted\n")
	var factory_source: String = generated.source
	var static_source: String = generated.static_source
	if generated.re_export:
		# In-memory aliases to nested classes can resolve to null; use the local types directly.
		var aliases = RegEx.new()
		aliases.compile("(?m)^const Sw[A-Za-z_0-9]* = _Generated\\.Sw[A-Za-z_0-9]*\n")
		factory_source = aliases.sub(factory_source, "", true)
		static_source = aliases.sub(static_source, "", true)
		if not generated.dependencies.is_empty():
			factory_source = factory_source.replace(generated.dependencies, "")
	else:
		wrapper_source = _nested_class("_Generated", wrapper_source)
	var validation_source = prefix + wrapper_source + "\n" + _nested_class("Sweets", static_source) + "\n" + factory_source
	if generated.re_export:
		validation_source = _flatten_wrapper_references(validation_source)
	validation_source = _rename_identifier(validation_source, "SweetUI", validation_name)
	if not validation_source.contains("class_name " + validation_name):
		validation_source = "class_name " + validation_name + "\n" + validation_source
	var validation = GDScript.new()
	validation.set_path_cache(validation_path)
	validation.source_code = validation_source
	var error = validation.reload()
	if error != OK:
		_clear_validation(validation)
		return _failure("Generated Sweets did not compile: " + error_string(error), error)
	# Validation already compiled the placeholder under its own name; renaming is token-only.
	return {"error": OK, "source": _apply_name(candidate, target_path, target_path, class_name_),
		"classes_source": _apply_name(generated.classes_source, classes_path, target_path, class_name_),
		"classes_path": classes_path, "sweets_source": _apply_name(sweets_source, sweets_path, target_path, class_name_),
		"sweets_path": sweets_path, "validation": validation}


## Unnamed builds reach their owner type through a preload alias instead of a global class.
static func _apply_name(source: String, path: String, target_path: String, class_name_: String) -> String:
	if class_name_ == DEFAULT_NAME:
		return source
	if not class_name_.is_empty():
		return _rename_identifier(source, DEFAULT_NAME, class_name_)
	var unnamed = source.trim_prefix("class_name %s\n" % DEFAULT_NAME)
	var renamed = _rename_identifier(unnamed, DEFAULT_NAME, UNNAMED_ALIAS)
	if renamed == unnamed:
		return renamed
	var extends_line = RegEx.create_from_string("(?m)^extends [^\n]*\n").search(renamed)
	var at = extends_line.get_end() if extends_line != null else 0
	return renamed.insert(at, "const %s = preload(%s)\n" % [UNNAMED_ALIAS, var_to_str(_relative_path(path, target_path))])


static func _relative_path(owner: String, dependency: String) -> String:
	var parent = owner.get_base_dir().split("/")
	var target = dependency.split("/")
	var common = 0
	while common < mini(parent.size(), target.size()) and parent[common] == target[common]:
		common += 1
	return "../".repeat(parent.size() - common) + "/".join(target.slice(common))


static func _nested_class(name: String, source: String) -> String:
	var nested = "class %s extends RefCounted:\n" % name
	for line in source.split("\n"):
		nested += ("\t" + line if not line.is_empty() else "") + "\n"
	return nested


## Release the temporary owner/wrapper type cycle after its instances are gone.
static func _clear_validation(validation: GDScript) -> Error:
	var constants = validation.get_script_constant_map()
	for name in constants:
		var value = constants[name]
		if value is GDScript and value.resource_path.is_empty() and (name == "_Generated" or str(name).begins_with("Sw")):
			var error = _clear_validation(value)
			if error != OK:
				return error
	validation.source_code = "extends RefCounted\n"
	return validation.reload()


static func _validation_path(path: String) -> String:
	return path.get_base_dir().path_join("__sweets_validate_%d.gd" % Time.get_ticks_usec())


static func _rename_identifier(source: String, identifier: String, replacement: String) -> String:
	var tokens = Lexer._tokens(source)
	for i in range(tokens.size() - 1, -1, -1):
		var token = tokens[i]
		if token.text == identifier:
			source = source.left(token.offset) + replacement + source.substr(token.end)
	return source


## Handwritten helpers may use _Generated even when factories use re-exported names.
static func _flatten_wrapper_references(source: String) -> String:
	var tokens = Lexer._tokens(source)
	for i in range(tokens.size() - 3, -1, -1):
		if tokens[i].text == "_Generated" and tokens[i + 1].text == "." and tokens[i + 2].text.begins_with("Sw"):
			source = source.left(tokens[i].offset) + source.substr(tokens[i + 2].offset)
	return source


static func _build_region(source_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return _failure("Sweets prototype source not found: " + source_path, ERR_FILE_NOT_FOUND)
	var source_text = FileAccess.get_file_as_string(source_path)
	var source_script = GDScript.new()
	source_script.set_path_cache(_validation_path(source_path))
	source_script.source_code = source_text
	var error = source_script.reload()
	if error != OK:
		_clear_validation(source_script)
		return _failure("Sweets prototypes did not compile: " + error_string(error), error)
	var settings = source_script.get_script_constant_map()
	var overrides = settings.get("TYPES", {})
	var re_export = settings.get("RE_EXPORT", false)
	if overrides is not Dictionary or re_export is not bool:
		_clear_validation(source_script)
		return _failure("Sweets needs a TYPES dictionary and a boolean RE_EXPORT setting.")
	var parser = Parser.new()
	parser.set_use_native_backend(false)
	parser.set_cache_enabled(false)
	parser.active_parser = parser
	parser.set_current_script(source_script)
	parser.set_source_code(source_text)
	parser.parse(true)
	var result = _emit_prototypes(parser, overrides, re_export, source_text.split("\n"), settings)
	parser.code_edit.free()
	parser.code_edit = null
	parser.active_parser = null
	_clear_validation(source_script)
	return result


static func _emit_prototypes(parser, overrides: Dictionary, re_export: bool, lines: PackedStringArray, settings: Dictionary) -> Dictionary:
	var tags = _collect_setter_tags(lines)
	if tags.error != OK:
		return tags
	var names: Array[String] = []
	for name: String in parser.get_classes():
		if name.begins_with("Sw") and not name.contains("."):
			names.append(name)
	if names.is_empty():
		return _failure("Sweets needs at least one top-level Sw prototype class.")
	for name in overrides:
		if not name in names:
			return _failure("No Sweets prototype for override: " + str(name))
	names.sort()
	var factories: Array[String] = []
	var static_factories: Array[String] = []
	var wrappers: Array[String] = []
	var aliases: Array[String] = []
	var used_factories: Array[String] = []
	var imports: Dictionary = {}
	var setting_names = settings.keys()
	setting_names.sort()
	for key: String in setting_names:
		if key in ["TYPES", "RE_EXPORT"] or key.begins_with("Sw"):
			continue
		var value = settings[key]
		if value is GDScript and not value.resource_path.is_empty():
			imports[key] = value.resource_path
	for name in names:
		if name is not String or not name.is_valid_ascii_identifier():
			return _failure("Invalid Sweets wrapper name: " + str(name))
		var entry = overrides.get(name, {})
		if entry is not Dictionary:
			return _failure("Invalid Sweets catalog entry: " + name)
		var inferred_type = name.trim_prefix("Sw")
		var target = entry.get("node", inferred_type)
		var custom: GDScript = target if target is GDScript else null
		var native_base = custom.get_instance_base_type() if custom != null else str(target)
		var native_type = str(target)
		if custom != null:
			var checked = _check_target(custom)
			if checked.error != OK:
				return checked
			native_type = _import_type(custom.resource_path, imports)

		var factory = str(entry.get("factory", inferred_type.to_snake_case()))
		if not ClassDB.is_parent_class(native_base, "Control") or not factory.is_valid_ascii_identifier():
			return _failure("Sweets entries need a Control type and factory name: " + name)
		for method_name in [factory, factory + "_from"]:
			if method_name in used_factories:
				return _failure("Duplicate Sweets factory: " + method_name)
			used_factories.append(method_name)
		var collected = _collect_methods(parser, name)
		if collected.error != OK:
			return collected
		var methods: Dictionary = collected.methods
		var setters = _emit_setters(native_base, name, collected.ancestors, tags.members, custom, imports)
		if setters.error != OK:
			return setters
		# Parser keys are StringNames; their sort order depends on interned addresses.
		var method_names: Array[String] = []
		for method_name in methods:
			method_names.append(str(method_name))
		for setter_name in setters.methods:
			if not methods.has(setter_name):
				method_names.append(setter_name)
		method_names.sort()
		var output = Templates.CLASS_BODY % [name, native_type, native_type, native_type]
		output += Templates.CLASS_INIT % [native_type, native_type, name, name]
		for method_name in method_names:
			if methods.has(method_name):
				var emitted = _emit_method(methods[method_name], lines, collected.ancestors, name)
				if emitted.error != OK:
					return emitted
				output += "\n\n" + emitted.source
			else:
				output += "\n\n" + setters.methods[method_name]
		wrappers.append(output)
		if re_export:
			aliases.append("const %s = _Generated.%s" % [name, name])
		var wrapper_type = name if re_export else "_Generated." + name
		factories.append(Templates.API_FUNC % [factory, wrapper_type, wrapper_type, native_type])
		factories.append(Templates.API_FROM_FUNC % [factory, native_type, wrapper_type, wrapper_type])
		static_factories.append(Templates.STATIC_API_FUNC % [factory, native_type, wrapper_type, native_type, wrapper_type])
	var dependencies = ""
	for alias: String in imports:
		dependencies += "const %s = preload(%s)\n" % [alias, var_to_str(imports[alias])]
	var region = "# Generated by _SweetUIGenerator. Do not edit.\n" + dependencies
	if not aliases.is_empty():
		region += "\n".join(aliases) + "\n"
	region += "\n\n"
	var static_region = region + "\n\n".join(static_factories) + "\n"
	region += "\n\n".join(factories) + "\n"
	var classes_source = "extends RefCounted\n\n# Generated by _SweetUIGenerator. Do not edit.\n\n"
	classes_source += dependencies + "\n" + "\n\n".join(wrappers)
	return {"error": OK, "source": region, "static_source": static_region, "classes_source": classes_source, "dependencies": dependencies, "re_export": re_export}


static func _collect_setter_tags(lines: PackedStringArray) -> Dictionary:
	var members: Dictionary = {}
	for tag in TagScanner.scan_lines(lines, ""):
		if tag.tag != "set" or not tag.owner_function.is_empty() or tag.owner_class.is_empty():
			continue
		if not lines[tag.line].left(tag.column).strip_edges().is_empty():
			continue
		var owner: String = tag.owner_class.trim_prefix(".")
		var names: Array = members.get_or_add(owner, [])
		var arguments: String = tag.raw.trim_prefix("#!").strip_edges().trim_prefix("set").strip_edges()
		for argument in arguments.split(","):
			var member_name: String = argument.strip_edges()
			if not member_name.is_valid_ascii_identifier():
				return _failure("Invalid set member on line %d: %s" % [tag.line + 1, member_name])
			if not member_name in names:
				names.append(member_name)
	return {"error": OK, "members": members}


static func _emit_setters(native_type: String, wrapper: String, ancestors: Array[String], tags: Dictionary, custom: GDScript, imports: Dictionary) -> Dictionary:
	var properties: Dictionary = {}
	for property in ClassDB.class_get_property_list(native_type):
		properties[property.name] = property
	var script_properties: Dictionary = {}
	var signals: Dictionary = {}
	var base_script = custom
	while base_script != null:
		for property in base_script.get_script_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not script_properties.has(property.name):
				script_properties[property.name] = property
		for signal_info in base_script.get_script_signal_list():
			signals[signal_info.name] = true
		base_script = base_script.get_base_script()
	properties.merge(script_properties, true)
	var methods: Dictionary = {}
	for ancestor in ancestors:
		for member_name: String in tags.get(ancestor, []):
			if methods.has(member_name):
				continue
			if member_name in ["_init", "node", "c", "ui", "with_parent"]:
				return _failure("Set member conflicts with generated method: " + member_name)
			if not properties.has(member_name):
				if signals.has(member_name) or Parser.BuiltInChecker.class_has_signal(native_type, member_name):
					methods[member_name] = "\tfunc %s(callable: Callable) -> %s:\n\t\t_control.%s.connect(callable)\n\t\treturn self\n" % [member_name, wrapper, member_name]
					continue
				return _failure("Unknown %s property or signal: %s" % [native_type, member_name])
			var value_type: String
			if script_properties.has(member_name):
				var property: Dictionary = script_properties[member_name]
				if property.usage & PROPERTY_USAGE_READ_ONLY:
					return _failure("Property is not writable: " + member_name)
				value_type = _property_type(property, imports)
			else:
				var setter: String = ClassDB.class_get_property_setter(native_type, member_name)
				if setter.is_empty() or properties[member_name].usage & PROPERTY_USAGE_READ_ONLY:
					return _failure("Property is not writable: %s.%s" % [native_type, member_name])
				var api_type: String = Parser.BuiltInChecker.get_member_type(native_type, member_name)
				if api_type.is_empty():
					return _failure("Cannot resolve setter type: %s.%s" % [native_type, member_name])
				value_type = Parser.Utils.type_path_to_display(Parser.Utils.type_path_from_api_enum(api_type))
			if value_type == "Nil":
				value_type = "Variant"
			methods[member_name] = "\tfunc %s(value: %s) -> %s:\n\t\t_control.%s = value\n\t\treturn self\n" % [member_name, value_type, wrapper, member_name]
	return {"error": OK, "methods": methods}


static func _check_target(script: GDScript) -> Dictionary:
	if not script.resource_path.ends_with(".gd") or not FileAccess.file_exists(script.resource_path):
		return _failure("Custom Sweet UI targets must be file-backed GDScript classes.")
	if not ClassDB.is_parent_class(script.get_instance_base_type(), "Control"):
		return _failure("Custom Sweet UI targets must extend Control: " + script.resource_path)
	if script.has_method("is_abstract") and script.call("is_abstract"):
		return _failure("Custom Sweet UI targets cannot be abstract: " + script.resource_path)
	var base_script = script
	while base_script != null:
		for method in base_script.get_script_method_list():
			if method.name == "_init":
				if method.args.size() > method.default_args.size():
					return _failure("Custom Sweet UI targets need a constructor without required arguments: " + script.resource_path)
				return {"error": OK}
		base_script = base_script.get_base_script()
	return {"error": OK}


static func _import_type(path: String, imports: Dictionary) -> String:
	for alias: String in imports:
		if imports[alias] == path:
			return alias
	var alias = "_SweetTarget%d" % imports.size()
	while imports.has(alias):
		alias += "_"
	imports[alias] = path
	return alias


static func _type_reference(value: String, imports: Dictionary) -> String:
	var script_end = value.find(".gd")
	if script_end >= 0 and (value.begins_with("res://") or value.is_absolute_path()):
		var path = value.left(script_end + 3)
		return _import_type(path, imports) + value.substr(script_end + 3)
	var first = value.get_slice(".", 0)
	for entry in ProjectSettings.get_global_class_list():
		if entry.class == first:
			return _import_type(entry.path, imports) + value.trim_prefix(first)
	return value


static func _property_type(property: Dictionary, imports: Dictionary) -> String:
	if not str(property.class_name).is_empty():
		return _type_reference(str(property.class_name), imports)
	if property.type == TYPE_ARRAY and property.hint == PROPERTY_HINT_ARRAY_TYPE:
		return "Array[%s]" % _type_reference(property.hint_string, imports)
	if property.type == TYPE_DICTIONARY and property.hint == PROPERTY_HINT_DICTIONARY_TYPE:
		var parts = str(property.hint_string).split(";")
		if parts.size() == 2:
			return "Dictionary[%s, %s]" % [_type_reference(parts[0], imports), _type_reference(parts[1], imports)]
	if property.hint == PROPERTY_HINT_TYPE_STRING:
		if property.type == TYPE_ARRAY:
			return "Array[%s]" % _export_element_type(property.hint_string, imports)
		if property.type == TYPE_DICTIONARY:
			var parts = str(property.hint_string).split(";")
			if parts.size() == 2:
				return "Dictionary[%s, %s]" % [_export_element_type(parts[0], imports), _export_element_type(parts[1], imports)]
	return "Variant" if property.type == TYPE_NIL else type_string(property.type)


static func _export_element_type(encoded: String, imports: Dictionary) -> String:
	var type = int(encoded.get_slice(":", 0).get_slice("/", 0))
	if type == TYPE_OBJECT:
		return _type_reference(encoded.substr(encoded.find(":") + 1), imports)
	return "Variant" if type == TYPE_NIL else type_string(type)


static func _collect_methods(parser, name: String) -> Dictionary:
	var chain: Array = []
	var ancestors: Array[String] = []
	var current = name
	while current != "RefCounted":
		if current in ancestors:
			return _failure("Cyclic Sweets prototype inheritance: " + name)
		var prototype = parser.get_class_object(current)
		if prototype == null:
			return _failure("Missing Sweets prototype: " + current)
		ancestors.append(current)
		chain.push_front(prototype)
		current = prototype.extended
	var methods = {}
	for prototype in chain:
		for constant in prototype.constants.values():
			if constant.get(Parser.Keys.ACCESS_PATH) == prototype.access_path:
				return _failure("Prototype constants are not supported: " + name)
		for member_name in prototype.members:
			if member_name != "_control" and not prototype.functions.has(member_name):
				return _failure("Only _control state and operation methods are supported: " + name)
		for method_name in prototype.functions:
			if method_name in ["_init", "node", "c", "ui", "with_parent"]:
				return _failure("Constructors, with_parent(), node(), and ui() are generated: " + name)
			methods[method_name] = prototype.functions[method_name]
	return {"error": OK, "methods": methods, "ancestors": ancestors}


static func _emit_method(method, lines: PackedStringArray, ancestors: Array[String], wrapper: String) -> Dictionary:
	var block: Array[String] = []
	var declaration: String = lines[method.declaration_line]
	var indentation = declaration.left(declaration.length() - declaration.strip_edges(true, false).length())
	for i in range(method.declaration_line, method.end_line + 1):
		block.append(lines[i].trim_prefix(indentation))
	var text = "\n".join(block).strip_edges(false, true)
	# The parser's lexer keeps type-like text inside strings and comments untouched.
	var tokens = Lexer._tokens(text)
	for token in tokens:
		if token.text == "super" or token.text == "static":
			return _failure("Sweets operations must be instance methods without super calls: " + method.name)
	var in_signature = true
	for i in tokens.size():
		var token = tokens[i]
		if in_signature and token.text == ":" and token.depth == 0:
			in_signature = false
		if in_signature and i >= 2 and token.text in ancestors and tokens[i - 1].text == ">" and tokens[i - 2].text == "-":
			text = text.left(token.offset) + wrapper + text.substr(token.end)
			break
	var emitted: Array[String] = []
	for line in text.split("\n"):
		emitted.append("\t" + line if not line.is_empty() else "")
	return {"error": OK, "source": "\n".join(emitted) + "\n"}


static func _failure(message: String, error: Error = ERR_INVALID_DATA) -> Dictionary:
	return {"error": error, "message": message}


class Templates:
	const API_FUNC = \
"func %s(parent: Node = null) -> %s:
	if not is_instance_valid(parent):
		parent = _node
	return %s.with_parent(%s.new(), parent, self)
"
	const API_FROM_FUNC = \
"func %s_from(node: %s, parent: Node = null) -> %s:
	if not is_instance_valid(parent):
		parent = _node
	return %s.with_parent(node, parent, self)
"
	const STATIC_API_FUNC = \
"static func %s(node: %s = null) -> %s:
	if node == null:
		node = %s.new()
	return %s.new(node)
"

	const CLASS_BODY = \
"class %s extends RefCounted:
	var _control: %s
	var _ui:SweetUI

	func node() -> %s:
		return _control

	func c() -> %s:
		return _control

	func ui() -> SweetUI:
		return _ui

"

	const CLASS_INIT = \
"	func _init(control: %s) -> void:
		_control = control

	static func with_parent(control: %s, parent: Node, ui: SweetUI) -> %s:
		var wrapper = %s.new(control)
		parent.add_child(control)
		wrapper._ui = ui
		return wrapper

"
