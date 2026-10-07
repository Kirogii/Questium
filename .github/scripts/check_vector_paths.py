"""Reject vector paths that AAPT silently replaces with STRING_TOO_LARGE."""

from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
attribute = "{http://schemas.android.com/apk/res/android}pathData"
count = 0
for file in (root / "app/src").glob("*/res/drawable*/*.xml"):
    for element in ET.parse(file).iter():
        path = element.get(attribute)
        if path is None:
            continue
        count += 1
        size = len(path.encode("utf-8"))
        if size >= 32767 or "STRING_TOO_LARGE" in path:
            raise SystemExit(f"{file.relative_to(root)}: invalid vector path ({size} bytes)")
print(f"PASS: {count} vector paths fit Android resource string limits")
