extends SceneTree

const Prop = preload("res://scripts/prop.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func make_prop(kind: String):
	var prop = Prop.new()
	prop.configure(kind)
	root.add_child(prop)
	prop.gravity_scale = 0
	return prop

func run() -> void:
	var truth_tables := {
		"and_gate": [false, false, false, true],
		"or_gate": [false, true, true, true],
		"xor_gate": [false, true, true, false],
	}
	var signals := [[false, false], [false, true], [true, false], [true, true]]
	for kind in truth_tables:
		var gate = make_prop(kind)
		for i in signals.size():
			gate.set_power_inputs(signals[i], 1.0 / 120)
			check(gate.output_power == truth_tables[kind][i], "%s inputs %s" % [kind, signals[i]])
		gate.set_power_inputs([], 1.0 / 120)
		check(not gate.output_power, "%s no disconnected input signal" % kind)
		gate.toggle_activation()
		gate.set_power_inputs([true, true], 1.0 / 120)
		check(not gate.output_power, "%s deactivation blocks output" % kind)
	var not_gate = make_prop("not_gate")
	not_gate.set_power_inputs([], 0.01)
	check(not not_gate.output_power, "NOT disconnected is off")
	not_gate.set_power_inputs([false], 0.01)
	check(not_gate.output_power, "NOT low input is high")
	not_gate.set_power_inputs([true], 0.01)
	check(not not_gate.output_power, "NOT high input is low")
	var xor_gate = make_prop("xor_gate")
	xor_gate.set_power_inputs([true, true, true], 0.01)
	check(xor_gate.output_power, "XOR supports parity with more than two inputs")
	var lever = make_prop("lever")
	lever.set_power_inputs([], 0.01)
	check(not lever.activated and not lever.output_power, "lever starts inactive")
	lever.toggle_activation()
	check(lever.activated and lever.output_power, "activation immediately powers lever output")
	lever.set_power_inputs([false], 0.01)
	check(lever.output_power, "lever does not require incoming power")
	lever.toggle_activation()
	check(not lever.output_power, "second activation switches lever off")
	var plain = make_prop("box")
	plain.set_power_inputs([true, false], 0.01)
	check(plain.powered and plain.output_power, "normal physical object passes through power")
	plain.set_power_inputs([false], 0.01)
	check(not plain.output_power, "normal object stops after input disappears")

	var cpu = make_prop("cpu")
	check(cpu.program_error.is_empty(), "default CPU program compiles")
	cpu.set_power_inputs([false], 0.01)
	check(not cpu.powered and not cpu.output_power, "unpowered CPU stays off")
	cpu.set_power_inputs([true], 0.01)
	check(cpu.powered and cpu.output_power, "default CPU passes incoming current")
	var source := "extends RefCounted\nvar count := 0\nfunc tick(cpu, delta):\n\tcount += 1\n\tcpu.set_meta(\"calls\", count)\n\tcpu.set_meta(\"delta\", delta)\n\tcpu.output_power = count % 2 == 0\n"
	check(cpu.set_program(source), "user program compiles")
	cpu.set_power_inputs([false], 0.02)
	check(not cpu.has_meta("calls"), "no tick calls while unpowered")
	cpu.set_power_inputs([true], 0.02)
	check(cpu.get_meta("calls") == 1 and not cpu.output_power, "powered CPU executes first tick and controls output")
	cpu.set_power_inputs([true], 0.03)
	check(cpu.get_meta("calls") == 2 and cpu.output_power and is_equal_approx(cpu.get_meta("delta"), 0.03), "powered CPU loops with delta and persistent program state")
	cpu.set_power_inputs([false], 0.01)
	check(cpu.get_meta("calls") == 2 and not cpu.output_power, "removing power stops execution and clears output")
	cpu.set_world_paused(true)
	cpu.set_power_inputs([true], 0.01)
	check(cpu.get_meta("calls") == 2, "paused CPU does not execute even if called with power")
	cpu.set_world_paused(false)
	cpu.toggle_activation()
	cpu.set_power_inputs([true], 0.01)
	check(cpu.get_meta("calls") == 2 and not cpu.output_power, "disabled CPU stops execution")
	cpu.toggle_activation()
	check(not cpu.set_program("extends RefCounted\nfunc other():\n\tpass\n") and not cpu.program_error.is_empty(), "missing tick is rejected with editor feedback")
	check(cpu.program_source == source, "rejected program preserves source of last valid program")
	cpu.set_power_inputs([true], 0.01)
	check(cpu.get_meta("calls") == 3, "last valid CPU program continues after rejected edit")
	check(not cpu.set_program("extends Node\nfunc tick(cpu, delta):\n\tpass\n"), "Node script is rejected")
	check(not cpu.set_program("extends RefCounted\nfunc _init(required):\n\tpass\nfunc tick(cpu, delta):\n\tpass\n"), "constructor with required arguments is rejected")
	check(not cpu.set_program("extends RefCounted\nfunc tick(cpu):\n\tpass\n"), "wrong tick signature is rejected")
	var deferred_source := "extends RefCounted\nfunc _init():\n\tEngine.set_meta(\"timeplayground_cpu_init\", true)\nfunc tick(cpu, delta):\n\tcpu.output_power = true\n"
	Engine.remove_meta("timeplayground_cpu_init")
	check(cpu.set_program(deferred_source) and not Engine.has_meta("timeplayground_cpu_init"), "compilation does not execute program constructor")
	cpu.set_power_inputs([true], 0.01)
	check(Engine.has_meta("timeplayground_cpu_init"), "program constructor runs only on first powered tick")
	Engine.remove_meta("timeplayground_cpu_init")
	for prop in [plain, lever, not_gate, cpu]:
		prop.flip_object()
		check(prop.flipped and (prop.sprite == null or prop.sprite.flip_h), "%s mirrors sprite" % prop.kind)
		prop.flip_object()
		check(not prop.flipped, "%s mirror toggle restores orientation" % prop.kind)
	print("Electronics checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
