#!/usr/bin/env python3
"""Generate the A4 network diagram used for the telecom business filing."""

from __future__ import annotations

import argparse
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


FONT_CANDIDATES = (
    Path("/Library/Fonts/Arial Unicode.ttf"),
    Path("/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"),
)


def register_japanese_font() -> str:
    for path in FONT_CANDIDATES:
        if not path.exists():
            continue
        try:
            pdfmetrics.registerFont(TTFont("Japanese", str(path)))
            return "Japanese"
        except Exception:
            continue
    raise RuntimeError(
        "A Japanese TrueType font was not found. "
        "Install Arial Unicode MS or update FONT_CANDIDATES."
    )


def centered_lines(
    page: canvas.Canvas,
    lines: list[str],
    *,
    center_x: float,
    center_y: float,
    font_name: str,
    font_size: float,
    leading: float,
) -> None:
    page.setFont(font_name, font_size)
    baseline = center_y + (len(lines) - 1) * leading / 2 - font_size * 0.35
    for index, line in enumerate(lines):
        page.drawCentredString(center_x, baseline - index * leading, line)


def vertical_arrow(
    page: canvas.Canvas,
    *,
    x: float,
    start_y: float,
    end_y: float,
    line_width: float = 1.1,
) -> None:
    page.setLineWidth(line_width)
    page.line(x, start_y, x, end_y)
    direction = 1 if end_y > start_y else -1
    head = 2.6 * mm
    page.line(x, end_y, x - head, end_y - direction * head)
    page.line(x, end_y, x + head, end_y - direction * head)


def draw_endpoint(
    page: canvas.Canvas,
    *,
    center_x: float,
    center_y: float,
    width: float,
    height: float,
    lines: list[str],
    font_name: str,
) -> None:
    page.setLineWidth(1.2)
    page.setFillColorRGB(1, 1, 1)
    page.ellipse(
        center_x - width / 2,
        center_y - height / 2,
        center_x + width / 2,
        center_y + height / 2,
        fill=1,
        stroke=1,
    )
    page.setFillColorRGB(0, 0, 0)
    centered_lines(
        page,
        lines,
        center_x=center_x,
        center_y=center_y,
        font_name=font_name,
        font_size=11,
        leading=5.2 * mm,
    )


def generate(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    font_name = register_japanese_font()
    page = canvas.Canvas(str(output_path), pagesize=A4)
    page.setTitle("World Notes（セカイノート） ネットワーク構成図")
    page.setAuthor("World Notes（セカイノート）")
    page.setSubject("電気通信事業届出用ネットワーク構成図")

    page_width, _ = A4
    center_x = page_width / 2

    page.setFillColorRGB(0, 0, 0)
    page.setFont(font_name, 18)
    page.drawCentredString(center_x, 278 * mm, "ネットワーク構成図")
    page.setFont(font_name, 12)
    page.drawCentredString(
        center_x,
        264 * mm,
        "ネットワークの名称「World Notes（セカイノート）」",
    )

    network_x = 20 * mm
    network_y = 31 * mm
    network_width = 170 * mm
    network_height = 215 * mm
    page.setLineWidth(1.2)
    page.roundRect(
        network_x,
        network_y,
        network_width,
        network_height,
        15 * mm,
        fill=0,
        stroke=1,
    )
    page.setFont(font_name, 11)
    page.drawString(network_x + 9 * mm, network_y + network_height - 12 * mm, "インターネット網")

    endpoint_width = 78 * mm
    endpoint_height = 25 * mm
    server_width = 92 * mm
    server_height = 30 * mm
    top_y = 207 * mm
    server_y = 139 * mm
    bottom_y = 71 * mm

    draw_endpoint(
        page,
        center_x=center_x,
        center_y=top_y,
        width=endpoint_width,
        height=endpoint_height,
        lines=["ユーザー", "（スマートフォン）"],
        font_name=font_name,
    )
    draw_endpoint(
        page,
        center_x=center_x,
        center_y=server_y,
        width=server_width,
        height=server_height,
        lines=["World Notes（セカイノート）", "サーバー（Google Firebase）"],
        font_name=font_name,
    )
    draw_endpoint(
        page,
        center_x=center_x,
        center_y=bottom_y,
        width=endpoint_width,
        height=endpoint_height,
        lines=["ユーザー", "（スマートフォン）"],
        font_name=font_name,
    )

    arrow_left_x = center_x - 36 * mm
    arrow_right_x = center_x + 36 * mm
    top_endpoint_bottom = top_y - endpoint_height / 2
    server_top = server_y + server_height / 2
    server_bottom = server_y - server_height / 2
    bottom_endpoint_top = bottom_y + endpoint_height / 2

    vertical_arrow(
        page,
        x=arrow_left_x,
        start_y=server_top + 3 * mm,
        end_y=top_endpoint_bottom - 3 * mm,
    )
    vertical_arrow(
        page,
        x=arrow_right_x,
        start_y=top_endpoint_bottom - 3 * mm,
        end_y=server_top + 3 * mm,
    )
    centered_lines(
        page,
        ["メッセージ・画像等"],
        center_x=center_x,
        center_y=(top_endpoint_bottom + server_top) / 2,
        font_name=font_name,
        font_size=9.5,
        leading=4.5 * mm,
    )

    vertical_arrow(
        page,
        x=arrow_left_x,
        start_y=bottom_endpoint_top + 3 * mm,
        end_y=server_bottom - 3 * mm,
    )
    vertical_arrow(
        page,
        x=arrow_right_x,
        start_y=server_bottom - 3 * mm,
        end_y=bottom_endpoint_top + 3 * mm,
    )
    centered_lines(
        page,
        ["メッセージ・画像等"],
        center_x=center_x,
        center_y=(server_bottom + bottom_endpoint_top) / 2,
        font_name=font_name,
        font_size=9.5,
        leading=4.5 * mm,
    )

    page.setFont(font_name, 8.5)
    page.drawCentredString(
        center_x,
        42 * mm,
        "利用者端末は携帯電話回線又はWi-Fi等によりインターネットへ接続",
    )
    page.drawCentredString(
        center_x,
        37.5 * mm,
        "（自営の伝送路設備は設置しない）",
    )

    page.showPage()
    page.save()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            "internal-docs/telecommunications/"
            "world_notes_network_configuration.pdf"
        ),
    )
    args = parser.parse_args()
    generate(args.output)


if __name__ == "__main__":
    main()
