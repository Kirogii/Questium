# Optional VR scene assets

Place an imported `bar_end.tscn`, `bar_end.glb`, `bar_end.gltf`, or `bar_end.fbx`
in this folder. `room.gd` loads the first supported packed scene at runtime and
always adds its own floor/wall/seat collision shell.

The currently inspected `D:/VR Kommiku/scenes/bar_end.fbx` is outside this
Godot project, so it is not treated as a packaged resource. Until it is copied
or imported here, the procedural bar fallback is the active map and no missing
geometry is assumed.
