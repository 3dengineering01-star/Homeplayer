"""Pictures of the OwnMedia site, made from the app icon (docs/play/icon-512.png).

Writes into site-src/static/img/: the logo, the favicon, the Apple touch icon and the link preview
(Open Graph). The screenshots in site-src/static/img/screens/ are real ones from the phone, taken
on a demo server with free content (see site/README.md); this script does not touch them.

    python site-src/make_images.py

Needs Pillow. Run once, or again after the icon changes; then python site-src/build.py.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "docs" / "play" / "icon-512.png"
OUT = Path(__file__).resolve().parent / "static" / "img"
FONTS = Path("C:/Windows/Fonts")

ORANGE = (255, 138, 31)
CYAN = (46, 226, 236)
INK = (11, 13, 18)


def font(size, bold=False):
    for name in (("segoeuib.ttf", "DejaVuSans-Bold.ttf") if bold else ("segoeui.ttf", "DejaVuSans.ttf")):
        for folder in (FONTS, Path("/usr/share/fonts/truetype/dejavu")):
            if (folder / name).exists():
                return ImageFont.truetype(str(folder / name), size)
    return ImageFont.load_default(size)


def rounded(img, radius):
    """The image with rounded corners, on transparency."""
    img = img.convert("RGBA")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    img.putalpha(mask)
    return img


def glow_background(size, spots):
    """A dark background with soft coloured light: spots are (x, y, radius, colour, strength)."""
    w, h = size
    bg = Image.new("RGB", size, INK)
    light = Image.new("RGB", size, (0, 0, 0))
    d = ImageDraw.Draw(light)
    for x, y, r, colour, k in spots:
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(c * k) for c in colour))
    light = light.filter(ImageFilter.GaussianBlur(max(w, h) // 8))
    return Image.blend(bg, light, 1.0).point(lambda v: min(255, v + 8))


def make_icons(icon):
    rr = rounded(icon, 112)  # the same shape as Android's launcher icon
    for px in (64, 128):
        rr.resize((px, px), Image.LANCZOS).save(OUT / f"logo-{px}.webp", quality=90, method=6)
    rr.resize((32, 32), Image.LANCZOS).save(OUT / "favicon-32.png", optimize=True)
    rr.resize((48, 48), Image.LANCZOS).save(OUT.parent / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    # Apple draws its own corners: the touch icon is square.
    icon.resize((180, 180), Image.LANCZOS).save(OUT / "apple-touch-icon.png", optimize=True)


def make_preview(icon):
    w, h = 1200, 630
    img = glow_background((w, h), [(220, 120, 360, ORANGE, 0.55), (1100, 600, 420, CYAN, 0.45),
                                   (700, -80, 300, (120, 80, 255), 0.35)])
    d = ImageDraw.Draw(img, "RGBA")
    # A glass panel behind the text.
    d.rounded_rectangle((60, 95, w - 60, h - 95), 48, fill=(255, 255, 255, 18), outline=(255, 255, 255, 60), width=2)
    logo = rounded(icon, 112).resize((300, 300), Image.LANCZOS)
    img.paste(logo, (120, (h - 300) // 2), logo)
    x = 480
    d.text((x, 168), "OwnMedia", font=font(104, True), fill=(245, 247, 250))
    d.text((x, 310), "Movies, music and photos", font=font(42), fill=(222, 228, 236))
    d.text((x, 362), "from your own server", font=font(42), fill=(222, 228, 236))
    d.text((x, 438), "Jellyfin  ·  Navidrome  ·  Android", font=font(30), fill=(255, 178, 107))
    img.save(OUT / "og-image.jpg", quality=86, optimize=True, progressive=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icon = Image.open(ICON).convert("RGB")
    make_icons(icon)
    make_preview(icon)
    for p in sorted(OUT.parent.rglob("*")):
        if p.is_file() and p.suffix in {".webp", ".png", ".jpg", ".ico"}:
            print(f"{p.relative_to(OUT.parent)}  {p.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
