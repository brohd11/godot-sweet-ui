class_name SweetsGen
extends RefCounted

const Parser = preload("res://addons/_lib/gdscript_parser/src/gdscript_parser.gd")
const Lexer = preload("res://addons/_lib/gdscript_parser/src/utils/lambda_scanner.gd")
const TagScanner = preload("res://addons/_lib/editor_parser/src/tag/scanner.gd")

const SOURCE = "res://addons/sweet_ui/_export_ignore/generate/sweets_source.gd"
const TARGET = "res://addons/sweet_ui/src/sweet_ui.gd"
const CLASSES_TARGET = "res://addons/sweet_ui/src/gen/sweets_generated.gd"
const START = "### GENERATED START"
const END = "### GENERATED END"


static func generate() -> Error:
	var result = _generate_file(TARGET)
	if result.error != OK:
		push_error(result.message)
	else:
		print("Sweets generated: " + TARGET if result.changed else "Sweets already up to date.")
	return result.error


static func _generate_file(target_path: String, source_path: String = SOURCE, classes_path: String = CLASSES_TARGET) -> Dictionary:
	var file = FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		return _failure("Cannot read Sweets target: " + target_path, FileAccess.get_open_error())
	var original = file.get_as_text()
	file.close()
	var result = build_candidate(original, source_path, target_path, classes_path)
	if result.error != OK:
		return result
	_clear_validation(result.validation)
	return _write_outputs({result.classes_path: result.classes_source, target_path: result.source})


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
static func build_candidate(original: String, source_path: String = SOURCE, target_path: String = TARGET, classes_path: String = CLASSES_TARGET) -> Dictionary:
	var marker = RegEx.new()
	marker.compile("(?m)^### GENERATED (START|END)\\r?$")
	var matches = marker.search_all(original)
	if matches.size() != 2 or matches[0].get_string(1) != "START" or matches[1].get_string(1) != "END":
		return _failure("Sweets needs exactly one ordered pair of generation markers.")
	var generated = _build_region(source_path)
	if generated.error != OK:
		return generated
	var classes = GDScript.new()
	classes.set_path_cache(_validation_path(classes_path))
	classes.source_code = generated.classes_source
	var error = classes.reload()
	_clear_validation(classes)
	if error != OK:
		return _failure("Generated wrapper classes did not compile: " + error_string(error), error)
	var newline = "\r\n" if original.contains("\r\n") else "\n"
	var preload_line = "const _Generated = preload(%s)\n" % var_to_str(classes_path)
	var region: String = (preload_line + generated.source).replace("\n", newline)
	var start_end: int = matches[0].get_start() + START.length()
	var prefix = original.left(start_end) + newline
	var suffix = original.substr(matches[1].get_start())
	var candidate = prefix + region + suffix
	# A local owner type keeps self typed without touching the editor's cached scripts.
	var validation_path = _validation_path(target_path)
	var validation_name = "SweetsValidation" + validation_path.get_file().get_basename().trim_prefix("__sweets_validate_")
	var wrapper_source: String = generated.classes_source.trim_prefix("extends RefCounted\n")
	var factory_source: String = generated.source
	if generated.re_export:
		# Local wrapper classes already expose the names exported by the real preload aliases.
		var aliases = RegEx.new()
		aliases.compile("(?m)^const Sw[A-Za-z_0-9]* = _Generated\\.Sw[A-Za-z_0-9]*\n")
		factory_source = aliases.sub(factory_source, "", true)
	else:
		var nested_classes = "class _Generated extends RefCounted:\n"
		for line in wrapper_source.split("\n"):
			nested_classes += ("\t" + line if not line.is_empty() else "") + "\n"
		wrapper_source = nested_classes
	var validation_source = prefix + wrapper_source + "\n" + factory_source + suffix
	validation_source = _rename_identifier(validation_source, "SweetUI", validation_name)
	if not validation_source.contains("class_name " + validation_name):
		validation_source = "class_name " + validation_name + "\n" + validation_source
	var validation = GDScript.new()
	validation.set_path_cache(validation_path)
	validation.source_code = validation_source
	error = validation.reload()
	if error != OK:
		_clear_validation(validation)
		return _failure("Generated Sweets did not compile: " + error_string(error), error)
	return {"error": OK, "source": candidate, "classes_source": generated.classes_source,
		"classes_path": classes_path, "validation": validation}


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
	var result = _emit_prototypes(parser, overrides, re_export, source_text.split("\n"))
	parser.code_edit.free()
	parser.code_edit = null
	parser.active_parser = null
	_clear_validation(source_script)
	return result


static func _emit_prototypes(parser, overrides: Dictionary, re_export: bool, lines: PackedStringArray) -> Dictionary:
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
		var setters = _emit_setters(native_type, name, collected.ancestors, tags.members)
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
		var output = Templates.CLASS_BODY % [name, native_type, native_type]
		output += Templates.CLASS_INIT % [native_type]
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
	var region = "# Generated by SweetsGen from _export_ignore/generate/sweets_source.gd.\n"
	if not aliases.is_empty():
		region += "\n".join(aliases) + "\n"
	region += "\n\n"
	region += "\n\n".join(factories) + "\n"
	var classes_source = "extends RefCounted\n\n# Generated by SweetsGen. Do not edit.\n\n"
	classes_source += "\n\n".join(wrappers)
	return {"error": OK, "source": region, "classes_source": classes_source, "re_export": re_export}


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


static func _emit_setters(native_type: String, wrapper: String, ancestors: Array[String], tags: Dictionary) -> Dictionary:
	var properties: Dictionary = {}
	for property in ClassDB.class_get_property_list(native_type):
		properties[property.name] = property
	var methods: Dictionary = {}
	for ancestor in ancestors:
		for member_name: String in tags.get(ancestor, []):
			if methods.has(member_name):
				continue
			if member_name in ["_init", "node", "ui"]:
				return _failure("Set member conflicts with generated method: " + member_name)
			if not properties.has(member_name):
				if Parser.BuiltInChecker.class_has_signal(native_type, member_name):
					methods[member_name] = "\tfunc %s(callable: Callable) -> %s:\n\t\t_control.%s.connect(callable)\n\t\treturn self\n" % [member_name, wrapper, member_name]
					continue
				return _failure("Unknown %s property or signal: %s" % [native_type, member_name])
			var setter: String = ClassDB.class_get_property_setter(native_type, member_name)
			if setter.is_empty() or properties[member_name].usage & PROPERTY_USAGE_READ_ONLY:
				return _failure("Property is not writable: %s.%s" % [native_type, member_name])
			var api_type: String = Parser.BuiltInChecker.get_member_type(native_type, member_name)
			if api_type.is_empty():
				return _failure("Cannot resolve setter type: %s.%s" % [native_type, member_name])
			var value_type = Parser.Utils.type_path_to_display(Parser.Utils.type_path_from_api_enum(api_type))
			if value_type == "Nil":
				value_type = "Variant"
			methods[member_name] = "\tfunc %s(value: %s) -> %s:\n\t\t_control.%s = value\n\t\treturn self\n" % [member_name, value_type, wrapper, member_name]
	return {"error": OK, "methods": methods}


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
			if method_name in ["_init", "node", "ui"]:
				return _failure("Constructors, node(), and ui() are generated: " + name)
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
	return %s.new(%s.new(), parent, self)
"

	const CLASS_BODY = \
"class %s extends RefCounted:
	var _control: %s
	var _ui:SweetUI
	
	func node() -> %s:
		return _control
	
	func ui() -> SweetUI:
		return _ui
"

	const CLASS_INIT = \
"	func _init(control: %s, parent: Node, ui:SweetUI) -> void:
		_control = control
		parent.add_child(control)
		_ui = ui
	
"
