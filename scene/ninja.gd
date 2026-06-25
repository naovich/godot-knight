extends CharacterBody2D

## Vitesse de déplacement horizontale max (pixels/seconde).
@export var speed: float = 800.0

## Tant que c'est désactivé, le ninja ne se déplace pas : on règle juste les animations sur place.
## Passe-le à true (dans l'inspecteur) quand les animations seront prêtes.
@export var movement_enabled: bool = false

# Noms des animations définies dans le SpriteFrames de l'AnimatedSprite2D.
const ANIM_IDLE := "idle"
const ANIM_ACCELERATION := "acceleration"
const ANIM_COURSE := "course"
const ANIM_DECELERATION := "deceleration"

# États : IDLE et COURSE sont des animations en boucle ; TRANSITION couvre l'élan ET le
# freinage. Pendant une transition on reste sur UN seul clip (acceleration ou deceleration)
# et on parcourt ses images en avant/arrière selon la touche -> aucun saut de posture.
enum State { IDLE, COURSE, TRANSITION }

var _state: State = State.IDLE
# Clip de la transition en cours ("acceleration" ou "deceleration").
var _clip: String = ""
# Position (image flottante) dans le clip de transition.
var _pos: float = 0.0
# Sens vers lequel on accélère/court (-1 gauche, +1 droite), conservé pendant les transitions.
var _facing: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_enter_idle()


func _physics_process(delta: float) -> void:
	# Direction voulue : -1 (gauche), 0 (rien), +1 (droite). pressing = une touche est tenue.
	var direction: float = Input.get_axis("move_left", "move_right")
	var pressing: bool = direction != 0.0

	# Mémorise le sens uniquement quand une touche est pressée.
	if pressing:
		_facing = direction
		animated_sprite.flip_h = direction < 0.0

	_update_state(pressing, delta)
	_update_movement()


# --- Machine à états ---

func _update_state(pressing: bool, delta: float) -> void:
	match _state:
		State.IDLE:
			if pressing:
				_enter_transition(ANIM_ACCELERATION)   # debout -> on prend de l'élan
		State.COURSE:
			if not pressing:
				_enter_transition(ANIM_DECELERATION)    # pleine course -> on freine
		State.TRANSITION:
			_advance_transition(pressing, delta)


## Fait progresser la transition : vers la course si on tient la touche, vers l'arrêt sinon.
## La touche peut changer à tout moment -> on parcourt le MÊME clip en avant ou en arrière.
func _advance_transition(pressing: bool, delta: float) -> void:
	var last: float = animated_sprite.sprite_frames.get_frame_count(_clip) - 1
	# Sur 'acceleration' l'image 0 = arrêt et la dernière = course.
	# Sur 'deceleration' c'est l'inverse (image 0 = course, dernière = arrêt).
	var course_end: float = last if _clip == ANIM_ACCELERATION else 0.0
	var idle_end: float = 0.0 if _clip == ANIM_ACCELERATION else last

	# On avance à la vitesse propre du clip (réglable dans l'éditeur SpriteFrames).
	var step: float = animated_sprite.sprite_frames.get_animation_speed(_clip) * delta
	var target: float = course_end if pressing else idle_end
	_pos = move_toward(_pos, target, step)

	if _pos == target:
		# On a atteint un bout du clip -> on bascule sur l'état stable correspondant.
		if pressing:
			_enter_course()
		else:
			_enter_idle()
		return

	animated_sprite.frame = int(round(_pos))


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
	# On entre toujours par le bout "course" du freinage ou le bout "arrêt" de l'élan,
	# c'est-à-dire l'image 0 des deux clips.
	_pos = 0.0
	animated_sprite.animation = clip
	animated_sprite.pause()          # on pilote l'image à la main, pas de lecture auto
	animated_sprite.frame = 0


# --- Déplacement réel (désactivé tant que movement_enabled est faux) ---
# La vitesse suit la PROGRESSION de l'animation (pas un freinage indépendant) :
# vitesse = speed × ratio, où ratio = 1 en pleine course et 0 à l'arrêt. Elle atteint
# donc 0 pile quand l'animation atteint l'idle -> plus de patinage.

func _update_movement() -> void:
	if not movement_enabled:
		return
	velocity.x = _facing * speed * _current_speed_ratio()
	move_and_slide()


## Vitesse normalisée : 0 = arrêt (idle), 1 = pleine course. Déduite de l'état et de la
## progression dans le clip de transition.
func _current_speed_ratio() -> float:
	match _state:
		State.COURSE:
			return 1.0
		State.TRANSITION:
			var last: float = animated_sprite.sprite_frames.get_frame_count(_clip) - 1
			if last <= 0.0:
				return 0.0
			# idle_end = image "arrêt" du clip ; le ratio est la distance à cette image.
			var idle_end: float = 0.0 if _clip == ANIM_ACCELERATION else last
			return clampf(absf(_pos - idle_end) / last, 0.0, 1.0)
		_:
			return 0.0
