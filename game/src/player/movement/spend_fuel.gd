extends Object

## Definition: the all-or-nothing fuel spend — the only way anything drains
## fuel (DESIGN.md §5). Spec: spend_fuel.gd.md.


static func spend_fuel(sim: MoveSim, amount: float) -> bool:
	if sim.fuel < amount:
		return false
	sim.fuel -= amount
	return true
