class_name Battery
extends RefCounted
## 12 V lead-acid battery: open-circuit voltage minus sag across its internal
## (plus wiring) resistance.

# Short lag so motor current and bus voltage do not chase each other tick to tick.
const _LAG := 0.01

var open_circuit_voltage := 12.6
var resistance := 0.02
var voltage := 12.6
var current := 0.0


func step(total_current: float, dt: float) -> void:
	current = total_current
	var target := clampf(open_circuit_voltage - resistance * total_current, 0.0, 14.5)
	voltage += (target - voltage) * (1.0 - exp(-dt / _LAG))
