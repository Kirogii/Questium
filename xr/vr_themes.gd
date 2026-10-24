extends RefCounted

const DEFAULT := "questium_frost"
var host: WeakRef
var workspace: RefCounted:
    get: return host.get_ref()
var entries: Array = []
var selected := DEFAULT
var mode := "dark"

func _init(owner: RefCounted) -> void:
    host = weakref(owner)
    selected = str(workspace.preferences.get_value("appearance", "theme", DEFAULT))
    mode = str(workspace.preferences.get_value("appearance", "mode", "dark"))
    var saved: Dictionary = workspace.preferences.get_value("appearance", "palette", {})
    workspace.reader.ui.apply_palette(selected, saved)

func consume(data: Dictionary) -> void:
    entries = data.get("items", [])
    apply(false)

func render(parent: Container) -> void:
    workspace.label(parent, "Themes", 27)
    workspace.label(parent, "Questium Frost keeps the current glass design. Other palettes come directly from the Android backend.", 18).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var choices := OptionButton.new()
    choices.custom_minimum_size.y = 56
    choices.add_item("Questium Frost (default)")
    choices.set_item_metadata(0, DEFAULT)
    for entry in entries:
        choices.add_item(str(entry.title))
        choices.set_item_metadata(choices.item_count - 1, str(entry.id))
        if str(entry.id) == selected: choices.selected = choices.item_count - 1
    parent.add_child(choices)
    choices.item_selected.connect(func(index: int):
        selected = str(choices.get_item_metadata(index))
        apply(true)
    )
    var appearance := OptionButton.new()
    appearance.custom_minimum_size.y = 56
    appearance.add_item("Dark palette")
    appearance.add_item("Light palette")
    appearance.selected = 1 if mode == "light" else 0
    parent.add_child(appearance)
    appearance.item_selected.connect(func(index: int):
        mode = "light" if index == 1 else "dark"
        apply(true)
    )
    workspace.reader.ui.theme_settings(parent)

func apply(persist: bool) -> void:
    var colors: Dictionary = {}
    for entry in entries:
        if str(entry.id) == selected: colors = entry.get(mode, {})
    if selected != DEFAULT and colors.is_empty():
        colors = workspace.preferences.get_value("appearance", "palette", {})
    workspace.reader.ui.apply_palette(selected, colors)
    if persist:
        workspace.preferences.set_value("appearance", "theme", selected)
        workspace.preferences.set_value("appearance", "mode", mode)
        workspace.preferences.set_value("appearance", "palette", colors)
        workspace.preferences.save("user://library.cfg")
