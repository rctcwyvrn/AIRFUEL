extends Object

## Definition: WASD input to a world-space horizontal wish direction through
## the body's yaw basis. Spec: wish_dir.gd.md.


static func wish_dir(move_input: Vector2, basis: Basis) -> Vector3:
	if move_input == Vector2.ZERO:
		return Vector3.ZERO
	return (basis.x * move_input.x + -basis.z * -move_input.y).normalized()
