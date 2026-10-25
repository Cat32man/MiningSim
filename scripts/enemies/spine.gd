extends Node3D
## A burning spine spat by the Magma Hydra. Flies straight (a little drop), hurts the player
## on contact, shatters on rock.

const Sfx = preload("res://scripts/audio/sfx.gd")
const HitFx = preload("res://scripts/enemies/hit_fx.gd")

const GRAVITY := 2.0
const LIFETIME := 2.5

var velocity := Vector3.ZERO
var damage := 3.0
var shooter: CollisionObject3D

var _age := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.045
	c.height = 0.55
	c.radial_segments = 6
	c.rings = 1
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.4, 0.08)
	m.emission_energy_multiplier = 4.0
	mi.material_override = m
	mi.rotation.x = -PI / 2  # point along -Z
	add_child(mi)


func _physics_process(dt: float) -> void:
	_age += dt
	velocity.y -= GRAVITY * dt
	var from := global_position
	var to := from + velocity * dt
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 8)  # rock, buildings, player
	if shooter:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c = hit["collider"]
		if c is Node and c.is_in_group("player"):
			c.take_damage(damage, from)
		HitFx.ichor(get_parent(), hit["position"], from, Color(1.0, 0.5, 0.15))
		queue_free()
		return
	global_position = to
	if velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	if _age > LIFETIME:
		queue_free()
