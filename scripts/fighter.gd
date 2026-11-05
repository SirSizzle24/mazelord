extends Node2D
## Shared by troops and raiders: health, attacking the nearest enemy in range, and being downed.
## unit.gd and raider.gd "extend" this script, so they inherit everything here and add their own parts.

const TARGET_CHECK := 0.2  # seconds between looks for a target
const FLASH_TIME := 0.12  # how long an attack line shows

var max_health := 30.0
var health := 30.0
var damage := 3.0
var attack_range := 50.0  # pixels, center to center
var attack_interval := 1.0  # seconds between attacks
var enemy_group := "hostiles"  # the group this fighter attacks ("hostiles" or "units")
var downed := false

var attack_cooldown := 0.0
var target: Node2D = null
var target_timer := 0.0
var flash_time_left := 0.0
var flash_at := Vector2.ZERO  # where the last attack landed, relative to this fighter


func set_stats(stats: Dictionary) -> void:
	max_health = stats["health"]
	health = max_health
	damage = stats["damage"]
	attack_range = stats["range"]
	attack_interval = stats["attack_interval"]


## Returns true if this hit downed the fighter, so the attacker can be credited.
func take_damage(amount: float) -> bool:
	if downed:
		return false
	health = max(health - amount, 0.0)
	queue_redraw()
	if health == 0.0:
		downed = true
		_on_downed()
		return true
	return false


## Called after each hit this fighter lands. Troops use it to earn fame; raiders ignore it.
func _on_hit_landed(_damage_dealt: float, _downed_it: bool) -> void:
	pass


## Called once when health reaches zero. Troops and raiders each add what they need.
func _on_downed() -> void:
	pass


## Runs combat for one frame. Returns true if there's an enemy in range (whether or not it attacked
## this frame), so raiders know to stand and fight.
func _fight(delta: float) -> bool:
	if downed:
		return false
	attack_cooldown = max(attack_cooldown - delta, 0.0)
	if flash_time_left > 0.0:
		flash_time_left -= delta
		queue_redraw()

	target_timer -= delta
	if target_timer <= 0.0 or not _target_still_good():
		target_timer = TARGET_CHECK
		target = _nearest_enemy_in_range()
	if target == null:
		return false

	if attack_cooldown == 0.0:
		var downed_it: bool = target.take_damage(damage)
		_on_hit_landed(damage, downed_it)
		attack_cooldown = attack_interval
		flash_at = target.position - position
		flash_time_left = FLASH_TIME
		queue_redraw()
	return true


func _target_still_good() -> bool:
	return target != null and is_instance_valid(target) and not target.downed \
		and position.distance_to(target.position) <= attack_range


func _nearest_enemy_in_range() -> Node2D:
	var best: Node2D = null
	var best_distance := attack_range
	for enemy in get_tree().get_nodes_in_group(enemy_group):
		if enemy.downed:
			continue
		var distance := position.distance_to(enemy.position)
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	return best


## The combat marks drawn over a fighter: a health bar once hurt, an attack line, and an X when downed.
func _draw_combat(radius: float) -> void:
	if downed:
		var a := radius * 0.7
		draw_line(Vector2(-a, -a), Vector2(a, a), Color.BLACK, 3.0)
		draw_line(Vector2(-a, a), Vector2(a, -a), Color.BLACK, 3.0)
		return
	if health < max_health:
		var width := radius * 2.0
		var top_left := Vector2(-radius, radius + 6.0)
		draw_rect(Rect2(top_left, Vector2(width, 4.0)), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(top_left, Vector2(width * health / max_health, 4.0)), Color(0.3, 0.9, 0.3))
	if flash_time_left > 0.0:
		draw_line(Vector2.ZERO, flash_at, Color(1.0, 0.9, 0.4), 2.0)
