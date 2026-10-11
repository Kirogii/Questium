# Default bar scene

`bar_end.fbx` is the packaged copy of `D:/VR Kommiku/scenes/bar_end.fbx`.
`room.gd` loads this model, preserves its texture atlases, and derives the floor,
table collisions, stool/booth targets and pendant-bulb positions from its meshes.

The map uses smooth dark lighting, glossy counters/tables/floor, a static room
reflection probe, depth-clipped light shafts, sparse dust and animated white fire.
The Quest renderer uses a bounded 24-sample beam with stable midpoint sampling,
per-eye camera coordinates and hardware depth testing. Each beam ends just above
the first table/counter/floor collision below its imported bulb. Scene depth clips
scattering against opaque objects within the beam.

The startup view faces the counter (+Z). Quest uses 1.25x recommended eye dimensions,
4x MSAA, no peripheral foveation and 1.5x UI textures with unchanged logical input
coordinates. Camera-backed glass stays blurred; its fallback is a stable tinted
surface without a fullscreen screen-texture copy. These settings require headset
frame-time verification; they cannot increase the physical display resolution.
