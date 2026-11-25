#!/usr/bin/env python3
"""
KaaijkOS 1.1 — Grafische GRUB 2.14 Thema- & PF2-Font Generator
Genereert assets/grub-theme/ (wallpaper-achtergrond, KaaijkOS-logo, 9-slice UI,
menu-iconen, theme.txt en binaire GRUB PFF2-fonts) zonder externe CLI-tools.
"""
from __future__ import annotations

import argparse
import math
import os
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "assets" / "grub-theme"

CODEPOINTS = sorted(
    set(range(0x0020, 0x007F))
    | set(range(0x00A0, 0x0100))
    | {0x2022, 0x2190, 0x2191, 0x2192, 0x2193, 0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518}
)


def resolve_font_path(fonts_dir: Path | None, candidates: list[str]) -> Path:
    search_dirs: list[Path] = []
    if fonts_dir is not None:
        search_dirs.append(fonts_dir)
    if os.name == "nt":
        search_dirs.append(Path(r"C:\Windows\Fonts"))
    search_dirs.extend([
        Path("/usr/share/fonts"),
        Path("/usr/local/share/fonts"),
    ])
    for name in candidates:
        for base in search_dirs:
            direct = base / name
            if direct.is_file():
                return direct
            if base.is_dir():
                for found in base.rglob(name):
                    if found.is_file():
                        return found
    raise FileNotFoundError(f"Font niet gevonden ({candidates}) in {search_dirs}")


def _glyph_notdef_bytes(font: ImageFont.FreeTypeFont, cw: int, ch: int, pad_x: int, baseline_y: int) -> bytes:
    im = Image.new("L", (cw, ch), 0)
    ImageDraw.Draw(im).text((pad_x, baseline_y), "\uffff", font=font, fill=255, anchor="ls")
    return im.tobytes()


def _pack_1bpp_msb(im: Image.Image) -> bytes:
    """Pack grayscale tight-cropped bitmap tightly row-major MSB-first (no row padding)."""
    w, h = im.size
    if w == 0 or h == 0:
        return b""
    px = im.tobytes()
    out = bytearray((w * h + 7) // 8)
    for idx, val in enumerate(px):
        if val >= 110:
            out[idx >> 3] |= 1 << (7 - (idx & 7))
    return bytes(out)


def _pf2_section(tag: bytes, payload: bytes) -> bytes:
    assert len(tag) == 4
    return tag + struct.pack(">I", len(payload)) + payload


def build_pf2(
    out_path: Path,
    font_name: str,
    family: str,
    size: int,
    primary_ttf: Path,
    fallback_ttf: Path,
) -> dict[str, int]:
    primary = ImageFont.truetype(str(primary_ttf), size)
    fallback = ImageFont.truetype(str(fallback_ttf), size)

    cw = max(64, size * 4)
    ch = max(64, size * 4)
    pad_x = cw // 3
    baseline_y = (ch * 2) // 3

    notdef_primary = _glyph_notdef_bytes(primary, cw, ch, pad_x, baseline_y)
    notdef_fallback = _glyph_notdef_bytes(fallback, cw, ch, pad_x, baseline_y)

    ascent_raw, descent_raw = primary.getmetrics()
    ascent = max(1, int(ascent_raw))
    descent = max(1, int(descent_raw))
    space_adv = max(4, int(round(primary.getlength(" "))))

    glyph_records: list[tuple[int, bytes]] = []
    max_w = 1
    max_h = 1

    for cp in CODEPOINTS:
        ch_str = chr(cp)
        if cp in (0x0020, 0x00A0):
            rec = struct.pack(">HHhhh", 0, 0, 0, 0, space_adv)
            glyph_records.append((cp, rec))
            continue

        chosen = primary
        im = Image.new("L", (cw, ch), 0)
        ImageDraw.Draw(im).text((pad_x, baseline_y), ch_str, font=chosen, fill=255, anchor="ls")
        if im.tobytes() == notdef_primary:
            im_fb = Image.new("L", (cw, ch), 0)
            ImageDraw.Draw(im_fb).text((pad_x, baseline_y), ch_str, font=fallback, fill=255, anchor="ls")
            if im_fb.tobytes() != notdef_fallback:
                chosen = fallback
                im = im_fb

        bw_im = im.point(lambda p: 255 if p >= 110 else 0, mode="1")
        bbox = bw_im.getbbox()
        adv = max(1, int(round(chosen.getlength(ch_str))))
        if bbox is None:
            rec = struct.pack(">HHhhh", 0, 0, 0, 0, adv)
            glyph_records.append((cp, rec))
            continue

        x0, y0, x1, y1 = bbox
        w = x1 - x0
        h = y1 - y0
        xoff = x0 - pad_x
        yoff = baseline_y - y1
        crop = im.crop((x0, y0, x1, y1))
        packed = _pf2_bitcheck(_pack_1bpp_msb(crop), w, h)
        rec = struct.pack(">HHhhh", w, h, xoff, yoff, adv) + packed
        glyph_records.append((cp, rec))
        if w > max_w:
            max_w = w
        if h > max_h:
            max_h = h

    pre_chix = b"".join([
        _pf2_section(b"FILE", b"PFF2"),
        _pf2_section(b"NAME", font_name.encode("ascii") + b"\x00"),
        _pf2_section(b"FAMI", family.encode("ascii") + b"\x00"),
        _pf2_section(b"WEIG", b"normal\x00"),
        _pf2_section(b"SLAN", b"normal\x00"),
        _pf2_section(b"PTSZ", struct.pack(">H", size)),
        _pf2_section(b"MAXW", struct.pack(">H", max_w)),
        _pf2_section(b"MAXH", struct.pack(">H", max_h)),
        _pf2_section(b"ASCE", struct.pack(">H", ascent)),
        _pf2_section(b"DESC", struct.pack(">H", descent)),
    ])

    num_chars = len(glyph_records)
    chix_len = 9 * num_chars
    data_payload_start = len(pre_chix) + 8 + chix_len + 8

    chix_buf = bytearray()
    data_buf = bytearray()
    for cp, rec in glyph_records:
        abs_off = data_payload_start + len(data_buf)
        chix_buf += struct.pack(">IBI", cp, 0, abs_off)
        data_buf += rec

    raw = (
        pre_chix
        + _pf2_section(b"CHIX", bytes(chix_buf))
        + b"DATA"
        + struct.pack(">I", 0xFFFFFFFF)
        + bytes(data_buf)
    )
    out_path.write_bytes(raw)
    return {
        "glyphs": num_chars,
        "bytes": len(raw),
        "ascent": ascent,
        "descent": descent,
        "max_w": max_w,
        "max_h": max_h,
    }


def _pf2_bitcheck(data: bytes, w: int, h: int) -> bytes:
    expected = (w * h + 7) // 8
    assert len(data) == expected, f"bitmap size mismatch: {len(data)} != {expected}"
    return data


def verify_pf2(path: Path) -> tuple[str, dict[int, tuple[int, int, int, int, int, bytes]], dict[str, int]]:
    """Onafhankelijke PFF2 parser volgens grub-core/font/font.c."""
    raw = path.read_bytes()
    pos = 0
    if len(raw) < 12 or raw[:4] != b"FILE":
        raise ValueError(f"{path}: 1e sectie is geen FILE")
    flen = struct.unpack_from(">I", raw, 4)[0]
    if flen != 4 or raw[8:12] != b"PFF2":
        raise ValueError(f"{path}: ongeldige FILE/PFF2 magic")
    pos = 12

    sections: dict[str, bytes] = {}
    chix_entries: list[tuple[int, int, int]] = []
    data_start = None
    while pos + 8 <= len(raw):
        tag = raw[pos:pos + 4].decode("ascii")
        slen = struct.unpack_from(">I", raw, pos + 4)[0]
        pos += 8
        if tag == "DATA":
            if slen != 0xFFFFFFFF:
                raise ValueError(f"{path}: DATA lengte {hex(slen)} != 0xffffffff")
            data_start = pos
            break
        if pos + slen > len(raw):
            raise ValueError(f"{path}: sectie {tag} buiten bestand")
        payload = raw[pos:pos + slen]
        pos += slen
        sections[tag] = payload
        if tag == "CHIX":
            if slen % 9 != 0:
                raise ValueError(f"{path}: CHIX lengte niet deelbaar door 9")
            prev_cp = -1
            for off in range(0, slen, 9):
                cp, flags, g_off = struct.unpack_from(">IBI", payload, off)
                if cp <= prev_cp:
                    raise ValueError(f"{path}: CHIX niet strikt oplopend bij {hex(cp)}")
                prev_cp = cp
                chix_entries.append((cp, flags, g_off))

    for req in ("NAME", "PTSZ", "MAXW", "MAXH", "ASCE", "DESC", "CHIX"):
        if req not in sections:
            raise ValueError(f"{path}: verplichte sectie {req} ontbreekt")
    if data_start is None:
        raise ValueError(f"{path}: DATA sectie ontbreekt")

    name = sections["NAME"].rstrip(b"\x00").decode("ascii")
    ptsz = struct.unpack(">H", sections["PTSZ"])[0]
    maxw = struct.unpack(">H", sections["MAXW"])[0]
    maxh = struct.unpack(">H", sections["MAXH"])[0]
    asce = struct.unpack(">H", sections["ASCE"])[0]
    desc = struct.unpack(">H", sections["DESC"])[0]
    if asce <= 0 or desc <= 0 or maxw <= 0 or maxh <= 0:
        raise ValueError(f"{path}: ongeldige metrics asce={asce} desc={desc} max={maxw}x{maxh}")

    glyphs: dict[int, tuple[int, int, int, int, int, bytes]] = {}
    for cp, flags, g_off in chix_entries:
        if flags != 0:
            raise ValueError(f"{path}: onverwachte opslagvlag {flags}")
        if g_off < data_start or g_off + 10 > len(raw):
            raise ValueError(f"{path}: ongeldige glyph offset {g_off}")
        w, h, xoff, yoff, dwidth = struct.unpack_from(">HHhhh", raw, g_off)
        if w > maxw or h > maxh:
            raise ValueError(f"{path}: glyph {hex(cp)} groter dan MAXW/MAXH ({w}x{h})")
        blen = (w * h + 7) // 8
        if g_off + 10 + blen > len(raw):
            raise ValueError(f"{path}: glyph {hex(cp)} bitmap afgekapt")
        glyphs[cp] = (w, h, xoff, yoff, dwidth, raw[g_off + 10:g_off + 10 + blen])

    return name, glyphs, {"ptsz": ptsz, "maxw": maxw, "maxh": maxh, "ascent": asce, "descent": desc}


def generate_background(out_path: Path) -> None:
    wp_path = REPO_ROOT / "assets" / "kaaijkos-wallpaper.png"
    bg = Image.open(wp_path).convert("RGB").resize((1280, 720), Image.Resampling.LANCZOS)

    # Smooth vignette / central + bottom darkening overlay so blue/magenta nebula glows
    # while glass menu, white text & footer remain sharp and high-contrast.
    overlay = Image.new("RGBA", (1280, 720), (6, 10, 20, 96))
    rad = Image.new("L", (1280, 720), 0)
    draw_rad = ImageDraw.Draw(rad)
    draw_rad.ellipse((240, 80, 1040, 620), fill=58)
    draw_rad.rectangle((0, 600, 1280, 720), fill=64)
    rad = rad.filter(ImageFilter.GaussianBlur(radius=90))

    dark_center = Image.new("RGBA", (1280, 720), (5, 8, 18, 255))
    dark_center.putalpha(rad)

    comp = Image.alpha_composite(bg.convert("RGBA"), overlay)
    comp = Image.alpha_composite(comp, dark_center).convert("RGB")
    comp.save(out_path, format="PNG", optimize=True)


def generate_logo(out_path: Path) -> None:
    splash_path = REPO_ROOT / "assets" / "boot" / "splash-kaaijkos.bmp"
    src = Image.open(splash_path).convert("RGBA")
    bbox = src.getbbox()
    if bbox is None:
        raise ValueError(f"{splash_path} is leeg")
    cropped = src.crop(bbox)

    canvas_w, canvas_h = 340, 134
    max_w, max_h = 328, 122
    scale = min(max_w / cropped.width, max_h / cropped.height)
    new_w = max(1, int(round(cropped.width * scale)))
    new_h = max(1, int(round(cropped.height * scale)))
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)

    x = (canvas_w - new_w) // 2
    y = (canvas_h - new_h) // 2

    logo_layer = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    logo_layer.paste(resized, (x, y), resized)

    alpha_mask = logo_layer.getchannel("A").filter(ImageFilter.GaussianBlur(radius=3.5))
    shadow_alpha = alpha_mask.point(lambda a: int(round(a * 0.65)))
    shadow_img = Image.new("RGBA", (canvas_w, canvas_h), (5, 8, 18, 255))
    shadow_img.putalpha(shadow_alpha)

    shadow_shifted = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    shadow_shifted.paste(shadow_img, (0, 3))

    final_logo = Image.alpha_composite(shadow_shifted, logo_layer)
    final_logo.save(out_path, format="PNG", optimize=True)


def _save_nine_slice(out_dir: Path, prefix: str, tile: int, draw_fn) -> None:
    full = Image.new("RGBA", (tile * 3, tile * 3), (0, 0, 0, 0))
    draw_fn(full, tile)
    slices = [
        ("nw", 0, 0), ("n", tile, 0), ("ne", tile * 2, 0),
        ("w", 0, tile), ("c", tile, tile), ("e", tile * 2, tile),
        ("sw", 0, tile * 2), ("s", tile, tile * 2), ("se", tile * 2, tile * 2),
    ]
    for suffix, sx, sy in slices:
        full.crop((sx, sy, sx + tile, sy + tile)).save(
            out_dir / f"{prefix}_{suffix}.png", format="PNG", optimize=True
        )


def generate_nine_slices(out_dir: Path) -> None:
    def draw_menu(im: Image.Image, tile: int) -> None:
        w, h = im.size
        d = ImageDraw.Draw(im)
        d.rounded_rectangle(
            (0, 0, w - 1, h - 1),
            radius=10,
            fill=(10, 15, 28, 200),
            outline=(56, 189, 248, 80),
            width=1,
        )

    def draw_select(im: Image.Image, tile: int) -> None:
        w, h = im.size
        d = ImageDraw.Draw(im)
        d.rounded_rectangle(
            (0, 0, w - 1, h - 1),
            radius=6,
            fill=(14, 165, 233, 72),
            outline=(56, 189, 248, 175),
            width=1,
        )
        # Bright cyan 3px left accent strip clipped to pill rounded mask
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=6, fill=255)
        bar = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(bar).rectangle((0, 0, 2, h - 1), fill=(34, 211, 238, 255))
        bar_clipped = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        bar_clipped.paste(bar, (0, 0), mask)
        im.alpha_composite(bar_clipped)

    def draw_terminal(im: Image.Image, tile: int) -> None:
        w, h = im.size
        d = ImageDraw.Draw(im)
        d.rounded_rectangle(
            (0, 0, w - 1, h - 1),
            radius=8,
            fill=(7, 11, 20, 228),
            outline=(56, 189, 248, 95),
            width=1,
        )

    _save_nine_slice(out_dir, "menu", 12, draw_menu)
    _save_nine_slice(out_dir, "select", 8, draw_select)
    _save_nine_slice(out_dir, "terminal", 12, draw_terminal)


def generate_icons(icons_dir: Path) -> None:
    icons_dir.mkdir(parents=True, exist_ok=True)

    # 1. kaaijkos.png from assets/kaaijkos-logo-klein.png
    k_src = Image.open(REPO_ROOT / "assets" / "kaaijkos-logo-klein.png").convert("RGBA")
    k_crop = k_src.crop(k_src.getbbox())
    scale = min(22 / k_crop.width, 22 / k_crop.height)
    kw = max(1, int(round(k_crop.width * scale)))
    kh = max(1, int(round(k_crop.height * scale)))
    k_res = k_crop.resize((kw, kh), Image.Resampling.LANCZOS)
    k_canvas = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    k_canvas.paste(k_res, ((24 - kw) // 2, (24 - kh) // 2), k_res)
    k_canvas.save(icons_dir / "kaaijkos.png", format="PNG", optimize=True)

    # 2. cli.png (96x96 -> 24x24): crisp cyan CLI terminal box with ">_"
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(
        (8, 14, 88, 82),
        radius=14,
        fill=(15, 23, 42, 220),
        outline=(34, 211, 238, 255),
        width=6,
    )
    d.line([(26, 36), (42, 48), (26, 60)], fill=(34, 211, 238, 255), width=7, joint="curve")
    d.line([(48, 60), (68, 60)], fill=(139, 92, 246, 255), width=7)
    im.resize((24, 24), Image.Resampling.LANCZOS).save(icons_dir / "cli.png", format="PNG", optimize=True)

    # 3. debug.png (96x96 -> 24x24): amber/cyan diagnostic terminal badge
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(
        (8, 14, 88, 82),
        radius=14,
        fill=(15, 23, 42, 220),
        outline=(251, 191, 36, 255),
        width=6,
    )
    d.line([(26, 36), (42, 48), (26, 60)], fill=(251, 191, 36, 255), width=7, joint="curve")
    d.line([(48, 60), (68, 60)], fill=(248, 113, 113, 255), width=7)
    im.resize((24, 24), Image.Resampling.LANCZOS).save(icons_dir / "debug.png", format="PNG", optimize=True)

    # 3. uefi.png (96x96 -> 24x24): UEFI chip / gear badge
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = 48, 48
    for deg in range(0, 360, 45):
        rad_a = math.radians(deg)
        x1 = cx + math.cos(rad_a) * 28
        y1 = cy + math.sin(rad_a) * 28
        x2 = cx + math.cos(rad_a) * 40
        y2 = cy + math.sin(rad_a) * 40
        d.line([(x1, y1), (x2, y2)], fill=(56, 189, 248, 255), width=10)
    d.ellipse((20, 20, 76, 76), fill=(15, 23, 42, 235), outline=(148, 163, 184, 255), width=7)
    d.ellipse((37, 37, 59, 59), fill=(56, 189, 248, 255))
    im.resize((24, 24), Image.Resampling.LANCZOS).save(icons_dir / "uefi.png", format="PNG", optimize=True)

    # 4. restart.png (96x96 -> 24x24): circular refresh arrow
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.arc((16, 16, 80, 80), start=35, end=310, fill=(34, 211, 238, 255), width=9)
    d.polygon([(78, 18), (82, 42), (58, 36)], fill=(34, 211, 238, 255))
    im.resize((24, 24), Image.Resampling.LANCZOS).save(icons_dir / "restart.png", format="PNG", optimize=True)

    # 5. shutdown.png (96x96 -> 24x24): soft red power symbol
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.arc((16, 18, 80, 82), start=-55, end=235, fill=(248, 113, 113, 255), width=9)
    d.line([(48, 12), (48, 44)], fill=(248, 113, 113, 255), width=9)
    im.resize((24, 24), Image.Resampling.LANCZOS).save(icons_dir / "shutdown.png", format="PNG", optimize=True)


THEME_TXT = """# KaaijkOS 1.1 GRUB Theme
title-text: ""
desktop-color: "#090d16"
desktop-image: "background.png"
desktop-image-scale-method: "crop"
desktop-image-h-align: "center"
desktop-image-v-align: "center"

terminal-font: "Cascadia Mono 16"
terminal-box: "terminal_*.png"
terminal-left: "10%"
terminal-top: "12%"
terminal-width: "80%"
terminal-height: "76%"
terminal-border: "12"

+ image {
    left = 50%-170
    top = 50%-265
    width = 340
    height = 134
    file = "logo.png"
}

+ boot_menu {
    left = 50%-300
    top = 50%-110
    width = 600
    height = 312
    item_font = "Roboto Regular 18"
    selected_item_font = "Roboto Regular 18"
    item_color = "#cbd5e1"
    selected_item_color = "#ffffff"
    icon_width = 24
    icon_height = 24
    item_icon_space = 16
    item_height = 32
    item_padding = 10
    item_spacing = 10
    menu_pixmap_style = "menu_*.png"
    selected_item_pixmap_style = "select_*.png"
    scrollbar = false
}

+ label {
    left = 0
    top = 91%
    width = 100%
    height = 28
    align = "center"
    font = "Roboto Regular 14"
    color = "#94a3b8"
    text = "↑↓ Select   ·   Enter Boot   ·   e Edit   ·   c Console"
}
"""


def verify_theme(theme_dir: Path) -> dict[str, tuple]:
    parsed_fonts: dict[str, tuple] = {}
    for pf2_name in ("kaaijkos-sans-18.pf2", "kaaijkos-sans-14.pf2", "kaaijkos-mono-16.pf2"):
        pf2_path = theme_dir / pf2_name
        if not pf2_path.is_file():
            raise FileNotFoundError(f"Font ontbreekt: {pf2_path}")
        name, glyphs, meta = verify_pf2(pf2_path)
        parsed_fonts[name] = (glyphs, meta)
        print(f"  [OK] {pf2_name}: NAME='{name}', glyphs={len(glyphs)}, ascent={meta['ascent']}, descent={meta['descent']}")

    for needed_font in ("Cascadia Mono 16", "Roboto Regular 18", "Roboto Regular 14"):
        if needed_font not in parsed_fonts:
            raise ValueError(f"theme.txt font '{needed_font}' niet gevonden in gegenereerde PF2-bestanden")

    bg = Image.open(theme_dir / "background.png")
    assert bg.size == (1280, 720) and bg.mode == "RGB", f"background.png onverwacht: {bg.size} {bg.mode}"
    logo = Image.open(theme_dir / "logo.png")
    assert logo.size == (340, 134) and logo.mode == "RGBA", f"logo.png onverwacht: {logo.size} {logo.mode}"

    for prefix, tile in (("menu", 12), ("select", 8), ("terminal", 12)):
        for suffix in ("nw", "n", "ne", "w", "c", "e", "sw", "s", "se"):
            p = theme_dir / f"{prefix}_{suffix}.png"
            im = Image.open(p)
            assert im.size == (tile, tile) and im.mode == "RGBA", f"{p} onverwacht: {im.size} {im.mode}"

    for icon_name in ("kaaijkos.png", "cli.png", "debug.png", "uefi.png", "restart.png", "shutdown.png"):
        p = theme_dir / "icons" / icon_name
        im = Image.open(p)
        assert im.size == (24, 24) and im.mode == "RGBA", f"{p} onverwacht: {im.size} {im.mode}"

    txt = (theme_dir / "theme.txt").read_bytes()
    assert b"\r" not in txt, "CRLF gevonden in theme.txt"
    print("  [OK] Alle 9-slice tiles, achtergrond, logo, iconen en theme.txt gevalideerd.")
    return parsed_fonts


def _draw_pf2_string(
    canvas: Image.Image,
    text: str,
    font_entry: tuple,
    x: int,
    baseline_y: int,
    color: tuple[int, int, int],
) -> None:
    glyphs, _ = font_entry
    px = canvas.load()
    cw, ch = canvas.size
    pen_x = x
    for c in text:
        cp = ord(c)
        g = glyphs.get(cp) or glyphs.get(0x3F)
        if g is None:
            continue
        w, h, xoff, yoff, dwidth, bmap = g
        if w > 0 and h > 0:
            # Exact grub_font_draw_glyph formule (grub-core/font/font.c)
            bitmap_left = pen_x + xoff
            bitmap_bottom = baseline_y - yoff
            bitmap_top = bitmap_bottom - h
            for ry in range(h):
                py = bitmap_top + ry
                if py < 0 or py >= ch:
                    continue
                for rx in range(w):
                    px_x = bitmap_left + rx
                    if px_x < 0 or px_x >= cw:
                        continue
                    bit_idx = ry * w + rx
                    if (bmap[bit_idx >> 3] >> (7 - (bit_idx & 7))) & 1:
                        px[px_x, py] = (*color, 255)
        pen_x += dwidth


def _measure_pf2_string(text: str, font_entry: tuple) -> int:
    glyphs, _ = font_entry
    total = 0
    for c in text:
        g = glyphs.get(ord(c)) or glyphs.get(0x3F)
        if g is not None:
            total += g[4]
    return total


def _draw_nine_slice_box(canvas: Image.Image, theme_dir: Path, prefix: str, x: int, y: int, w: int, h: int) -> None:
    parts = {s: Image.open(theme_dir / f"{prefix}_{s}.png").convert("RGBA")
             for s in ("nw", "n", "ne", "w", "c", "e", "sw", "s", "se")}
    tw = parts["nw"].width
    th = parts["nw"].height
    cw = max(1, w - 2 * tw)
    ch = max(1, h - 2 * th)
    box = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    box.paste(parts["nw"], (0, 0))
    box.paste(parts["n"].resize((cw, th), Image.Resampling.NEAREST), (tw, 0))
    box.paste(parts["ne"], (tw + cw, 0))
    box.paste(parts["w"].resize((tw, ch), Image.Resampling.NEAREST), (0, th))
    box.paste(parts["c"].resize((cw, ch), Image.Resampling.NEAREST), (tw, th))
    box.paste(parts["e"].resize((tw, ch), Image.Resampling.NEAREST), (tw + cw, th))
    box.paste(parts["sw"], (0, th + ch))
    box.paste(parts["s"].resize((cw, th), Image.Resampling.NEAREST), (tw, th + ch))
    box.paste(parts["se"], (tw + cw, th + ch))
    canvas.alpha_composite(box, (x, y))


def _crop_center_background(bg: Image.Image, target_w: int, target_h: int) -> Image.Image:
    if bg.size == (target_w, target_h):
        return bg.convert("RGBA")
    src_w, src_h = bg.size
    scale = max(target_w / src_w, target_h / src_h)
    rw = max(target_w, int(round(src_w * scale)))
    rh = max(target_h, int(round(src_h * scale)))
    resized = bg.resize((rw, rh), Image.Resampling.LANCZOS)
    left = (rw - target_w) // 2
    top = (rh - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h)).convert("RGBA")


def render_preview(
    theme_dir: Path,
    preview_path: Path,
    parsed_fonts: dict[str, tuple],
    size: tuple[int, int] = (1280, 720),
) -> None:
    W, H = size
    canvas = _crop_center_background(Image.open(theme_dir / "background.png"), W, H)

    # + image
    logo = Image.open(theme_dir / "logo.png").convert("RGBA")
    canvas.alpha_composite(logo, (W // 2 - 170, H // 2 - 265))

    # + boot_menu exact gui_list.c geometry
    bm_x = W // 2 - 300
    bm_y = H // 2 - 110
    bm_w = 600
    bm_h = 312
    _draw_nine_slice_box(canvas, theme_dir, "menu", bm_x, bm_y, bm_w, bm_h)

    menu_pad = 12
    item_padding = 10
    item_height = 32
    item_spacing = 10
    icon_w = 24
    icon_space = 16
    sel_pad = 8

    content_x = bm_x + menu_pad + item_padding
    content_y = bm_y + menu_pad + item_padding
    content_w = bm_w - 2 * menu_pad - 2 * item_padding

    font_item = parsed_fonts["Roboto Regular 18"]
    ascent = font_item[1]["ascent"]
    descent = font_item[1]["descent"]
    text_top_offset = (item_height - (ascent + descent)) // 2 + ascent
    icon_top_offset = (item_height - 24) // 2

    entries = [
        ("cli.png", "KaaijkOS 1.1 (CLI)", True),
        ("kaaijkos.png", "KaaijkOS 1.1 (Graphical)", False),
        ("debug.png", "KaaijkOS 1.1 (Debug / Verbose Boot)", False),
        ("uefi.png", "UEFI Firmware Settings", False),
        ("restart.png", "Reboot", False),
        ("shutdown.png", "Power Off", False),
    ]

    num_shown = (bm_h + item_spacing - 2 * item_padding - 2 * sel_pad - 2 * menu_pad) // (item_height + item_spacing)
    item_top = content_y
    for idx, (icon_file, title, selected) in enumerate(entries[:num_shown]):
        if selected:
            _draw_nine_slice_box(
                canvas, theme_dir, "select",
                content_x, item_top, content_w, item_height + 2 * sel_pad,
            )
        icon = Image.open(theme_dir / "icons" / icon_file).convert("RGBA")
        canvas.alpha_composite(icon, (content_x + sel_pad, item_top + sel_pad + icon_top_offset))
        color = (255, 255, 255) if selected else (203, 213, 225)
        _draw_pf2_string(
            canvas,
            title,
            font_item,
            content_x + sel_pad + icon_w + icon_space,
            item_top + sel_pad + text_top_offset,
            color,
        )
        item_top += item_height + item_spacing

    # + label
    footer_font = parsed_fonts["Roboto Regular 14"]
    footer_text = "↑↓ Select   ·   Enter Boot   ·   e Edit   ·   c Console"
    fw = _measure_pf2_string(footer_text, footer_font)
    fx = (W - fw) // 2
    fy = int(H * 0.91) + footer_font[1]["ascent"]
    _draw_pf2_string(canvas, footer_text, footer_font, fx, fy, (148, 163, 184))

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(preview_path, format="PNG", optimize=True)
    print(f"  [OK] Preview {W}x{H} opgeslagen: {preview_path} (zichtbare menu-items={num_shown}/5)")


def _parse_size(text: str) -> tuple[int, int]:
    parts = text.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"Ongeldige resolutie '{text}', verwacht WxH (bv. 800x600)")
    w, h = int(parts[0]), int(parts[1])
    if w < 640 or h < 480:
        raise argparse.ArgumentTypeError("Minimum preview resolutie is 640x480")
    return w, h


def main() -> int:
    ap = argparse.ArgumentParser(description="Genereer het KaaijkOS GRUB 2.14 thema.")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Doelmap (standaard assets/grub-theme)")
    ap.add_argument("--fonts-dir", type=Path, default=None, help="Optionele map met TTF-fonts")
    ap.add_argument("--verify", action="store_true", help="Valideer PF2-fonts en alle thema-assets")
    ap.add_argument("--preview", type=Path, default=None, help="Schrijf een gesimuleerde GRUB preview PNG")
    ap.add_argument("--preview-size", type=_parse_size, default=(1280, 720), help="Resolutie voor --preview (bv. 800x600)")
    args = ap.parse_args()

    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    roboto_ttf = resolve_font_path(args.fonts_dir, ["Roboto-Regular.ttf", "DejaVuSans.ttf"])
    cascadia_ttf = resolve_font_path(args.fonts_dir, ["CascadiaMono.ttf", "DejaVuSansMono.ttf"])

    print(f"[kaaijkos-mkgrub-theme] Genereer assets in {out_dir}...")
    generate_background(out_dir / "background.png")
    generate_logo(out_dir / "logo.png")
    generate_nine_slices(out_dir)
    generate_icons(out_dir / "icons")

    build_pf2(out_dir / "kaaijkos-sans-18.pf2", "Roboto Regular 18", "Roboto", 18, roboto_ttf, cascadia_ttf)
    build_pf2(out_dir / "kaaijkos-sans-14.pf2", "Roboto Regular 14", "Roboto", 14, roboto_ttf, cascadia_ttf)
    build_pf2(out_dir / "kaaijkos-mono-16.pf2", "Cascadia Mono 16", "Cascadia Mono", 16, cascadia_ttf, roboto_ttf)

    with open(out_dir / "theme.txt", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(THEME_TXT)

    if args.verify or args.preview is not None:
        parsed_fonts = verify_theme(out_dir)
        if args.preview is not None:
            render_preview(out_dir, args.preview, parsed_fonts, size=args.preview_size)

    return 0


if __name__ == "__main__":
    sys.exit(main())
