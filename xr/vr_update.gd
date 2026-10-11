extends RefCounted

var host: WeakRef
var workspace: RefCounted:
    get: return host.get_ref()
var popup: Dictionary = {}
var message: Label
var accept: Button

func _init(value: RefCounted) -> void:
    host = weakref(value)

func consume(data: Dictionary) -> bool:
    if data.get("kind", "") not in ["app_update", "app_update_status"]: return false
    if popup.is_empty():
        popup = workspace.panel(Vector2(0.78, 0.36), Vector2i(1170, 540))
        popup.background.add_theme_stylebox_override("panel", workspace.reader.ui.settings_surface())
        workspace.label(popup.content, "Questium Update", 36)
        message = workspace.label(popup.content, "", 28)
        message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        message.size_flags_vertical = Control.SIZE_EXPAND_FILL
        var actions := HBoxContainer.new()
        popup.content.add_child(actions)
        accept = workspace.button(actions, "Yes, update now", func():
            accept.disabled = true
            workspace.reader._request("app_update_install")
        )
        workspace.button(actions, "No, continue", func():
            popup.node.visible = false
            workspace.hud.node.visible = true
        )
        workspace.reader.ui.theme_settings(popup.content)
    message.text = str(data.get("message", ""))
    accept.disabled = bool(data.get("busy", false))
    if data.kind == "app_update":
        workspace.minimize_popups()
        workspace.raise_popup(popup.node)
    return true
