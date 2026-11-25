#!/usr/bin/env python3
"""原汽水图标满幅 + 右下直角同色加号；并生成菜单栏黑色镂空模板托盘图。"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
  from PIL import Image, ImageDraw
except ImportError:
  print("需要 Pillow：python3 -m pip install pillow", file=sys.stderr)
  sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources" / "SodaPlus" / "Resources"
SODA_ICNS = Path("/Applications/汽水音乐.app/Contents/Resources/electron.icns")

PLUS_CX = 703
PLUS_CY = 718
PLUS_HALF_LEN = 100
PLUS_ARM = 28
PLUS_GAP = 10

STOPS = [
  (0.00, (0xC4, 0xFA, 0x45)),
  (0.28, (0x82, 0xFB, 0x43)),
  (0.50, (0x38, 0xFD, 0x43)),
  (0.72, (0x25, 0xFD, 0x83)),
  (1.00, (0x23, 0xFA, 0xBE)),
]


def lerp(a: float, b: float, t: float) -> float:
  return a + (b - a) * t


def gradient_color(t: float):
  t = max(0.0, min(1.0, t))
  for i in range(len(STOPS) - 1):
    t0, c0 = STOPS[i]
    t1, c1 = STOPS[i + 1]
    if t0 <= t <= t1:
      u = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
      return tuple(int(lerp(c0[j], c1[j], u)) for j in range(3))
  return STOPS[-1][1]


def load_soda_master() -> Image.Image:
  if not SODA_ICNS.is_file():
    raise FileNotFoundError(f"未找到汽水音乐图标：{SODA_ICNS}")
  tmp = Path(tempfile.mkdtemp(prefix="soda-iconset-"))
  try:
    iconset = tmp / "soda.iconset"
    subprocess.run(["iconutil", "-c", "iconset", str(SODA_ICNS), "-o", str(iconset)], check=True)
    largest = iconset / "icon_512x512@2x.png"
    if not largest.is_file():
      pngs = sorted(iconset.glob("*.png"), key=lambda p: p.stat().st_size, reverse=True)
      largest = pngs[0]
    return Image.open(largest).convert("RGBA")
  finally:
    shutil.rmtree(tmp, ignore_errors=True)


def draw_sharp_plus(img, cx, cy, half_len, arm, fill) -> None:
  d = ImageDraw.Draw(img)
  d.rectangle([cx - arm, cy - half_len, cx + arm, cy + half_len], fill=fill)
  d.rectangle([cx - half_len, cy - arm, cx + half_len, cy + arm], fill=fill)


def composite(soda: Image.Image, size: int) -> Image.Image:
  master_w = soda.size[0]
  scale = size / master_w
  base = soda.resize((size, size), Image.Resampling.LANCZOS) if size != master_w else soda.copy()
  cx = int(round(PLUS_CX * scale))
  cy = int(round(PLUS_CY * scale))
  hl = max(2, int(round(PLUS_HALF_LEN * scale)))
  ar = max(1, int(round(PLUS_ARM * scale)))
  gp = max(1, int(round(PLUS_GAP * scale)))
  layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
  knock = Image.new("L", (size, size), 0)
  plusm = Image.new("L", (size, size), 0)
  draw_sharp_plus(knock, cx, cy, hl + gp, ar + gp, 255)
  draw_sharp_plus(plusm, cx, cy, hl, ar, 255)
  lp, km, pm = layer.load(), knock.load(), plusm.load()
  top, bot = cy - hl, cy + hl
  for y in range(max(0, cy - (hl + gp)), min(size, cy + (hl + gp) + 1)):
    t = (y - top) / max(1, bot - top)
    r, g, b = gradient_color(max(0.0, min(1.0, t)))
    for x in range(max(0, cx - (hl + gp)), min(size, cx + (hl + gp) + 1)):
      if pm[x, y]:
        lp[x, y] = (r, g, b, 255)
      elif km[x, y]:
        lp[x, y] = (0, 0, 0, 255)
  out = base.copy()
  out.alpha_composite(layer)
  return out


def to_template_silhouette(color_icon: Image.Image, out_size: int) -> Image.Image:
  """彩色图标 → 菜单栏黑色镂空模板（RGB 黑 + alpha 外形，含设计镂空）。"""
  im = color_icon.convert("RGBA")
  w, h = im.size
  px = im.load()
  mask = Image.new("L", (w, h), 0)
  mp = mask.load()
  xs: list[int] = []
  ys: list[int] = []
  for y in range(h):
    for x in range(w):
      r, g, b, a = px[x, y]
      if a < 32 or r + g + b < 40:
        continue
      mp[x, y] = 255
      xs.append(x)
      ys.append(y)
  if not xs:
    return Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
  x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
  pad = max(2, int(max(x1 - x0, y1 - y0) * 0.06))
  x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
  x1, y1 = min(w - 1, x1 + pad), min(h - 1, y1 + pad)
  cropped = mask.crop((x0, y0, x1 + 1, y1 + 1))
  cw, ch = cropped.size
  # 铺满托盘槽位，再整体下移（顶部可裁切）
  scale = out_size / max(cw, ch)
  nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
  nw, nh = min(nw, out_size), min(nh, out_size)
  fitted = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
  canvas = Image.new("L", (out_size, out_size), 0)
  ox = (out_size - nw) // 2
  # 相对居中略下移（少于 1/8，多于居中）
  shift = max(1, out_size // 14)
  oy = (out_size - nh) // 2 + shift
  canvas.paste(fitted, (ox, oy))
  out = Image.new("RGBA", (out_size, out_size), (0, 0, 0, 0))
  op, cp = out.load(), canvas.load()
  for y in range(out_size):
    for x in range(out_size):
      a = cp[x, y]
      if a:
        op[x, y] = (0, 0, 0, a)
  return out



def main() -> None:
  OUT.mkdir(parents=True, exist_ok=True)
  print(f"读取：{SODA_ICNS}")
  soda = load_soda_master()
  master = composite(soda, 1024)
  master.save(OUT / "AppIcon-1024.png")
  iconset = OUT / "AppIcon.iconset"
  if iconset.exists():
    shutil.rmtree(iconset)
  iconset.mkdir()
  for px, name in [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
  ]:
    composite(soda, px).save(iconset / name)
  icns = OUT / "AppIcon.icns"
  subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
  shutil.rmtree(iconset)

  for sz, name in [(16, "TrayIcon-16.png"), (32, "TrayIcon-32.png")]:
    to_template_silhouette(master, sz).save(OUT / name)
    print(f"托盘模板 {name}")

  # 清理不再使用的侧栏切图
  for name in ("SidebarIcon-36.png", "SidebarIcon-72.png", "SidebarIcon-144.png"):
    path = OUT / name
    if path.exists():
      path.unlink()

  print(f"写入 {icns}")


if __name__ == "__main__":
  main()
