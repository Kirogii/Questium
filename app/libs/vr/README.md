Godot OpenXR Vendors 5.1.0 (Meta release AAR), from the official release:
https://github.com/GodotVR/godot_openxr_vendors/releases/tag/5.1.0-stable

The Android runtime uses Godot 4.6.3.stable with the Godot 4.6 export format.
Earlier 4.6 Android template libraries reject --main-pack, preventing startup
of the embedded reader. OpenXR Vendors 5.1.0 supports Godot 4.6.
Meta loader/SDK license texts are included beside the AAR. The plugin source is
MIT licensed: https://github.com/GodotVR/godot_openxr_vendors/blob/master/LICENSE

The AAR supplies the Android plugin registration, OpenXR permissions,
GDExtension descriptor, and arm64/x86_64 native libraries. Do not add another
OpenXR loader or a separately exported Godot APK.
