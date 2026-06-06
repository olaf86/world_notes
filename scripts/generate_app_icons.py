from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
IOS_ICON_DIR = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES_DIR = ROOT / "android/app/src/main/res"
MASTER_PATH = ROOT / "assets/images/app_icon_1024.png"

SCALE = 4
CANVAS = 1024


def c(value: str) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def sc(value: float) -> int:
    return int(round(value * SCALE))


def rounded_rectangle(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float, float, float],
    radius: float,
    fill: tuple[int, int, int, int],
) -> None:
    draw.rounded_rectangle(tuple(sc(v) for v in xy), radius=sc(radius), fill=fill)


def line(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    fill: tuple[int, int, int, int],
    width: float,
    opacity: float = 1,
) -> None:
    rgba = (*fill[:3], int(255 * opacity))
    scaled_points = [(sc(x), sc(y)) for x, y in points]
    draw.line(scaled_points, fill=rgba, width=sc(width), joint="curve")
    radius = sc(width) // 2
    for x, y in (scaled_points[0], scaled_points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=rgba)


def curve_points(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    steps: int = 24,
) -> list[tuple[float, float]]:
    points = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0]
        y = mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]
        points.append((x, y))
    return points


def swish(
    draw: ImageDraw.ImageDraw,
    upper: tuple[tuple[float, float], tuple[float, float], tuple[float, float]],
    lower: tuple[tuple[float, float], tuple[float, float], tuple[float, float]],
    fill: tuple[int, int, int, int],
) -> None:
    upper_points = curve_points(*upper, steps=36)
    lower_points = list(reversed(curve_points(*lower, steps=36)))
    draw.polygon([(sc(x), sc(y)) for x, y in upper_points + lower_points], fill=fill)


def draw_background(image: Image.Image) -> None:
    draw = ImageDraw.Draw(image, "RGBA")
    draw.rectangle((0, 0, sc(CANVAS), sc(CANVAS)), fill=c("#EAF8F2"))
    draw.ellipse((sc(124), sc(124), sc(900), sc(900)), fill=c("#D3F0E6"))


def draw_note(base: Image.Image) -> None:
    return


def draw_pin(base: Image.Image) -> None:
    draw = ImageDraw.Draw(base, "RGBA")
    draw.ellipse((sc(268), sc(142), sc(756), sc(630)), fill=c("#EF5350"))
    draw.polygon([(sc(304), sc(514)), (sc(720), sc(514)), (sc(512), sc(876))], fill=c("#EF5350"))
    draw.ellipse((sc(416), sc(290), sc(608), sc(482)), fill=c("#FFFFFF"))
    draw.ellipse((sc(466), sc(340), sc(558), sc(432)), fill=c("#0B4E59"))
    hair_color = c("#EF5350")
    swish(
        draw,
        ((547, 134), (598, 60), (704, 30)),
        ((607, 150), (650, 108), (704, 30)),
        hair_color,
    )
    swish(
        draw,
        ((607, 150), (702, 78), (826, 50)),
        ((682, 197), (748, 132), (826, 50)),
        hair_color,
    )
    swish(
        draw,
        ((682, 197), (780, 136), (890, 116)),
        ((736, 267), (805, 205), (890, 116)),
        hair_color,
    )


def make_master() -> Image.Image:
    image = Image.new("RGBA", (sc(CANVAS), sc(CANVAS)), (0, 0, 0, 255))
    draw_background(image)
    draw_note(image)
    draw_pin(image)
    return image.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS).convert("RGB")


def save_resized(master: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    master.resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)


def main() -> None:
    master = make_master()
    MASTER_PATH.parent.mkdir(parents=True, exist_ok=True)
    master.save(MASTER_PATH, optimize=True)

    ios_icons = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for filename, size in ios_icons.items():
        save_resized(master, IOS_ICON_DIR / filename, size)

    android_icons = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    for relative_path, size in android_icons.items():
        save_resized(master, ANDROID_RES_DIR / relative_path, size)


if __name__ == "__main__":
    main()
