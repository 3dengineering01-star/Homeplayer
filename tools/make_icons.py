"""Makes the app's icons from the artwork in docs/brand/ownmedia-icon-source.jpg.

The artwork is a dark rounded tile on black. Out of it come:
- Android adaptive icon: the picture as the foreground layer, a flat dark background, and a
  one-colour version for themed icons (Android 13+);
- Android icons for old phones (rounded tile), Google Play's 512 px icon, the installer's .ico.

Run from the repository root: python3 tools/make_icons.py (needs Pillow and NumPy).
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'docs/brand/ownmedia-icon-source.jpg'
RES = ROOT / 'app/android/app/src/main/res'

# Where the tile and the picture on it are in the artwork (pixels).
TILE_LEFT, TILE_RIGHT = 58, 724
GLYPH_CENTER_Y = 563

# The adaptive icon's layer is 108 dp; launchers show the middle 72 dp, and a round icon keeps
# the middle 66 dp. The picture is a disc 510 px across with its glow: in a 900 px layer it
# fits that circle with room to spare.
LAYER = 900

DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def rounded_mask(size: int, radius: float, feather: float = 0) -> Image.Image:
    mask = Image.new('L', (size, size), 0)
    inset = feather
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, size - 1 - inset, size - 1 - inset), radius, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(feather / 2)) if feather else mask


def main() -> None:
    art = Image.open(SOURCE).convert('RGB')
    side = TILE_RIGHT - TILE_LEFT
    top = GLYPH_CENTER_Y - side // 2
    square = art.crop((TILE_LEFT, top, TILE_LEFT + side, top + side))

    # The tile's own colour, from its plain parts near the edges.
    a = np.asarray(square).reshape(-1, 3)
    plain = a[(a.max(1) - a.min(1) < 20) & (a.max(1) > 12) & (a.max(1) < 45)]
    background = tuple(int(v) for v in np.median(plain, 0))

    # Adaptive icon: the picture on a flat background, its edges faded into it.
    fade = rounded_mask(side, side * 0.3, feather=50)
    layer = Image.new('RGBA', (LAYER, LAYER), background + (0,))
    piece = square.convert('RGBA')
    piece.putalpha(fade)
    offset = (LAYER - side) // 2
    layer.alpha_composite(piece, (offset, offset))

    # Themed icons: the bright, coloured parts as one shape.
    rgb = np.asarray(layer.convert('RGB')).astype(float)
    saturation = rgb.max(2) - rgb.min(2)
    alpha = np.clip((saturation - 70) / 50, 0, 1) * np.asarray(layer.getchannel('A')) / 255
    shape = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))
    mono = Image.new('RGBA', (LAYER, LAYER), (255, 255, 255, 0))
    mono.putalpha(shape)

    flat = Image.new('RGB', (LAYER, LAYER), background)
    flat.paste(layer, (0, 0), layer)

    # The tile as in the artwork: the picture with the same margin around it.
    cut = (LAYER - side) // 2
    window = (cut, cut, cut + side, cut + side)

    for name, scale in DENSITIES.items():
        folder = RES / f'mipmap-{name}'
        folder.mkdir(exist_ok=True)
        px = round(108 * scale)
        layer.resize((px, px), Image.LANCZOS).save(folder / 'ic_launcher_foreground.png', optimize=True)
        mono.resize((px, px), Image.LANCZOS).save(folder / 'ic_launcher_monochrome.png', optimize=True)
        # Old phones (before Android 8): the rounded tile itself.
        legacy = round(48 * scale)
        tile = flat.crop(window).resize((legacy, legacy), Image.LANCZOS)
        tile = tile.convert('RGBA')
        tile.putalpha(rounded_mask(legacy, legacy * 0.22).resize((legacy, legacy)))
        tile.save(folder / 'ic_launcher.png', optimize=True)

    (RES / 'values/ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">#{background[0]:02X}{background[1]:02X}{background[2]:02X}</color>\n'
        '</resources>\n', newline='\n')

    # Google Play: a full square, Play rounds the corners itself.
    flat.crop(window).resize((512, 512), Image.LANCZOS).save(ROOT / 'docs/play/icon-512.png', optimize=True)

    # Windows installer and its Start menu link: the rounded tile.
    big = flat.crop(window).resize((256, 256), Image.LANCZOS).convert('RGBA')
    big.putalpha(rounded_mask(256, 256 * 0.22))
    big.save(ROOT / 'installer/homeplay.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    print('background', background)


if __name__ == '__main__':
    main()
