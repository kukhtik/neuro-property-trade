class_name Rng
extends RefCounted
## Deterministic, seedable RNG for the authoritative engine.
##
## All randomness flows through this class so the engine is reproducible
## from a seed (stream replay requires it). Uses Godot's PCG-based
## RandomNumberGenerator so results are reproducible within a Godot build.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Re-seed with a specific seed for deterministic replay.
func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

## Roll a single 6-sided die: returns 1..6.
func roll_die() -> int:
	return _rng.randi_range(1, 6)

## Roll two dice: returns the pair [d1, d2] and their sum.
func roll_two_dice() -> Dictionary:
	var d1 := roll_die()
	var d2 := roll_die()
	return {"d1": d1, "d2": d2, "sum": d1 + d2, "doubles": d1 == d2}

## Uniform integer in [min, max] inclusive.
func int_range(vmin: int, vmax: int) -> int:
	return _rng.randi_range(vmin, vmax)

## Uniform float in [0, 1).
func unit() -> float:
	return _rng.randf()
