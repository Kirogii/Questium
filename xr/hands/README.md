# Tracked hand fallback

The left/right humanoid rigs, their binary buffers and `hand.png` come from the official Godot OpenXR hand tracking demo at commit `3e08537616661a5883831628decab4c526260289`:

https://github.com/godotengine/godot-demo-projects/tree/3e08537616661a5883831628decab4c526260289/xr/openxr_hand_tracking_demo/assets/gltf

The original `LeftHandHumanoid.gltf` and `RightHandHumanoid.gltf` were renamed to `left.gltf` and `right.gltf`. Their rigs already use the bone convention expected by Godot's `XRHandModifier3D`. The included project license applies; see `LICENSE`.

These are skinned fallback meshes. The runtime-provided Meta hand mesh replaces them when available. Both use the app's white/purple outline material and tracked joint poses. No controller-pose animation or capsule placeholder is substituted for natural hand tracking.
