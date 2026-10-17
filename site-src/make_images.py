"""Pictures of the OwnMedia site, made from the app icon (docs/play/icon-512.png).

Writes into site-src/static/img/: the logo, the favicon, the Apple touch icon, the link preview
(Open Graph) and placeholder screenshots in site-src/static/img/screens/. The placeholders are
drawn shapes, not real screenshots: replace them with real ones of the same name and size
(600 x 1300, WebP) when there are screenshots without personal data.

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


# Placeholder screenshots ---------------------------------------------------------------------

SW, SH = 600, 1300


def screen_base(top, bottom):
    img = Image.new("RGB", (SW, SH))
    d = ImageDraw.Draw(img)
    for y in range(SH):
        t = y / SH
        d.line([(0, y), (SW, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def glass(d, box, r=28, a=34):
    d.rounded_rectangle(box, r, fill=(255, 255, 255, a), outline=(255, 255, 255, 70), width=2)


def bar(d, x, y, w, h=18, a=110):
    d.rounded_rectangle((x, y, x + w, y + h), h // 2, fill=(255, 255, 255, a))


def header(d, title):
    # Status bar and the screen's title.
    bar(d, 40, 34, 70, 14, 150)
    for i in range(3):
        d.ellipse((480 + i * 28, 34, 494 + i * 28, 48), fill=(255, 255, 255, 150))
    d.text((40, 96), title, font=font(46, True), fill=(255, 255, 255, 235))


def footer_note(d):
    note = "Screenshot coming soon"
    f = font(26)
    w = d.textlength(note, font=f)
    d.rounded_rectangle(((SW - w) / 2 - 22, SH - 104, (SW + w) / 2 + 22, SH - 56), 24, fill=(0, 0, 0, 90))
    d.text(((SW - w) / 2, SH - 98), note, font=f, fill=(255, 255, 255, 220))


def screen_servers(d):
    header(d, "Good evening")
    for i, (c1, y) in enumerate([((255, 138, 31), 200), ((46, 200, 220), 520)]):
        d.rounded_rectangle((40, y, SW - 40, y + 280), 36, fill=c1 + (150,), outline=(255, 255, 255, 90), width=2)
        d.ellipse((76, y + 40, 156, y + 120), fill=(255, 255, 255, 120))
        bar(d, 76, y + 160, 260, 26, 200)
        bar(d, 76, y + 204, 170, 18, 140)
        d.ellipse((SW - 110, y + 44, SW - 84, y + 70), fill=(125, 220, 154, 255))
    glass(d, (40, 850, SW - 40, 1000))
    bar(d, 76, 900, 300, 22, 140)
    bar(d, 76, 940, 200, 16, 100)


def screen_library(d):
    header(d, "Movies")
    for chip in range(3):
        glass(d, (40 + chip * 150, 176, 170 + chip * 150, 226), 25)
    cw, ch, gap = 160, 236, 20
    for row in range(4):
        for col in range(3):
            x = 40 + col * (cw + gap)
            y = 260 + row * (ch + 58)
            hue = [(255, 138, 31), (46, 200, 220), (150, 110, 255), (255, 90, 120)][(row + col) % 4]
            d.rounded_rectangle((x, y, x + cw, y + ch), 18, fill=hue + (120,), outline=(255, 255, 255, 60), width=2)
            bar(d, x, y + ch + 14, cw - 40, 14, 120)


def screen_player(d):
    d.rectangle((0, 0, SW, SH), fill=(0, 0, 0, 120))
    d.rounded_rectangle((0, 300, SW, 640), 0, fill=(20, 24, 34, 255))
    d.polygon([(270, 420), (270, 520), (350, 470)], fill=(255, 255, 255, 200))
    bar(d, 40, 680, SW - 80, 8, 90)
    bar(d, 40, 680, 300, 8, 255)
    glass(d, (20, 760, SW - 20, SH - 140), 36, 48)
    d.text((60, 790), "Audio", font=font(34, True), fill=(255, 255, 255, 230))
    for i in range(4):
        y = 860 + i * 78
        d.ellipse((60, y, 92, y + 32), outline=(255, 255, 255, 160), width=3)
        if i == 0:
            d.ellipse((68, y + 8, 84, y + 24), fill=(255, 138, 31, 255))
        bar(d, 116, y + 2, 260 - i * 30, 18, 170)
        bar(d, 116, y + 30, 160, 12, 90)


def screen_music(d):
    header(d, "Now playing")
    d.rounded_rectangle((70, 200, SW - 70, 660), 40, fill=(255, 138, 31, 170), outline=(255, 255, 255, 90), width=2)
    d.ellipse((200, 330, 400, 530), outline=(255, 255, 255, 140), width=10)
    bar(d, 70, 720, 320, 30, 220)
    bar(d, 70, 768, 200, 20, 140)
    bar(d, 70, 840, SW - 140, 8, 90)
    bar(d, 70, 840, 250, 8, 255)
    cx = SW // 2
    d.ellipse((cx - 56, 920, cx + 56, 1032), fill=(255, 255, 255, 230))
    d.polygon([(cx - 14, 950), (cx - 14, 1002), (cx + 26, 976)], fill=(40, 30, 20, 255))
    for dx in (-170, 170):
        d.ellipse((cx + dx - 34, 942, cx + dx + 34, 1010), fill=(255, 255, 255, 70))


def screen_photos(d):
    header(d, "Photos")
    s, gap = 122, 10
    for row in range(7):
        for col in range(4):
            x = 40 + col * (s + gap)
            y = 190 + row * (s + gap)
            hue = [(46, 200, 220), (255, 160, 80), (130, 200, 120), (150, 120, 255)][(row * 3 + col) % 4]
            d.rounded_rectangle((x, y, x + s, y + s), 10, fill=hue + (110 + (row * col) % 3 * 30,))


def screen_share(d):
    header(d, "Share with friends")
    glass(d, (40, 190, SW - 40, 560))
    d.text((76, 220), "Libraries", font=font(30, True), fill=(255, 255, 255, 220))
    for i in range(4):
        y = 290 + i * 64
        bar(d, 76, y + 8, 220 - i * 20, 18, 160)
        on = i < 3
        d.rounded_rectangle((SW - 150, y, SW - 76, y + 38), 19, fill=(255, 138, 31, 230) if on else (255, 255, 255, 60))
        kx = SW - 114 if on else SW - 150
        d.ellipse((kx + 4, y + 4, kx + 34, y + 34), fill=(255, 255, 255, 255))
    # The invite link and the button that sends it.
    glass(d, (40, 600, SW - 40, 800))
    d.text((76, 628), "Invite link", font=font(30, True), fill=(255, 255, 255, 220))
    d.rounded_rectangle((76, 690, SW - 76, 750), 16, fill=(0, 0, 0, 70))
    bar(d, 100, 711, 330, 18, 150)
    d.rounded_rectangle((40, 830, SW - 40, 910), 40, fill=(255, 138, 31, 240))
    bar(d, 210, 860, 180, 20, 230)
    # Who has access.
    glass(d, (40, 950, SW - 40, 1150))
    for i in range(2):
        y = 985 + i * 80
        d.ellipse((76, y, 128, y + 52), fill=(255, 255, 255, 110))
        bar(d, 150, y + 6, 200, 18, 170)
        bar(d, 150, y + 34, 140, 12, 100)


SCREENS = [
    ("servers", (60, 34, 20), (14, 30, 46), screen_servers),
    ("library", (24, 30, 52), (12, 14, 24), screen_library),
    ("player", (10, 12, 18), (24, 20, 40), screen_player),
    ("music", (90, 46, 18), (20, 14, 30), screen_music),
    ("photos", (14, 44, 54), (14, 16, 30), screen_photos),
    ("share", (40, 24, 60), (12, 30, 44), screen_share),
]


def make_screens():
    folder = OUT / "screens"
    folder.mkdir(parents=True, exist_ok=True)
    for name, top, bottom, draw in SCREENS:
        img = screen_base(top, bottom).convert("RGBA")
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        draw(d)
        footer_note(d)
        img = Image.alpha_composite(img, layer).convert("RGB")
        img.save(folder / f"{name}.webp", quality=78, method=6)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    icon = Image.open(ICON).convert("RGB")
    make_icons(icon)
    make_preview(icon)
    make_screens()
    for p in sorted(OUT.parent.rglob("*")):
        if p.is_file() and p.suffix in {".webp", ".png", ".jpg", ".ico"}:
            print(f"{p.relative_to(OUT.parent)}  {p.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
