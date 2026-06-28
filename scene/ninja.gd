extends CharacterBody2D

## Vitesse de course max (pixels/seconde). À régler pour que les pieds ne patinent
## pas en pleine course.
@export var speed: float = 800.0

## Si désactivé, le ninja ne se déplace pas réellement (les animations tournent quand
## même, pilotées par la progression du clip).
@export var movement_enabled: bool = false

## Courbe du profil de vitesse (1 = linéaire ; 2 = ease). Plus haut = démarrage plus doux
## et arrêt plus net (retombe à 0 quand les jambes se posent). N'affecte QUE la vitesse au
## sol, pas la cadence des jambes.
@export var speed_curve: float = 2.0

# Noms des animations définies dans le SpriteFrames de l'AnimatedSprite2D.
const ANIM_IDLE := "idle"
const ANIM_ACCELERATION := "acceleration"
const ANIM_COURSE := "course"
const ANIM_DECELERATION := "deceleration"

# IDLE et COURSE = boucles. TRANSITION couvre élan ET freinage : on reste sur UN seul clip,
# joué à sa CADENCE NATURELLE (donc les jambes vont à la même vitesse que la course, c'est
# cohérent), et la vitesse au sol suit la progression via une courbe `speed_curve`.
enum State { IDLE, COURSE, TRANSITION }

var _state: State = State.IDLE
# Clip de la transition en cours.
var _clip: String = ""
# Position (image flottante) dans le clip de transition.
var _pos: float = 0.0
# Sens (-1 gauche / +1 droite).
var _facing: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_enter_idle()


func _physics_process(delta: float) -> void:
	var direction: float = Input.get_axis("move_left", "move_right")
	var pressing: bool = direction != 0.0
	if pressing:
		_facing = direction
		animated_sprite.flip_h = direction < 0.0

	_update_state(pressing, delta)

	velocity.x = _facing * speed * _speed_ratio()
	if movement_enabled:
		move_and_slide()


# --- Machine à états ---

func _update_state(pressing: bool, delta: float) -> void:
	match _state:
		State.IDLE:
			if pressing:
				_enter_transition(ANIM_ACCELERATION)
		State.COURSE:
			if not pressing:
				_enter_transition(ANIM_DECELERATION)
		State.TRANSITION:
			_advance_transition(pressing, delta)


## Avance le clip à sa CADENCE NATURELLE (la vitesse propre du clip), vers la course
## (touche tenue) ou l'arrêt (relâchée). La touche peut changer -> on inverse sur le clip.
func _advance_transition(pressing: bool, delta: float) -> void:
	var last: float = animated_sprite.sprite_frames.get_frame_count(_clip) - 1
	# acceleration : image 0 = arrêt, dernière = course. deceleration : l'inverse.
	var course_end: float = last if _clip == ANIM_ACCELERATION else 0.0
	var idle_end: float = 0.0 if _clip == ANIM_ACCELERATION else last

	var step: float = animated_sprite.sprite_frames.get_animation_speed(_clip) * delta
	var target: float = course_end if pressing else idle_end
	_pos = move_toward(_pos, target, step)

	if _pos == target:
		if pressing:
			_enter_course()
		else:
			_enter_idle()
		return

	animated_sprite.frame = int(round(_pos))


## Vitesse normalisée (courbée) : 0 = arrêt, 1 = pleine course.
func _speed_ratio() -> float:
	match _state:
		State.COURSE:
			return 1.0
		State.TRANSITION:
			var last: float = animated_sprite.sprite_frames.get_frame_count(_clip) - 1
			if last <= 0.0:
				return 0.0
			var idle_end: float = 0.0 if _clip == ANIM_ACCELERATION else last
			var ratio: float = clampf(absf(_pos - idle_end) / last, 0.0, 1.0)
			return pow(ratio, speed_curve)
		_:
			return 0.0


# --- Entrées d'état ---

func _enter_idle() -> void:
	_state = State.IDLE
	animated_sprite.play(ANIM_IDLE)


func _enter_course() -> void:
	_state = State.COURSE
	animated_sprite.play(ANIM_COURSE)


func _enter_transition(clip: String) -> void:
	_state = State.TRANSITION
	_clip = clip
	_pos = 0.0
	animated_sprite.animation = clip
	animated_sprite.pause()
	animated_sprite.frame = 0
