extends RefCounted

var materials: Array[ShaderMaterial] = []
var room: ImageTexture
var elapsed := 0.0
var stale := 10.0

func register(material: ShaderMaterial) -> void:
    materials.append(material)

func update(reader: Node3D, delta: float) -> void:
    elapsed += delta
    stale += delta
    if elapsed < 0.08: return
    elapsed = 0
    if reader.bridge and reader.bridge.has_method("frostedRoomFrame"):
        var data: PackedByteArray = reader.bridge.call("frostedRoomFrame")
        if data.size() == 96 * 72 * 3:
            var image := Image.create_from_data(96, 72, false, Image.FORMAT_RGB8, data)
            if room: room.update(image)
            else: room = ImageTexture.create_from_image(image)
            stale = 0
    for material in materials:
        material.set_shader_parameter("has_room", room != null and stale < 0.7 and reader.passthrough_enabled)
        if room: material.set_shader_parameter("room_texture", room)
