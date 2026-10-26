class_name SweetsGen
extends RefCounted

const Parser = preload("res://addons/_lib/gdscript_parser/src/gdscript_parser.gd")
const Lexer = preload("res://addons/_lib/gdscript_parser/src/utils/lambda_scanner.gd")

const SOURCE = "res://addons/code_ui/_export_ignore/generate/sweets_source.gd"
const TARGET = "res://addons/code_ui/src/class/sweets.gd"
const START = "### GENERATED START"
const END = "### GENERATED END"


static func generate(target_path: String = TARGET, source_path: String = SOURCE) -> Error:
	var result = _generate_file(target_path, source_path)
	if result.error != OK:
		push_error(result.message)
	else:
		print("Sweets generated: " + target_path if result.changed else "Sweets already up to date.")
	return result.error


static func _generate_file(target_path: String, source_path: String = SOURCE) -> Dictionary:
	var file = FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		return _failure("Cannot read Sweets target: " + target_path, FileAccess.get_open_error())
	var original = file.get_as_text()
	file.close()
	var result = build_candidate(original, source_path, target_path)
	if result.error != OK:
		return result
	return _write_outputs({result.classes_path: result.classes_source, target_path: result.source})


static func _write_outputs(outputs: Dictionary) -> Dictionary:
	var pending: Array[String] = []
	for path: String in outputs:
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == outputs[path]:
			continue
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


static func build_candidate(original: String, source_path: String = SOURCE, target_path: String = TARGET) -> Dictionary:
	var marker = RegEx.new()
	marker.compile("(?m)^### GENERATED (START|END)\\r?$")
	var matches = marker.search_all(original)
	if matches.size() != 2 or matches[0].get_string(1) != "START" or matches[1].get_string(1) != "END":
		return _failure("Sweets needs exactly one ordered pair of generation markers.")
	var generated = _build_region(source_path)
	if generated.error != OK:
		return generated
	var classes_path = target_path.get_base_dir().path_join("sweets_generated.gd")
	var classes = GDScript.new()
	classes.set_path_cache(classes_path)
	classes.source_code = generated.classes_source
	var error = classes.reload()
	if error != OK:
		return _failure("Generated wrapper classes did not compile: " + error_string(error), error)
	var newline = "\r\n" if original.contains("\r\n") else "\n"
	var preload_line = "const _Generated = preload(%s)\n" % var_to_str(classes_path)
	var region: String = (preload_line + generated.source).replace("\n", newline)
	var start_end: int = matches[0].get_start() + START.length()
	var prefix = original.left(start_end) + newline
	var suffix = original.substr(matches[1].get_start())
	var candidate = prefix + region + suffix
	# Validate aliases against staged classes, rather than the previous generated file.
	var temp_dir = OS.get_environment("TMPDIR")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	var staged_classes = temp_dir.path_join("sweets_validate_%d.gd" % Time.get_ticks_usec())
	var staged_file = FileAccess.open(staged_classes, FileAccess.WRITE)
	if staged_file == null:
		return _failure("Cannot stage wrapper validation.", FileAccess.get_open_error())
	staged_file.store_string(generated.classes_source)
	staged_file.close()
	var staged_preload = "const _Generated = preload(%s)\n" % var_to_str(staged_classes)
	var validation = GDScript.new()
	validation.set_path_cache(target_path)
	validation.source_code = prefix + (staged_preload + generated.source).replace("\n", newline) + suffix
	error = validation.reload()
	DirAccess.remove_absolute(staged_classes)
	if error != OK:
		return _failure("Generated Sweets did not compile: " + error_string(error), error)
	return {"error": OK, "source": candidate, "classes_source": generated.classes_source,
		"classes_path": classes_path, "validation": validation}



static func _build_region(source_path: String) -> Dictionary:
	if not FileAccess.file_exists(source_path):
		return _failure("Sweets prototype source not found: " + source_path, ERR_FILE_NOT_FOUND)
	var source_text = FileAccess.get_file_as_string(source_path)
	var source_script = GDScript.new()
	source_script.set_path_cache(source_path)
	source_script.source_code = source_text
	var error = source_script.reload()
	if error != OK:
		return _failure("Sweets prototypes did not compile: " + error_string(error), error)
	var settings = source_script.get_script_constant_map()
	var overrides = settings.get("TYPES", {})
	var re_export = settings.get("RE_EXPORT", false)
	if overrides is not Dictionary or re_export is not bool:
		return _failure("Sweets needs a TYPES dictionary and a boolean RE_EXPORT setting.")
	var parser = Parser.new()
	parser.set_use_native_backend(false)
	parser.set_cache_enabled(false)
	parser.active_parser = parser
	parser.set_current_script(source_script)
	parser.set_source_code(source_text)
	parser.parse(true)
	var result = _emit_prototypes(parser, overrides, re_export, source_text.split("\n"))
	parser.code_edit.free()
	parser.code_edit = null
	parser.active_parser = null
	return result


static func _emit_prototypes(parser, overrides: Dictionary, re_export: bool, lines: PackedStringArray) -> Dictionary:
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
	var wrappers: Array[String] = []
	var aliases: Array[String] = []
	var used_factories: Array[String] = []
	for name in names:
		if name is not String or not name.is_valid_ascii_identifier():
			return _failure("Invalid Sweets wrapper name: " + str(name))
		var entry = overrides.get(name, {})
		if entry is not Dictionary:
			return _failure("Invalid Sweets catalog entry: " + name)
		var inferred_type = name.trim_prefix("Sw")
		var native_type = str(entry.get("node", inferred_type))
		var factory = str(entry.get("factory", inferred_type.to_snake_case()))
		if not ClassDB.is_parent_class(native_type, "Control") or not factory.is_valid_ascii_identifier():
			return _failure("Sweets entries need a Control type and factory name: " + name)
		if factory in used_factories:
			return _failure("Duplicate Sweets factory: " + factory)
		used_factories.append(factory)
		var collected = _collect_methods(parser, name)
		if collected.error != OK:
			return collected
		var methods: Dictionary = collected.methods
		var method_names = methods.keys()
		method_names.sort()
		var output = "class %s extends RefCounted:\n\tvar _control: %s\n\n\n" % [name, native_type]
		output += "\tfunc _init(control: %s, parent: Node) -> void:\n\t\t_control = control\n\t\tparent.add_child(control)\n\n\n" % native_type
		output += "\tfunc node() -> %s:\n\t\treturn _control\n" % native_type
		for method_name in method_names:
			var emitted = _emit_method(methods[method_name], lines, collected.ancestors, name)
			if emitted.error != OK:
				return emitted
			output += "\n\n" + emitted.source
		wrappers.append(output)
		if re_export:
			aliases.append("const %s = _Generated.%s" % [name, name])
		var wrapper_type = name if re_export else "_Generated." + name
		factories.append("func %s(parent: Node = null) -> %s:\n\tif not is_instance_valid(parent):\n\t\tparent = _node\n\treturn %s.new(%s.new(), parent)\n" % [factory, wrapper_type, wrapper_type, native_type])
	var region = "# Generated by SweetsGen from _export_ignore/generate/sweets_source.gd.\n"
	if not aliases.is_empty():
		region += "\n".join(aliases) + "\n"
	region += "\n\n"
	region += "\n\n".join(factories) + "\n"
	var classes_source = "extends RefCounted\n\n# Generated by SweetsGen. Do not edit.\n\n"
	classes_source += "\n\n".join(wrappers)
	return {"error": OK, "source": region, "classes_source": classes_source}


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
			if method_name in ["_init", "node"]:
				return _failure("Constructors and node() are generated: " + name)
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
