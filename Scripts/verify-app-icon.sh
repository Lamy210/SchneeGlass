#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ICON_PACKAGE="App/AppIcon.icon"
ARTWORK="$ICON_PACKAGE/Assets/Artwork.svg"
SOURCE="assets/icon.svg"
METADATA="$ICON_PACKAGE/icon.json"

fail() {
  echo "App icon validation failed: $*" >&2
  exit 1
}

[[ -f "$ARTWORK" ]] || fail "missing $ARTWORK"
[[ -f "$SOURCE" ]] || fail "missing $SOURCE"
[[ -f "$METADATA" ]] || fail "missing $METADATA"

cmp -s "$SOURCE" "$ARTWORK" || fail "$SOURCE and $ARTWORK must stay byte-identical"

python3 - "$ARTWORK" "$METADATA" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

artwork_path = Path(sys.argv[1])
metadata_path = Path(sys.argv[2])


def fail(message: str) -> None:
    print(f"App icon validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


root = ET.parse(artwork_path).getroot()
view_box = root.attrib.get("viewBox", "").replace(",", " ").split()
if view_box != ["0", "0", "1024", "1024"]:
    fail(f"Artwork.svg viewBox must be '0 0 1024 1024', got {root.attrib.get('viewBox')!r}")

for dimension in ("width", "height"):
    value = root.attrib.get(dimension, "").removesuffix("px")
    if value != "1024":
        fail(f"Artwork.svg {dimension} must be 1024, got {root.attrib.get(dimension)!r}")

namespace = "{http://www.w3.org/2000/svg}"
for rect in root.iter(f"{namespace}rect"):
    x = rect.attrib.get("x", "0")
    y = rect.attrib.get("y", "0")
    width = rect.attrib.get("width")
    height = rect.attrib.get("height")
    if x in {"0", "0.0"} and y in {"0", "0.0"} and width == "1024" and height == "1024":
        fail("Artwork.svg must not contain a full-canvas background or pre-applied canvas mask")

try:
    metadata = json.loads(metadata_path.read_text())
except (OSError, json.JSONDecodeError) as error:
    fail(f"cannot parse {metadata_path}: {error}")

solid_fill = metadata.get("fill", {}).get("solid")
if not isinstance(solid_fill, str) or not solid_fill:
    fail("Icon Composer metadata must own the icon background fill")

image_names = [
    layer.get("image-name")
    for group in metadata.get("groups", [])
    for layer in group.get("layers", [])
]
if image_names != ["Artwork.svg"]:
    fail(f"Icon Composer package must reference exactly Artwork.svg, got {image_names!r}")

print("App icon package OK: 1024x1024 unmasked artwork, Icon Composer-owned background")
PY
