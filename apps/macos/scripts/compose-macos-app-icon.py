#!/usr/bin/env python3
"""
Resize the iOS 1024 master so the Todus mark nearly fills the macOS icon canvas.

The iOS app icon is authored with a large "safe" margin. macOS then composites that
full asset onto the Dock tile, which can look like a small white card floating over
the system plate. This script scales the logo to ~FILL RATIO of 1024 and regenerates
all AppIcon.appiconset PNGs (plus a master reference PNG).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as e:
    print("error: install Pillow: pip install pillow", file=sys.stderr)
    raise e

# Share of 1024 used by the (cropped) logo on its longest side (HIG-typical ~80–90%).
FILL = 0.86
WHITE_THRESHOLD = 250
PAD = 6


def is_not_white(p: tuple[int, int, int]) -> bool:
    return p[0] < WHITE_THRESHOLD or p[1] < WHITE_THRESHOLD or p[2] < WHITE_THRESHOLD


def tight_bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
    w, h = im.size
    xs: list[int] = []
    ys: list[int] = []
    px = im.load()
    for y in range(h):
        for x in range(w):
            if is_not_white(px[x, y]):  # type: ignore[index]
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    l, t, r, b = min(xs), min(ys), max(xs), max(ys)
    l = max(0, l - PAD)
    t = max(0, t - PAD)
    r = min(w - 1, r + PAD)
    b = min(h - 1, b + PAD)
    return l, t, r, b


def compose(source: Path, out1024: Path, fill: float) -> None:
    im = Image.open(source).convert("RGB")
    w, h = im.size
    if w != 1024 or h != 1024:
        print(f"warning: expected 1024^2, got {w}x{h}", file=sys.stderr)
    b = tight_bbox(im)
    if b is None:
        raise SystemExit("no non-white content in source icon")
    l, t, r, b = b
    crop = im.crop((l, t, r + 1, b + 1))
    cw, ch = crop.size
    target = int(1024 * fill)
    scale = target / max(cw, ch)
    nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    scaled = crop.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGB", (1024, 1024), (255, 255, 255))
    x0 = (1024 - nw) // 2
    y0 = (1024 - nh) // 2
    out.paste(scaled, (x0, y0))
    out1024.parent.mkdir(parents=True, exist_ok=True)
    out.save(out1024, "PNG")


def sips_resize(src: Path, size: int, out: Path) -> None:
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(src), "--out", str(out)],
        check=True,
        capture_output=True,
    )


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
    # Keep the 1024 reference next to the script so it is not copied into the app bundle.
    master = script_dir / "AppIcon-macos-master.png"
    print(f"composing {master} from {ios} (fill={FILL})")
    compose(ios, master, FILL)

    for sz, name in [
        (16, "icon_16x16.png"),
        (32, "icon_32x32.png"),
        (64, "icon_64x64.png"),
        (128, "icon_128x128.png"),
        (256, "icon_256x256.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_1024x1024.png"),
    ]:
        sips_resize(master, sz, out_dir / name)
        print("wrote", out_dir / name)


if __name__ == "__main__":
    main()
