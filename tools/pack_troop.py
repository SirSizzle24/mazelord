"""Packs a raw Sprite Baker output folder into game-ready sheets.

    python pack_troop.py <raw bake folder> <output folder>

For each clip (one <clip>.json plus <clip>_d0.._d7_color/_mask.png from the baker):
  - finds the smallest box that holds every frame of every direction, and crops all frames to it,
  - scales the frames down (SCALE) with an area filter (no ringing), treating the baked color as
    premultiplied (Unity renders it over a clear black background), so edges stay clean,
  - gives the soft edge pixels a mask region too: the mask pass has no anti-aliasing, so the outer
    ring of the color picture falls outside it; each such pixel takes the region next to it
    (otherwise they'd keep the original red and white and flicker around a recolored troop),
  - writes ONE sheet per clip, <clip>_color.png, directions stacked top to bottom (each direction
    starts on a new row), and <clip>_mask.png as a one-channel gray picture: 255 cap, 128 body,
    0 everything else (eyes, brows: left as they are),
  - writes <clip>.json with the packed frame size, columns, rows per direction, and the anchor: where
    the troop's feet (its origin) sit inside a packed frame, in pixels.
The portrait (portrait.json, portrait_color/_mask.png) is cropped and scaled the same way
(PORTRAIT_SCALE).

The anchor comes from the baker's camera: it aims at aim_height above the origin, at the frame's
middle, so the origin sits aim_height * cos(pitch) below the middle, in camera units.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

SCALE = 0.5
PORTRAIT_SCALE = 0.75
MAX_WIDTH = 4096
PAD = 2  # pixels kept around the used box, before scaling
# The baker's map camera, to place the feet. Keep in step with SpriteBaker's settings.
CAMERA_PITCH = 38.0
CAMERA_SIZE = 1.2  # orthographic half height, in world units
AIM_HEIGHT = 0.8


def load(path):
    return np.array(Image.open(path).convert("RGBA"))


def frames_of(sheet, info, rows):
    w, h = info["frame_width"], info["frame_height"]
    cols = info["columns"]
    out = []
    for i in range(info["frames"]):
        r, c = divmod(i, cols)
        out.append(sheet[r * h:(r + 1) * h, c * w:(c + 1) * w])
    return out


def used_box(all_frames):
    alpha = np.zeros(all_frames[0].shape[:2], bool)
    for f in all_frames:
        alpha |= f[..., 3] > 0
    ys, xs = np.where(alpha)
    h, w = alpha.shape
    return (max(xs.min() - PAD, 0), max(ys.min() - PAD, 0),
            min(xs.max() + 1 + PAD, w), min(ys.max() + 1 + PAD, h))


def shrink(channel, size):
    """Area-average one float channel down to size (no overshoot, unlike Lanczos)."""
    img = Image.fromarray(channel.astype(np.float32), "F")
    return np.array(img.resize(size, Image.BOX))


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def shrink_color(frame, size):
    """Unity blends the soft edge with the clear black background in linear light, then stores sRGB.
    So: back to linear (premultiplied there), average down, divide the alpha out, back to sRGB."""
    f = frame.astype(np.float32) / 255.0
    rgb = to_linear(f[..., :3])
    out = np.stack([shrink(rgb[..., k], size) for k in range(3)] + [shrink(f[..., 3], size)], -1)
    a = out[..., 3:4]
    # Where a pixel is all but transparent, its color barely matters: floor the alpha we divide by,
    # rather than blowing noise up into bright specks.
    out[..., :3] = np.where(a > 0.02, out[..., :3] / np.maximum(a, 0.02), 0)
    out[..., :3] = to_srgb(np.clip(out[..., :3], 0, 1))
    out[..., 3] = np.where(out[..., 3] < 0.02, 0, out[..., 3])
    return (np.clip(out, 0, 1) * 255).round().astype(np.uint8)


def regions(mask_frame, color_frame):
    """The mask as labels (255 cap, 128 body, 0 keep or empty), with the color's soft edge filled in."""
    label = np.zeros(mask_frame.shape[:2], np.uint8)
    label[mask_frame[..., 1] > 127] = 128
    label[mask_frame[..., 0] > 127] = 255
    covered = mask_frame[..., 3] > 127  # drawn in the mask pass (eyes and brows are covered, as 0)
    # Grow cap and body labels outward a few pixels into what the mask pass didn't cover.
    for _ in range(4):
        grown = label.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            shifted = np.roll(label, (dy, dx), (0, 1))
            grown = np.maximum(grown, np.where(covered, 0, shifted))
        label = np.where(covered, label, grown)
    return label


def shrink_mask(label, size):
    """Each small pixel takes the region most of its big pixels have (cap, body or keep)."""
    votes = [shrink((label == v).astype(np.float32), size) for v in (0, 128, 255)]
    return np.array((0, 128, 255), np.uint8)[np.argmax(np.stack(votes, -1), -1)]


def pack(raw, out, name, scale, directions, anchor_raw):
    info = json.load(open(os.path.join(raw, name + ".json")))
    dirs = list(range(directions))
    stem = (lambda d: f"{name}_d{d}") if directions > 1 else (lambda d: name)
    colors, masks = [], []
    for d in dirs:
        colors.append(frames_of(load(os.path.join(raw, stem(d) + "_color.png")), info, None))
        masks.append(frames_of(load(os.path.join(raw, stem(d) + "_mask.png")), info, None))
    x0, y0, x1, y1 = used_box([f for fs in colors for f in fs])
    fw = max(1, round((x1 - x0) * scale))
    fh = max(1, round((y1 - y0) * scale))
    frames = info["frames"]
    cols = min(frames, MAX_WIDTH // fw)
    rows_per_dir = math.ceil(frames / cols)
    color_sheet = np.zeros((rows_per_dir * fh * len(dirs), cols * fw, 4), np.uint8)
    mask_sheet = np.zeros((rows_per_dir * fh * len(dirs), cols * fw), np.uint8)
    for d in dirs:
        for i in range(frames):
            r, c = divmod(i, cols)
            y = (d * rows_per_dir + r) * fh
            x = c * fw
            color_sheet[y:y + fh, x:x + fw] = shrink_color(colors[d][i][y0:y1, x0:x1], (fw, fh))
            label = regions(masks[d][i][y0:y1, x0:x1], colors[d][i][y0:y1, x0:x1])
            mask_sheet[y:y + fh, x:x + fw] = shrink_mask(label, (fw, fh))
    Image.fromarray(color_sheet).save(os.path.join(out, name + "_color.png"), optimize=True)
    Image.fromarray(mask_sheet, "L").save(os.path.join(out, name + "_mask.png"), optimize=True)
    packed = {"frame_width": fw, "frame_height": fh, "frames": frames, "columns": cols,
              "rows_per_direction": rows_per_dir, "directions": len(dirs), "fps": info["fps"]}
    if anchor_raw is not None:
        packed["anchor"] = [round((anchor_raw[0] - x0) * scale, 2), round((anchor_raw[1] - y0) * scale, 2)]
    json.dump(packed, open(os.path.join(out, name + ".json"), "w"))
    return color_sheet.shape[1] * color_sheet.shape[0] * 5  # bytes in memory: RGBA + one-channel mask


def main():
    raw, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    total = 0
    for f in sorted(os.listdir(raw)):
        if not f.endswith(".json") or f.startswith("portrait") or f.startswith("Turn") or "preview" in f:
            continue
        name = f[:-5]
        if not os.path.exists(os.path.join(raw, name + "_d0_color.png")):
            continue
        info = json.load(open(os.path.join(raw, f)))
        w, h = info["frame_width"], info["frame_height"]
        px_per_unit = (h / 2) / CAMERA_SIZE
        anchor = (w / 2, h / 2 + AIM_HEIGHT * math.cos(math.radians(CAMERA_PITCH)) * px_per_unit)
        size = pack(raw, out, name, SCALE, info["directions"], anchor)
        total += size
        print(f"{name}: {size / 2**20:.1f} MB")
    if os.path.exists(os.path.join(raw, "portrait.json")):
        size = pack(raw, out, "portrait", PORTRAIT_SCALE, 1, None)
        print(f"portrait: {size / 2**20:.1f} MB")
    print(f"map sprites: {total / 2**20:.1f} MB in memory")


main()
