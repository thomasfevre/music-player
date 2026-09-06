#!/usr/bin/env python3
"""Compose App Store-ready screenshots from raw iPhone Simulator captures."""

from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "marketing" / "app-store" / "1.2" / "raw"
OUTPUT = ROOT / "marketing" / "app-store" / "1.2" / "final"
SCREEN_MASK = ROOT / "marketing" / "app-store" / "1.2" / "assets" / "iphone-17-pro-max-screen-mask.png"
WIDTH, HEIGHT = 1320, 2868
FONT = "/System/Library/Fonts/SFNS.ttf"


SCREENS = [
    {
        "file": "01-library.png",
        "source": "library.png",
        "title": "Your music.\nYour rules.",
        "subtitle": "A private, offline library built around how you listen.",
        "colors": ((24, 13, 45), (9, 20, 42), (45, 18, 75)),
    },
    {
        "file": "02-auto-dj.png",
        "source": "now-playing.png",
        "title": "Let Auto-DJ\nkeep it moving.",
        "subtitle": "A queue shaped by your library and listening signals.",
        "colors": ((10, 38, 49), (29, 15, 47), (58, 18, 66)),
    },
    {
        "file": "03-listening-stats.png",
        "source": "stats.png",
        "title": "See what you\nactually play.",
        "subtitle": "Plays, listening time and skips, stored on your iPhone.",
        "colors": ((23, 18, 52), (13, 27, 49), (56, 20, 63)),
    },
    {
        "file": "04-add-tracks.png",
        "source": "add-tracks.png",
        "title": "Build playlists\nwithout the busywork.",
        "subtitle": "Scroll your library and select every track in one pass.",
        "colors": ((48, 10, 50), (15, 22, 42), (70, 17, 64)),
    },
    {
        "file": "05-playlists.png",
        "source": "playlist.png",
        "title": "Every playlist,\nready to evolve.",
        "subtitle": "Rename it, customize it and keep adding music.",
        "colors": ((22, 17, 47), (10, 25, 40), (55, 14, 70)),
    },
    {
        "file": "06-settings.png",
        "source": "settings.png",
        "title": "Make the player\nfeel like yours.",
        "subtitle": "Stats covers, unique colors, listening badges and crossfade.",
        "colors": ((20, 20, 45), (10, 28, 44), (49, 16, 63)),
    },
]


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(FONT, size=size)
    face.set_variation_by_name(weight)
    return face


def gradient(colors: tuple[tuple[int, int, int], ...]) -> Image.Image:
    top, bottom, glow = colors
    canvas = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = canvas.load()
    for y in range(HEIGHT):
        t = y / max(1, HEIGHT - 1)
        for x in range(WIDTH):
            radial = max(0.0, 1.0 - (((x - WIDTH * 0.72) / 800) ** 2 + ((y - 430) / 720) ** 2))
            base = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
            pixels[x, y] = tuple(min(255, int(base[i] + glow[i] * radial * 0.42)) for i in range(3))
    return canvas


def rounded_screen(source_path: Path, target_width: int) -> Image.Image:
    source = Image.open(source_path).convert("RGB")
    target_height = round(source.height * target_width / source.width)
    source = source.resize((target_width, target_height), Image.Resampling.LANCZOS)
    mask = Image.open(SCREEN_MASK).convert("L").resize(source.size, Image.Resampling.LANCZOS)
    result = Image.new("RGBA", source.size)
    result.paste(source, (0, 0), mask)
    return result


def iphone_mockup(source_path: Path) -> Image.Image:
    """Render a reusable, straight-on titanium iPhone around a simulator capture."""
    screen_width = 994
    inset = 22
    rail = 9
    screen = rounded_screen(source_path, screen_width)
    phone_width = screen.width + (inset + rail) * 2
    phone_height = screen.height + (inset + rail) * 2

    # Extra transparent space keeps the side controls and their shadows visible.
    device = Image.new("RGBA", (phone_width + 44, phone_height + 20), (0, 0, 0, 0))
    x = 22
    y = 0
    screen_x = x + inset + rail
    screen_y = y + inset + rail

    # The simulator-provided alpha mask is the source of truth for Apple's
    # continuous corner geometry. Dilating it produces perfectly parallel rails.
    screen_mask = Image.open(SCREEN_MASK).convert("L").resize(screen.size, Image.Resampling.LANCZOS)
    body_mask = Image.new("L", device.size, 0)
    body_mask.paste(screen_mask, (screen_x, screen_y))
    outer_mask = body_mask.filter(ImageFilter.MaxFilter((inset + rail) * 2 + 1))
    inner_rail_mask = body_mask.filter(ImageFilter.MaxFilter(inset * 2 + 1))

    shadow = Image.new("RGBA", device.size, (0, 0, 0, 0))
    shifted_shadow = Image.new("L", device.size, 0)
    shifted_shadow.paste(outer_mask, (0, 12))
    shadow.putalpha(shifted_shadow.filter(ImageFilter.GaussianBlur(22)))
    device.alpha_composite(shadow)

    draw = ImageDraw.Draw(device)

    titanium = Image.new("RGBA", device.size, (75, 76, 82, 255))
    titanium.putalpha(outer_mask)
    device.alpha_composite(titanium)
    inner_rail = Image.new("RGBA", device.size, (29, 29, 33, 255))
    inner_rail.putalpha(inner_rail_mask)
    device.alpha_composite(inner_rail)
    bezel = Image.new("RGBA", device.size, (3, 3, 4, 255))
    bezel.putalpha(body_mask.filter(ImageFilter.MaxFilter(rail * 2 + 1)))
    device.alpha_composite(bezel)

    # Subtle highlights on the outer titanium edge.
    highlight_mask = ImageChops.subtract(outer_mask, inner_rail_mask)
    highlight = Image.new("RGBA", device.size, (190, 191, 198, 180))
    highlight.putalpha(highlight_mask)
    device.alpha_composite(highlight)

    # Physical controls. They sit outside the body just like a product mockup.
    button_fill = (72, 73, 79, 255)
    button_edge = (133, 134, 140, 220)
    for box in (
        (x - 7, 285, x + 3, 390),
        (x - 8, 430, x + 3, 625),
        (x - 8, 665, x + 3, 860),
        (x + phone_width - 3, 480, x + phone_width + 8, 790),
    ):
        draw.rounded_rectangle(box, radius=5, fill=button_fill, outline=button_edge, width=2)

    device.alpha_composite(screen, (screen_x, screen_y))

    # Camera/sensor cutout. The source remains unobstructed below the status bar.
    island_width, island_height = 232, 66
    island_x = screen_x + (screen.width - island_width) // 2
    island_y = screen_y + 23
    draw.rounded_rectangle(
        (island_x, island_y, island_x + island_width, island_y + island_height),
        radius=island_height // 2,
        fill=(0, 0, 0, 255),
    )
    draw.ellipse(
        (island_x + island_width - 48, island_y + 20, island_x + island_width - 26, island_y + 42),
        fill=(12, 17, 28, 255),
    )
    draw.ellipse(
        (island_x + island_width - 43, island_y + 25, island_x + island_width - 33, island_y + 35),
        fill=(30, 46, 69, 230),
    )
    return device


def draw_wrapped(draw: ImageDraw.ImageDraw, text: str, y: int, typeface, fill, spacing: int) -> int:
    for line in text.splitlines():
        draw.text((96, y), line, font=typeface, fill=fill)
        box = draw.textbbox((96, y), line, font=typeface)
        y = box[3] + spacing
    return y


def compose(screen: dict) -> None:
    canvas = gradient(screen["colors"]).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    pill_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    pill_draw = ImageDraw.Draw(pill_layer)
    pill_draw.rounded_rectangle((96, 76, 405, 132), radius=28, fill=(255, 255, 255, 34))
    canvas.alpha_composite(pill_layer)
    draw = ImageDraw.Draw(canvas)
    draw.text((120, 88), "LOCAL MUSIC PLAYER", font=font(25, "Semibold"), fill=(255, 255, 255, 215))

    title_bottom = draw_wrapped(draw, screen["title"], 176, font(104, "Bold"), (255, 255, 255, 255), 4)
    draw.text((100, title_bottom + 20), screen["subtitle"], font=font(39, "Medium"), fill=(235, 232, 244, 220))

    phone = iphone_mockup(RAW / screen["source"])
    phone_x, phone_y = (WIDTH - phone.width) // 2, 630
    canvas.alpha_composite(phone, (phone_x, phone_y))

    OUTPUT.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT / screen["file"], quality=96)


if __name__ == "__main__":
    for item in SCREENS:
        compose(item)
    print(f"Generated {len(SCREENS)} screenshots in {OUTPUT}")
