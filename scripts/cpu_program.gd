extends RefCounted
## Native GDScript program owned by a CPU. Compile first; instantiate only when
## powered, so _init and tick do not execute merely by opening/applying the editor.

const DEFAULT_SOURCE := "extends RefCounted\n\n# tick runs once per physics tick while this CPU receives power.\n# cpu.powered is the input; cpu.output_power controls outgoing wires.\nfunc tick(cpu, delta: float) -> void:\n\tcpu.output_power = true\n"
var source := DEFAULT_SOURCE
var error := ""
var _script: GDScript
var _instance: RefCounted

func compile_program(candidate: String) -> bool:
	var script := GDScript.new()
	script.source_code = candidate
	var result := script.reload()
	if result != OK:
		error = "GDScript compilation failed: %s. Check the syntax and Godot output." % error_string(result)
		return false
	if not script.can_instantiate():
		error = "The program must be a concrete, instantiable GDScript. "
		return false
	if script.get_instance_base_type() != &"RefCounted":
		error = "The program must extend RefCounted."
		return false
	var has_tick := false
	for method in script.get_script_method_list():
		if method.name == &"tick":
			has_tick = method.args.size() == 2
		if method.name == &"_init" and method.args.size() > method.default_args.size():
			error = "_init must not require arguments."
			return false
	if not has_tick:
		error = "Define func tick(cpu, delta) with exactly two arguments."
		return false
	_script = script
	_instance = null
	source = candidate
	error = ""
	return true

func run_tick(cpu: RigidBody2D, delta: float) -> void:
	if _script == null:
		return
	if _instance == null:
		_instance = _script.new()
	if _instance != null:
		_instance.call("tick", cpu, delta)
