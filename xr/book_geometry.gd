extends RefCounted

static func cover(size: Vector3) -> ArrayMesh:
    var mesh := SurfaceTool.new()
    mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
    var rings: Array[PackedVector3Array] = []
    for index in range(4):
        var ring := PackedVector3Array()
        var inset := minf(0.0002, size.z * 0.2) if index == 0 or index == 3 else 0.0
        var half := Vector2(size.x, size.y) * 0.5 - Vector2.ONE * inset
        var radius := minf(0.0025, minf(half.x, half.y) * 0.45)
        var z := (-1.0 if index < 2 else 1.0) * (size.z * 0.5 - inset)
        for corner in range(4):
            var center := Vector2((1.0 if corner < 2 else -1.0) * (half.x - radius), (1.0 if corner == 0 or corner == 3 else -1.0) * (half.y - radius))
            for step in range(7):
                var angle := PI * 0.5 - corner * PI * 0.5 - step * PI / 12.0
                var xy := center + Vector2(cos(angle), sin(angle)) * radius
                ring.append(Vector3(xy.x, xy.y, z))
        rings.append(ring)
    for ring in range(3):
        for i in range(rings[ring].size()):
            var next := (i + 1) % rings[ring].size()
            for v in [rings[ring][i], rings[ring + 1][i], rings[ring + 1][next], rings[ring][i], rings[ring + 1][next], rings[ring][next]]:
                mesh.add_vertex(v)
    for ring in [0, 3]:
        for i in range(rings[ring].size()):
            var next := (i + 1) % rings[ring].size()
            var vertices := [Vector3(0, 0, rings[ring][i].z), rings[ring][i], rings[ring][next]]
            if ring == 0:
                vertices.reverse()
            for v in vertices:
                mesh.add_vertex(v)
    mesh.generate_normals()
    return mesh.commit()

# Top follows the resting leaf with clearance below its printed surface.
static func stack(side: int, width: float, height: float, rest_angle: float = 0.035, thickness: float = 0.0016) -> ArrayMesh:
    var mesh := SurfaceTool.new()
    mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
    for section in range(64):
        for face in range(4):
            var points: Array[Vector3] = []
            for u in [float(section) / 64, float(section + 1) / 64]:
                var x: float = side * (u * width * cos(rest_angle) - sin(rest_angle) * 0.002 * sin(u * PI))
                var z: float = u * width * sin(rest_angle) + sin(rest_angle) * 0.002 * sin(u * PI) - 0.0005
                if face < 2:
                    for y in [-height / 2, height / 2]:
                        points.append(Vector3(x, y, z - face * thickness))
                else:
                    for depth in [0.0, thickness]:
                        points.append(Vector3(x, (-1 if face == 2 else 1) * height / 2, z - depth))
            for i in [0, 1, 2, 2, 1, 3]:
                mesh.set_uv(Vector2(points[i].x / width, points[i].z / thickness))
                mesh.add_vertex(points[i])
    var x := side * width * cos(rest_angle)
    var z := width * sin(rest_angle) - 0.0005
    for v in [Vector3(x, -height / 2, z), Vector3(x, height / 2, z), Vector3(x, -height / 2, z - thickness), Vector3(x, -height / 2, z - thickness), Vector3(x, height / 2, z), Vector3(x, height / 2, z - thickness)]:
        mesh.set_uv(Vector2(v.y / height, v.z / thickness))
        mesh.add_vertex(v)
    mesh.generate_normals()
    return mesh.commit()
