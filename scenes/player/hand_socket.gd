class_name HandSocket
extends Node3D
## Where a carried item rides: this node mirrors a hand bone's world pose
## every physics tick, so anything parented under it (the torch) moves with
## the arm swing. It lives beside the Visual instead of inside the skeleton
## because the Meshy rig is authored in centimetres — its Armature carries a
## 0.01 scale, and a child of the Skeleton3D would inherit it. Mirroring the
## bone's *global* pose orthonormalized sidesteps the whole trap.
##
## Costs nothing while empty: the mirror only runs when something is carried.

## The skeleton inside the player's Visual, and the bone to follow.
@export var skeleton_path: NodePath = ^"../Visual/Armature/Skeleton3D"
@export var bone_name: String = "RightHand"

var _skeleton: Skeleton3D = null
var _bone: int = -1


func _ready() -> void:
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton != null:
		_bone = _skeleton.find_bone(bone_name)
	child_order_changed.connect(_update_active)
	_update_active()


func _physics_process(_delta: float) -> void:
	global_transform = (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_bone)
	).orthonormalized()


func _update_active() -> void:
	set_physics_process(_skeleton != null and _bone >= 0 and get_child_count() > 0)
