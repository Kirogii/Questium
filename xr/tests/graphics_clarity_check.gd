extends SceneTree

class Host extends Node3D:
    var preferred_hand := "right"
    var haptics := true
    var scenes_enabled := true
    var books: Array = []
    var bindings: Dictionary = {}

func _initialize() -> void:
    var host := Host.new()
    var ui = load("res://reader_ui.gd").new(host)
    ui.config_path = "user://graphics_clarity_test.cfg"
    ui.config.set_value("reader", "controls_version", 1)
    ui.config.set_value("graphics", "preset", "quest_3s")
    ui.config.set_value("graphics", "eye_scale", 0.90)
    ui.config.set_value("graphics", "foveation", 2)
    ui.config.set_value("graphics", "dynamic_foveation", true)
    assert(ui.config.save(ui.config_path) == OK)
    ui.load_config()
    assert(ui.graphics_eye_scale >= 1.0)
    assert(ui.graphics_ui_scale >= 1.5)
    assert(ui.graphics_foveation == 0 and not ui.graphics_dynamic_foveation)
    assert(ui.graphics_msaa == 2)
    ui.config.set_value("graphics", "preset", "custom")
    assert(ui.config.save(ui.config_path) == OK)
    ui.load_config()
    assert(is_equal_approx(ui.graphics_eye_scale, 0.90), "Custom resolution remains user controlled")
    assert(ui.graphics_foveation == 2 and ui.graphics_dynamic_foveation)
    for preset in ui.GRAPHICS_PRESETS.values():
        assert(preset.foveation == 0 and not preset.dynamic_foveation)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(ui.config_path))
    host.free()
    print("PASS: reading clarity presets, existing preset upgrade, custom settings preserved")
    quit()
