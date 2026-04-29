#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App Store 预览图（PNG，sRGB），尺寸依据 Apple Screenshot specifications。"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# AppTheme 近似 RGB（Neon Sovereign）
BG_TOP = (13, 13, 25)
BG_BOTTOM = (40, 22, 58)
PRIMARY = (197, 154, 255)
PRIMARY_DIM = (149, 71, 247)
ON_SURFACE = (230, 227, 245)
ON_VARIANT = (140, 138, 160)
SECONDARY = (255, 215, 9)

# Apple 接受的常见 iPhone 竖屏尺寸（宽 x 高）
SIZES = {
    "iPhone_6.7_1290x2796": (1290, 2796),  # 6.7" / 多套 6.9" 档位亦接受此尺寸
    "iPhone_6.5_1284x2778": (1284, 2778),  # 6.5"
    "iPhone_5.5_1242x2208": (1242, 2208),  # 5.5"
}

FRAMES: list[tuple[str, str, str]] = [
    ("01", "模板发现 · 双列瀑布流", "浏览换脸、视频与舞蹈模板，一键进入详情"),
    ("02", "沉浸式全屏浏览", "竖滑信息流，专注预览每条模板"),
    ("03", "视频与舞蹈成片", "静音循环预览，直观感受生成效果"),
    ("04", "布局随心切换", "沉浸式与网格双模式，锚点同步不打断浏览"),
    ("05", "金币与创作流程", "消耗透明、充值便捷，完成你的创意"),
]


def gradient_rgb(w: int, h: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (w, h))
    hm = max(h - 1, 1)
    pixels: list[tuple[int, int, int]] = []
    for y in range(h):
        t = y / hm
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        pixels.extend([(r, g, b)] * w)
    img.putdata(pixels)
    return img


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for path in candidates:
        if os.path.isfile(path):
            try:
                return ImageFont.truetype(path, size=size, index=0)
            except OSError:
                continue
    return ImageFont.load_default()


def draw_phone_mock(draw: ImageDraw.ImageDraw, cx: int, top: int, w: int, h: int) -> None:
    """中间一块圆角「手机界面」示意。"""
    x0, y0 = cx - w // 2, top
    x1, y1 = x0 + w, y0 + h
    draw.rounded_rectangle([x0, y0, x1, y1], radius=36, fill=(24, 24, 39), outline=PRIMARY_DIM, width=4)
    # 内部高光条模拟列表
    inner_margin = 32
    iy = y0 + 120
    for i in range(5):
        bar_w = w - inner_margin * 2 - (i % 2) * 80
        draw.rounded_rectangle(
            [x0 + inner_margin, iy, x0 + inner_margin + bar_w, iy + 56],
            radius=12,
            fill=(36, 36, 54),
        )
        iy += 72


def render_frame(
    size_key: str,
    width: int,
    height: int,
    title: str,
    subtitle: str,
) -> Image.Image:
    img = gradient_rgb(width, height, BG_TOP, BG_BOTTOM)
    draw = ImageDraw.Draw(img)

    font_title = load_font(64 if width >= 1284 else 52)
    font_sub = load_font(38 if width >= 1284 else 30)
    font_badge = load_font(28)

    # 顶部小标签
    badge = f"bbb · {size_key}"
    draw.text((width // 2, int(height * 0.08)), badge, fill=ON_VARIANT, font=font_badge, anchor="mm")

    # 标题（多行）
    tw = int(width * 0.82)
    title_lines = wrap_text(title, font_title, tw, draw)
    title_line_height = int(getattr(font_title, "size", 64) * 1.35)
    y = int(height * 0.11)
    for line in title_lines:
        draw.text((width // 2, y), line, fill=ON_SURFACE, font=font_title, anchor="mm")
        y += title_line_height

    # 中间设备框
    mock_w = int(width * 0.78)
    mock_h = int(height * 0.42)
    draw_phone_mock(draw, width // 2, int(height * 0.28), mock_w, mock_h)

    # 副标题
    sub_lines = wrap_text(subtitle, font_sub, tw, draw)
    sub_line_height = int(getattr(font_sub, "size", 38) * 1.3)
    y = int(height * 0.76)
    for line in sub_lines:
        draw.text((width // 2, y), line, fill=ON_VARIANT, font=font_sub, anchor="mm")
        y += sub_line_height

    # 底部品牌条
    draw.rounded_rectangle(
        [int(width * 0.12), height - 120, int(width * 0.88), height - 48],
        radius=20,
        fill=(30, 24, 50),
        outline=PRIMARY,
        width=2,
    )
    draw.text((width // 2, height - 84), "Neon Sovereign · AI 模板", fill=PRIMARY, font=font_badge, anchor="mm")

    return img


def wrap_text(text: str, font: ImageFont.FreeTypeFont | ImageFont.ImageFont, max_width: int, draw: ImageDraw.ImageDraw) -> list[str]:
    text = text.strip()
    if not text:
        return [""]
    lines: list[str] = []
    buf = ""
    for ch in text:
        trial = buf + ch
        bbox = draw.textbbox((0, 0), trial, font=font)
        if bbox[2] - bbox[0] <= max_width:
            buf = trial
        else:
            if buf:
                lines.append(buf)
            buf = ch
    if buf:
        lines.append(buf)
    return lines if lines else [text]


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out_dir = root / "预览图"
    out_dir.mkdir(parents=True, exist_ok=True)

    readme = out_dir / "尺寸说明.txt"
    readme.write_text(
        "App Store 预览图（竖屏 PNG）\n\n"
        "依据 Apple App Store Connect — Screenshot specifications 常见档位：\n"
        "- iPhone_6.7_1290x2796：1290 × 2796 px（6.7\" 等，亦被 6.9\" 档位接受）\n"
        "- iPhone_6.5_1284x2778：1284 × 2778 px（6.5\"）\n"
        "- iPhone_5.5_1242x2208：1242 × 2208 px（5.5\"）\n\n"
        "格式：PNG，不透明背景。可按需替换为真实截图并保留同名尺寸导出。\n",
        encoding="utf-8",
    )

    for folder_name, (w, h) in SIZES.items():
        sub = out_dir / folder_name
        sub.mkdir(parents=True, exist_ok=True)
        for idx, title, subtitle in FRAMES:
            im = render_frame(folder_name, w, h, title, subtitle)
            path = sub / f"app_store_preview_{idx}.png"
            im.save(path, "PNG", optimize=True)
            print(f"Wrote {path.relative_to(root)}")


if __name__ == "__main__":
    main()
