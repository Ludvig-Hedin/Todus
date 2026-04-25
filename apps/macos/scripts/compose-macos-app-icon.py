#!/usr/bin/env python3
"""
Build macOS AppIcon assets from the iOS 1024 master.

The iOS file is a full white square; the mark sits in the middle. Crop to the ink bounds,
scale that crop, then paste it onto a clean opaque white canvas. Keeping the canvas opaque
prevents macOS/Dock backing gradients from showing through the logo counter or corners.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
    import numpy as np
except ImportError as e:
    print("error: need Pillow and numpy: pip install pillow numpy", file=sys.stderr)
    raise e

# How much of 1024 the longest side of the ink crop should use.
FILL = 0.95
# Treat near-white pixels as background when finding the mark bounds.
WHITE_MIN = 250


def bbox_nonwhite(rgb: np.ndarray) -> tuple[int, int, int, int] | None:
    nonwhite = np.any(rgb < WHITE_MIN, axis=2)
    ys, xs = np.where(nonwhite)
    if len(xs) == 0:
        return None
    t, b, l, r = ys.min(), ys.max(), xs.min(), xs.max()
    return l, t, r, b


def compose(source: Path, out1024: Path, fill: float) -> None:
    rgb = np.array(Image.open(source).convert("RGB"), dtype=np.uint8)
    h, w = rgb.shape[0], rgb.shape[1]
    if h != 1024 or w != 1024:
        print(f"warning: expected 1024^2, got {w}x{h}", file=sys.stderr)
    bb = bbox_nonwhite(rgb)
    if bb is None:
        raise SystemExit("no logo content in source icon (check WHITE_MIN)")
    l, t, r, b = bb
    pad = 6
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(w - 1, r + pad)
    b = min(h - 1, b + pad)
    crop = rgb[t : b + 1, l : r + 1, :]
    ch, cw = crop.shape[0], crop.shape[1]
    target = int(1024 * fill)
    scale = target / max(cw, ch)
    nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    im = Image.fromarray(crop)
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGB", (1024, 1024), (255, 255, 255))
    x0 = (1024 - nw) // 2
    y0 = (1024 - nh) // 2
    out.paste(im, (x0, y0))
    out1024.parent.mkdir(parents=True, exist_ok=True)
    out.save(out1024, "PNG")


def sips_to_size(src: Path, size: int, out: Path) -> None:
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(src), "--out", str(out)],
        check=True,
        capture_output=True,
    )


def write_contents_json(out_dir: Path) -> None:
    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_64x64.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_1024x1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    out = json.dumps(contents, indent=2).replace("\n    {", "\n    {")
    out = out.replace('"images":', '"images" :').replace('"info":', '"info" :')
    out = out.replace('"filename":', '"filename" :')
    out = out.replace('"idiom":', '"idiom" :')
    out = out.replace('"scale":', '"scale" :')
    out = out.replace('"size":', '"size" :')
    out = out.replace('"author":', '"author" :')
    out = out.replace('"version":', '"version" :')
    (out_dir / "Contents.json").write_text(out + "\n")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    ios = root.parent / "ios" / "Todus" / "Todus" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "App-Icon-1024x1024@1x.png"
    if not ios.exists():
        ios = Path(
            "/Users/ludvighedin/Programming/personal/mail/apps/ios/Todus/Todus/Resources/Assets.xcassets/AppIcon.appiconset/App-Icon-1024x1024@1x.png"
        )
    if not ios.exists():
        print("error: iOS source icon not found", file=sys.stderr)
        sys.exit(1)

    script_dir = Path(__file__).resolve().parent
    out_dir = root / "TodusMac" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    master = script_dir / "AppIcon-macos-master.png"
    print(f"composing {master} from {ios} (fill={FILL}, opaque white background)")
    compose(ios, master, FILL)
    for stale in out_dir.glob("mac_*.png"):
        stale.unlink()
        print("removed stale", stale)

    for sz, name in [
        (16, "icon_16x16.png"),
        (32, "icon_32x32.png"),
        (64, "icon_64x64.png"),
        (128, "icon_128x128.png"),
        (256, "icon_256x256.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_1024x1024.png"),
    ]:
        sips_to_size(master, sz, out_dir / name)
        print("wrote", out_dir / name)
    write_contents_json(out_dir)
    print("wrote", out_dir / "Contents.json")


if __name__ == "__main__":
    main()
