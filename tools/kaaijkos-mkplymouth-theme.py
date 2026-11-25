#!/usr/bin/env python3
"""
KaaijkOS 1.1 — Flicker-Free Boot Splash & Plymouth Theme Generator
Genereert:
  1. assets/grub-theme/boot-splash.png (800x600 #090d16 + exact gecentreerd KaaijkOS logo)
  2. assets/plymouth-theme/kaaijkos/ (logo.png, 36-frame K-spinner, kaaijkos.plymouth, kaaijkos.script)
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
GRUB_THEME_DIR = REPO_ROOT / "assets" / "grub-theme"
PLYMOUTH_THEME_DIR = REPO_ROOT / "assets" / "plymouth-theme" / "kaaijkos"

BG_RGB = (9, 13, 22)  # #090d16 exact match between GRUB & Plymouth
NUM_FRAMES = 36

# KaaijkOS K-logo gradient stops (cyan -> blue -> violet -> coral -> orange)
GRADIENT_STOPS = [
    (0.00, (34, 211, 238)),   # #22d3ee bright cyan (leading head)
    (0.28, (59, 130, 246)),   # #3b82f6 electric blue
    (0.55, (139, 92, 246)),   # #8b5cf6 vivid violet
    (0.80, (244, 63, 94)),    # #f43f5e coral pink
    (1.00, (251, 146, 60)),   # #fb923c warm orange (fading tail)
]

PLYMOUTH_DESC = """[Plymouth Theme]
Name=KaaijkOS
Description=KaaijkOS 1.1 Flicker-Free Boot Splash with K-Logo Spinner
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/kaaijkos
ScriptFile=/usr/share/plymouth/themes/kaaijkos/kaaijkos.script
"""

PLYMOUTH_SCRIPT = """# KaaijkOS 1.1 Plymouth Script — Flicker-free logo + K-based spinner
Window.SetBackgroundTopColor(0.0353, 0.0510, 0.0863);
Window.SetBackgroundBottomColor(0.0353, 0.0510, 0.0863);

win_w = Window.GetWidth();
win_h = Window.GetHeight();

# Match GRUB 800x600 boot-splash.png vertical scale cleanly (1:1 on 800x600, uniform on 1024x768+)
raw_logo = Image("logo.png");
scale = win_h / 600.0;
if (scale < 0.85) scale = 0.85;
if (scale > 1.65) scale = 1.65;

logo_w = Math.Int(raw_logo.GetWidth() * scale);
logo_h = Math.Int(raw_logo.GetHeight() * scale);
logo_img = raw_logo.Scale(logo_w, logo_h);

logo_sprite = Sprite(logo_img);
logo_sprite.SetX(Math.Int((win_w - logo_w) / 2));
logo_sprite.SetY(Math.Int((win_h - logo_h) / 2));
logo_sprite.SetZ(10);

# 36-frame K-inspired spinner right below the logo
num_frames = 36;
spinner_size = Math.Int(64 * scale);
if (spinner_size < 48) spinner_size = 48;
if (spinner_size > 96) spinner_size = 96;

for (i = 0; i < num_frames; i++) {
    if (i < 10)
        fname = "spinner-0" + i + ".png";
    else
        fname = "spinner-" + i + ".png";
    spinner_frames[i] = Image(fname).Scale(spinner_size, spinner_size);
}

spinner_sprite = Sprite(spinner_frames[0]);
spinner_sprite.SetX(Math.Int((win_w - spinner_size) / 2));
spinner_sprite.SetY(Math.Int((win_h + logo_h) / 2 + (32 * scale)));
spinner_sprite.SetZ(20);

# On boot, GRUB already drew the exact logo -> keep logo at 1.0 and fade-in spinner smoothly.
# On shutdown/reboot, fade-in both logo and spinner together from 0.0 -> 1.0.
mode = Plymouth.GetMode();
logo_fade_in = (mode == "shutdown" || mode == "reboot");
if (logo_fade_in)
    logo_sprite.SetOpacity(0.0);
else
    logo_sprite.SetOpacity(1.0);
spinner_sprite.SetOpacity(0.0);

tick = 0;
fade_in_ticks = 18;
fade_out_active = 0;
fade_out_tick = 0;
fade_out_ticks = 20;

fun ease_out(t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    inv = 1.0 - t;
    return 1.0 - (inv * inv * inv);
}

fun refresh_callback() {
    tick++;
    frame_idx = Math.Int(tick / 1.5) % num_frames;
    spinner_sprite.SetImage(spinner_frames[frame_idx]);

    if (fade_out_active) {
        fade_out_tick++;
        p = fade_out_tick / fade_out_ticks;
        op = 1.0 - ease_out(p);
        if (op < 0.0) op = 0.0;
        logo_sprite.SetOpacity(op);
        spinner_sprite.SetOpacity(op);
    } else if (tick <= fade_in_ticks) {
        op = ease_out(tick / fade_in_ticks);
        spinner_sprite.SetOpacity(op);
        if (logo_fade_in)
            logo_sprite.SetOpacity(op);
    } else {
        spinner_sprite.SetOpacity(1.0);
        logo_sprite.SetOpacity(1.0);
    }
}

Plymouth.SetRefreshFunction(refresh_callback);

fun status_callback(status) {
    if (status == "fadeout") {
        fade_out_active = 1;
        fade_out_tick = 0;
    }
}
Plymouth.SetUpdateStatusFunction(status_callback);

fun quit_callback() {
    logo_sprite.SetOpacity(0.0);
    spinner_sprite.SetOpacity(0.0);
}
Plymouth.SetQuitFunction(quit_callback);
"""


def _lerp_color(t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    for i in range(len(GRADIENT_STOPS) - 1):
        t0, c0 = GRADIENT_STOPS[i]
        t1, c1 = GRADIENT_STOPS[i + 1]
        if t0 <= t <= t1:
            u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            return (
                int(round(c0[0] + (c1[0] - c0[0]) * u)),
                int(round(c0[1] + (c1[1] - c0[1]) * u)),
                int(round(c0[2] + (c1[2] - c0[2]) * u)),
            )
    return GRADIENT_STOPS[-1][1]


def build_logo_image() -> Image.Image:
    """Create crisp 340x134 RGBA KaaijkOS logo matching GRUB theme logo."""
    splash_path = REPO_ROOT / "assets" / "boot" / "splash-kaaijkos.bmp"
    src = Image.open(splash_path).convert("RGBA")
    cropped = src.crop(src.getbbox())

    canvas_w, canvas_h = 340, 134
    max_w, max_h = 328, 122
    scale = min(max_w / cropped.width, max_h / cropped.height)
    new_w = max(1, int(round(cropped.width * scale)))
    new_h = max(1, int(round(cropped.height * scale)))
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)

    layer = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    layer.paste(resized, ((canvas_w - new_w) // 2, (canvas_h - new_h) // 2), resized)
    return layer


def build_grub_boot_splash(logo: Image.Image, out_path: Path) -> None:
    """800x600 solid #090d16 RGB PNG with exact centered 340x134 logo."""
    bg = Image.new("RGBA", (800, 600), (*BG_RGB, 255))
    bg.alpha_composite(logo, ((800 - logo.width) // 2, (600 - logo.height) // 2))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bg.convert("RGB").save(out_path, format="PNG", optimize=True)


def build_k_spinner_frames(out_dir: Path) -> list[Image.Image]:
    """Generate 36 high-DPI 64x64 RGBA frames of a K-emblem + orbiting K-gradient arc."""
    k_src = Image.open(REPO_ROOT / "assets" / "kaaijkos-logo-klein.png").convert("RGBA")
    k_crop = k_src.crop(k_src.getbbox())

    # 4x supersampling (256x256 -> 64x64) for ultra-smooth anti-aliased arcs
    S = 256
    cx, cy = S // 2, S // 2
    radius = 96
    stroke_r = 12
    arc_span_deg = 255.0
    arc_steps = 90

    # Prepare crisp mini-K centered inside 256x256 (~108px height)
    k_target = 104
    k_scale = min(k_target / k_crop.width, k_target / k_crop.height)
    kw = max(1, int(round(k_crop.width * k_scale)))
    kh = max(1, int(round(k_crop.height * k_scale)))
    k_small = k_crop.resize((kw, kh), Image.Resampling.LANCZOS)

    frames: list[Image.Image] = []
    for f in range(NUM_FRAMES):
        canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        draw = ImageDraw.Draw(canvas)

        # Subtle circular track ring
        draw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            outline=(56, 189, 248, 34),
            width=14,
        )

        # Orbiting K-gradient comet arc (clockwise)
        head_deg = (f * (360.0 / NUM_FRAMES)) - 90.0
        glow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow_layer)

        # Draw tail -> head so bright cyan head sits cleanly on top
        for step in range(arc_steps, -1, -1):
            frac = step / arc_steps  # 0.0 = bright head, 1.0 = faded tail
            ang = math.radians(head_deg - frac * arc_span_deg)
            px = cx + math.cos(ang) * radius
            py = cy + math.sin(ang) * radius
            rgb = _lerp_color(frac)
            alpha = int(round(255 * ((1.0 - frac) ** 1.35)))
            r_dot = max(4.5, stroke_r * (1.0 - 0.35 * frac))
            draw.ellipse(
                (px - r_dot, py - r_dot, px + r_dot, py + r_dot),
                fill=(*rgb, alpha),
            )
            if frac < 0.35:
                gr = r_dot * 1.9
                gdraw.ellipse(
                    (px - gr, py - gr, px + gr, py + gr),
                    fill=(*rgb, int(alpha * 0.28)),
                )

        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=10))
        canvas = Image.alpha_composite(glow_layer, canvas)

        # Subtle breathing opacity/glow on central K emblem
        pulse = 0.84 + 0.16 * (0.5 + 0.5 * math.sin(2.0 * math.pi * f / NUM_FRAMES))
        k_frame = k_small.copy()
        a_ch = k_frame.getchannel("A").point(lambda a: int(round(a * pulse)))
        k_frame.putalpha(a_ch)
        canvas.alpha_composite(k_frame, ((S - kw) // 2, (S - kh) // 2))

        final_im = canvas.resize((64, 64), Image.Resampling.LANCZOS)
        final_im.save(out_dir / f"spinner-{f:02d}.png", format="PNG", optimize=True)
        frames.append(final_im)

    return frames


def render_preview(boot_splash: Path, frames: list[Image.Image], preview_path: Path) -> None:
    """Render 800x600 Plymouth boot screen + zoomed 6-frame K-spinner strip below."""
    screen = Image.open(boot_splash).convert("RGBA")
    # Place frame 6 at exact Plymouth script coordinates: y = (600 + 134)/2 + 32 = 399
    screen.alpha_composite(frames[6], ((800 - 64) // 2, (600 + 134) // 2 + 32))

    # Add a clean strip at the bottom showing 6 evenly spaced spinner frames (2x zoom = 96px)
    strip_h = 132
    full = Image.new("RGB", (800, 600 + strip_h), (14, 20, 34))
    full.paste(screen.convert("RGB"), (0, 0))
    draw = ImageDraw.Draw(full)
    draw.line([(0, 600), (800, 600)], fill=(34, 211, 238), width=2)

    sample_ids = [0, 6, 12, 18, 24, 30]
    gap = 800 // len(sample_ids)
    for idx, fid in enumerate(sample_ids):
        zoom = frames[fid].resize((88, 88), Image.Resampling.LANCZOS)
        x = idx * gap + (gap - 88) // 2
        y = 600 + (strip_h - 88) // 2
        full.paste(zoom, (x, y), zoom)

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    full.save(preview_path, format="PNG", optimize=True)
    print(f"  [OK] Preview opgeslagen: {preview_path}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Genereer KaaijkOS boot-splash & Plymouth thema.")
    ap.add_argument("--preview", type=Path, default=None, help="Optioneel preview PNG pad")
    args = ap.parse_args()

    PLYMOUTH_THEME_DIR.mkdir(parents=True, exist_ok=True)
    logo = build_logo_image()
    logo.save(PLYMOUTH_THEME_DIR / "logo.png", format="PNG", optimize=True)

    boot_splash_path = GRUB_THEME_DIR / "boot-splash.png"
    build_grub_boot_splash(logo, boot_splash_path)

    frames = build_k_spinner_frames(PLYMOUTH_THEME_DIR)

    with open(PLYMOUTH_THEME_DIR / "kaaijkos.plymouth", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(PLYMOUTH_DESC)
    with open(PLYMOUTH_THEME_DIR / "kaaijkos.script", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(PLYMOUTH_SCRIPT)

    print(
        f"[kaaijkos-mkplymouth-theme] OK: boot-splash.png ({boot_splash_path.stat().st_size}B), "
        f"logo.png, {len(frames)} K-spinner frames, kaaijkos.plymouth & kaaijkos.script."
    )

    if args.preview is not None:
        render_preview(boot_splash_path, frames, args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
